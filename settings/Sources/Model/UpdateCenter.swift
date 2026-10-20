//
//  UpdateCenter.swift
//  鼠须管设置
//
//  Checking for a new ohmyrime (once a day by itself, or when asked) and installing it: download
//  the release, check its SHA-256 against the one published beside it, unpack it, check its
//  signature, swap it for this app, and start the new one.
//

import AppKit
import CryptoKit
import Observation

@MainActor @Observable
final class UpdateCenter {
  enum Phase: Equatable {
    case idle
    case checking
    case upToDate(Date)
    case available(UpdateCheck.Release)
    case failed(String)
  }

  /// What installing the download is doing.
  enum Install: Equatable {
    case idle
    case downloading
    case verifying
    case replacing
    case failed(String)
  }

  private static let lastCheckKey = "OhmyrimeLastUpdateCheck"
  private static let interval: TimeInterval = 24 * 60 * 60

  private(set) var phase: Phase = .idle
  private(set) var install: Install = .idle
  /// Whether a check runs now.
  var isChecking: Bool { phase == .checking }
  /// Why installing failed, if it did.
  var installFailure: String? {
    if case .failed(let message) = install { return message }
    return nil
  }
  /// The release to offer, if there is one.
  var release: UpdateCheck.Release? {
    if case .available(let release) = phase { return release }
    return nil
  }

  private var started = false

  /// One per app: the menu, the About window and the banner all talk to it.
  static let shared = UpdateCenter()

  /// The update check a launched app runs by itself: once a day, quietly. Failures stay quiet
  /// too; only a check the user asked for shows them.
  func checkIfDue() async {
    guard !started else { return }
    started = true
    let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
    guard last == nil || Date().timeIntervalSince(last!) > Self.interval else { return }
    await check(userInitiated: false)
  }

  func check(userInitiated: Bool = true) async {
    guard phase != .checking, install == .idle else { return }
    phase = .checking
    let outcome = await UpdateCheck.check(currentVersion: Payload.version)
    UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
    switch outcome {
    case .upToDate(let current):
      phase = .upToDate(Date())
    case .available(let release):
      phase = .available(release)
    case .failed(let reason):
      // A quiet check that fails is not worth an alarm: the next launch tries again.
      phase = userInitiated ? .failed(reason) : .idle
    }
  }

  // MARK: Installing

  /// Downloads the newest release, checks it, and puts it in place of this app.
  func installRelease() async {
    guard let release, install == .idle else { return }
    install = .downloading
    do {
      guard let archiveURL = UpdateCheck.assetURL("ohmyrime.zip") else {
        throw UpdateError.message("发布包地址不对")
      }
      let (downloaded, downloadResponse) = try await Self.download(archiveURL)
      if let http = downloadResponse as? HTTPURLResponse, http.statusCode != 200 {
        throw UpdateError.message("下载失败（\(http.statusCode)）")
      }
      install = .verifying
      try await Self.verifyChecksum(of: downloaded)
      let app = try Self.unpack(downloaded, expecting: release)
      try Self.verifySignature(of: app)
      install = .replacing
      try Self.replaceThisApp(with: app)
      // Starts by itself after the swap; quitting here leaves the new one running.
      Self.relaunch()
    } catch {
      install = .failed(error.localizedDescription)
    }
  }

  private enum UpdateError: LocalizedError {
    case message(String)

    var errorDescription: String? {
      switch self {
      case .message(let text): text
      }
    }
  }

  private static func download(_ url: URL) async throws -> (URL, URLResponse?) {
    let session = URLSession(configuration: UpdateCheck.sessionConfiguration())
    defer { session.invalidateAndCancel() }
    return try await session.download(from: url)
  }

