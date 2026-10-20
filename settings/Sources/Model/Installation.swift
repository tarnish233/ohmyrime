//
//  Installation.swift
//  鼠须管设置
//
//  The app installs ohmyrime too. It carries ohmyrime's Squirrel and rime-ice
//  (scripts/build-settings.sh puts them in Contents/Resources/Payload) and runs the bundled
//  scripts/install.sh, the script the command line uses. Here: what it carries, what is installed,
//  and the script runner. What needs the system (input sources, processes) is in InstallState.
//

import CryptoKit
import Foundation
import Observation

/// What the app carries, and its scripts.
enum Payload {
  /// The app's resources; the repository's build in tests.
  nonisolated(unsafe) static var resources: URL? = Bundle.main.resourceURL
  nonisolated(unsafe) static var info: [String: Any] = Bundle.main.infoDictionary ?? [:]

  static func resource(_ path: String) -> URL? {
    guard let url = resources?.appending(path: path), FileManager.default.fileExists(atPath: url.path) else { return nil }
    return url
  }

  static var squirrelArchive: URL? { resource("Payload/Squirrel.zip") }
  static var rimeIceArchive: URL? { resource("Payload/rime-ice.zip") }
  static var installScript: URL? { resource("scripts/install.sh") }
  static var uninstallScript: URL? { resource("scripts/uninstall.sh") }

  /// SHA-256 of the carried Squirrel's executable: the installed one is the same if its hash is.
  static var squirrelHash: String? { info["OhmyrimeSquirrelHash"] as? String }
  /// The carried rime-ice's version, such as "2026-03-08".
  static var rimeIceVersion: String? { info["OhmyrimeRimeIceVersion"] as? String }
  static var version: String { info["CFBundleShortVersionString"] as? String ?? "" }

  static var canInstall: Bool { squirrelArchive != nil && installScript != nil && squirrelHash != nil }
}

/// What install.sh wrote last: ~/Library/Application Support/鼠须管设置/installed.json.
struct InstallMarker: Codable, Equatable {
  var version: String
  var squirrelHash: String
  var date: String?

  static var url: URL { RimePaths.supportDir.appending(component: "installed.json") }

  static func read(_ url: URL = url) -> InstallMarker? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(Self.self, from: data)
  }
}

/// The installed Squirrel compared with the one the app carries.
enum SquirrelStatus: Equatable {
  /// Not installed.
  case missing
  /// The one the app carries.
  case current
  /// Another build: an older ohmyrime, or the official Squirrel. Installing replaces it.
  case other
  /// Installed by a newer ohmyrime: this app has nothing to offer.
  case newer

  static func of(installedHash: String?, carriedHash: String?, marker: InstallMarker?, version: String) -> SquirrelStatus {
    guard let installedHash else { return .missing }
    // Built without the payload: nothing to compare with.
    guard let carriedHash else { return .current }
    if installedHash == carriedHash {
      return .current
    }
    if let marker, marker.squirrelHash == installedHash, isVersion(marker.version, newerThan: version) {
      return .newer
    }
    return .other
  }

  /// "0.10.0" is newer than "0.9.1".
  static func isVersion(_ version: String, newerThan other: String) -> Bool {
    !version.isEmpty && version.compare(other, options: .numeric) == .orderedDescending
  }

  /// A file's SHA-256, in hex.
  static func hash(of url: URL) -> String? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

/// Squirrel and the system's record of the input sources the user added.
enum InputSourceRecord {
  static let squirrelBundle = "im.rime.inputmethod.Squirrel"
  static let squirrelHans = "im.rime.inputmethod.Squirrel.Hans"

  /// Whether a list of input sources the user added (macOS 27: com.apple.inputsources'
  /// AppleEnabledThirdPartyInputSources; earlier: com.apple.HIToolbox's AppleEnabledInputSources)
  /// has Squirrel. nil when there is no such list.
  static func hasSquirrel(_ list: Any?) -> Bool? {
    guard let list = list as? [[String: Any]] else { return nil }
    return list.contains { ($0["Bundle ID"] as? String) == squirrelBundle }
  }

  /// Whether the system remembers that the user added Squirrel, so that it is still there after
  /// logging in again; nil when it keeps no list we can read.
  static func remembersSquirrel() -> Bool? {
    var found: Bool?
    for (key, domain) in [("AppleEnabledThirdPartyInputSources", "com.apple.inputsources"), ("AppleEnabledInputSources", "com.apple.HIToolbox")] {
      CFPreferencesAppSynchronize(domain as CFString)
      if let has = hasSquirrel(CFPreferencesCopyAppValue(key as CFString, domain as CFString)) {
        if has { return true }
        found = false
      }
    }
    return found
  }
}

/// Runs one of the bundled scripts (install.sh, uninstall.sh), showing its steps: the lines that
/// start with "==> ".
@MainActor @Observable
final class ScriptRunner {
  enum Phase: Equatable {
    case idle, running, finished
    case failed(String)
  }

  private(set) var phase: Phase = .idle
  private(set) var steps: [String] = []
  private(set) var log: [String] = []
  @ObservationIgnored private var pending = Data()
  @ObservationIgnored private var streamOpen = false

  var isRunning: Bool { phase == .running }

  /// Why the last run failed, if it did.
  var failure: String? {
    switch phase {
    case .failed(let message): message
    default: nil
    }
  }

  /// Runs `script` with bash; returns whether it succeeded.
  func run(_ script: URL, arguments: [String] = [], environment extra: [String: String] = [:]) async -> Bool {
    guard phase != .running else { return false }
    phase = .running
    steps = []
    log = []
    pending = Data()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path] + arguments
    var environment = ProcessInfo.processInfo.environment
    // install.sh and uninstall.sh close other copies of this app, not this one.
    environment["OHMYRIME_APP_PID"] = String(ProcessInfo.processInfo.processIdentifier)
    environment.merge(extra) { $1 }
    process.environment = environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    streamOpen = true
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
      }
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.received(data) }
      }
    }
    do {
      try process.run()
    } catch {
      phase = .failed("没能运行 \(script.lastPathComponent)：\(error.localizedDescription)")
      return false
    }
    while process.isRunning {
      try? await Task.sleep(for: .milliseconds(100))
    }
    // The rest of the output, unless something the script started (open) holds the pipe.
    let deadline = Date().addingTimeInterval(2)
    while streamOpen && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(50))
    }
    if !pending.isEmpty {
      handle(String(decoding: pending, as: UTF8.self))
      pending = Data()
    }
    if process.terminationStatus == 0 {
      phase = .finished
      return true
    }
    phase = .failed(Self.explain(status: process.terminationStatus, log: log))
    return false
  }

  private func received(_ data: Data) {
    guard !data.isEmpty else {
      streamOpen = false
      return
    }
    pending += data
    while let end = pending.firstIndex(of: 10) {
      handle(String(decoding: pending[pending.startIndex..<end], as: UTF8.self))
      pending = Data(pending[pending.index(after: end)...])
    }
  }

  private func handle(_ line: String) {
    let line = line.trimmingCharacters(in: .whitespaces)
    guard !line.isEmpty else { return }
    log.append(line)
    if line.hasPrefix("==> ") {
      steps.append(String(line.dropFirst(4)))
    }
  }

  /// For snapshots: shows a state without running anything.
  func show(_ phase: Phase, steps: [String] = [], log: [String] = []) {
    self.phase = phase
    self.steps = steps
    self.log = log
  }

  /// Why the script failed, for the page.
  nonisolated static func explain(status: Int32, log: [String]) -> String {
    // osascript: "execution error: User canceled. (-128)" (用户已取消).
    if log.contains(where: { $0.contains("(-128)") }) {
      return "没有输入管理员密码，已取消。"
    }
    if let last = log.last(where: { !$0.hasPrefix("==> ") }) {
      return last
    }
    return "脚本出错（退出码 \(status)）"
  }
}