  /// The zip must match the SHA-256 published beside it, or nothing is installed.
  private static func verifyChecksum(of archive: URL) async throws {
    guard let checksumURL = UpdateCheck.assetURL("ohmyrime.zip.sha256") else {
      throw UpdateError.message("发布包地址不对")
    }
    let session = URLSession(configuration: UpdateCheck.sessionConfiguration())
    defer { session.invalidateAndCancel() }
    let (data, _) = try await session.data(from: checksumURL)
    guard let expected = UpdateCheck.parseChecksum(String(decoding: data, as: UTF8.self)) else {
      throw UpdateError.message("发布的校验值读不出来")
    }
    guard let actual = try sha256(of: archive) else {
      throw UpdateError.message("下载的文件读不出来")
    }
    guard actual == expected else {
      throw UpdateError.message("下载的文件和发布的校验值不一致，没有安装")
    }
  }

  private static func sha256(of url: URL) throws -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  /// Unpacks the zip into a temporary folder and returns the app inside.
  private static func unpack(_ archive: URL, expecting release: UpdateCheck.Release) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "ohmyrime-update-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try run("/usr/bin/ditto", ["-x", "-k", archive.path, folder.path])
    let apps = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    guard let app = apps.first(where: { $0.pathExtension == "app" }) else {
      throw UpdateError.message("下载的包里没有 App")
    }
    let plist = app.appending(components: "Contents", "Info.plist")
    let bundle = Bundle(url: app)
    guard let version = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String else {
      throw UpdateError.message("下载的 App 没有版本号")
    }
    guard UpdateCheck.versionsMatch(version, release.shortVersion) else {
      throw UpdateError.message("下载的是 \(version)，不是 \(release.shortVersion)")
    }
    guard FileManager.default.isExecutableFile(atPath: plist.deletingLastPathComponent().appending(component: "MacOS").appending(component: "SquirrelSettings").path) else {
      throw UpdateError.message("下载的 App 不完整")
    }
    return app
  }

  /// Apple silicon runs only signed code; an unsigned or tampered copy is refused here.
  private static func verifySignature(of app: URL) throws {
    do {
      try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    } catch {
      throw UpdateError.message("下载的 App 签名不对，没有安装")
    }
  }

  /// Swaps the download for this app, in the same folder: the old one goes aside first, and comes
  /// back if the new one cannot take its place.
  private static func replaceThisApp(with downloaded: URL) throws {
    let target = Bundle.main.bundleURL
    let folder = target.deletingLastPathComponent()
    guard target.pathExtension == "app" else {
      throw UpdateError.message("这个 App 不是从 .app 里运行的，请手动下载新版")
    }
    guard FileManager.default.isWritableFile(atPath: folder.path) else {
      throw UpdateError.message("没有权限改写 \(folder.path)，把 App 放进「应用程序」后再更新")
    }
    let staging = folder.appending(path: ".\(target.lastPathComponent).new")
    let backup = folder.appending(path: ".\(target.lastPathComponent).old")
    let manager = FileManager.default
    try? manager.removeItem(at: staging)
    try? manager.removeItem(at: backup)
    try run("/usr/bin/ditto", [downloaded.path, staging.path])
    // A download of this app comes with it, and an input method's helper must not be quarantined.
    try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staging.path])
    do {
      try manager.moveItem(at: target, to: backup)
      do {
        try manager.moveItem(at: staging, to: target)
      } catch {
        try? manager.moveItem(at: backup, to: target)
        throw error
      }
    } catch {
      try? manager.removeItem(at: staging)
      throw UpdateError.message("没能替换 App：\(error.localizedDescription)")
    }
    try? manager.removeItem(at: backup)
  }

  private static func relaunch() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
  }

  private static func run(_ tool: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let error = Pipe()
    process.standardError = error
    process.standardOutput = Pipe()
    do {
      try process.run()
    } catch {
      throw UpdateError.message("没能运行 \(tool)")
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let text = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw UpdateError.message(text.isEmpty ? "\(tool) 出错（\(process.terminationStatus)）" : text)
    }
  }

  /// For tests and snapshots: shows a state without doing anything.
  func show(_ phase: Phase, install: Install = .idle) {
    self.phase = phase
    self.install = install
  }
}
