//
//  RimeIceInstaller.swift
//  鼠须管设置
//
//  Installs or updates rime-ice (雾凇拼音) with ohmyrime's scripts/rime-ice.sh, which is bundled
//  in the app, so that the app and the command line do it the same way: download the latest
//  release (or take the copy the app carries), back up the user folder, copy rime-ice in, keeping
//  the user's own files. No proxy of its own: curl goes the way the user's environment says.
//

import Foundation
import Observation

@MainActor @Observable
final class RimeIceInstaller {
  /// Where rime-ice comes from.
  enum Source: Equatable {
    /// The latest release, from GitHub.
    case download
    /// The last download, in cacheDir.
    case cache
    /// A full.zip: the one the app carries.
    case archive(URL)

    var arguments: [String] {
      switch self {
      case .download: []
      case .cache: ["--offline"]
      case .archive(let url): ["--from", url.path]
      }
    }
  }

  enum Phase: Equatable {
    case idle
    /// With curl's progress, once it has given one.
    case downloading(Double?)
    case installing
    case finished
    case failed(String)
    case cancelled
  }

  private(set) var phase: Phase = .idle
  /// What the script printed, without curl's progress bar.
  private(set) var log: [String] = []
  /// When the last run succeeded.
  private(set) var finishedAt: Date?
  /// What the last run came to, such as "已安装雾凇拼音（2026-03-08）".
  var summary: String?

  /// The script and ohmyrime's config templates: the app's own (scripts/build-settings.sh copies
  /// them in), or the repository's in tests.
  nonisolated(unsafe) static var script = Bundle.main.url(forResource: "rime-ice", withExtension: "sh", subdirectory: "scripts")
  nonisolated(unsafe) static var templates = Bundle.main.resourceURL?.appending(component: "rime")
  /// Where the download is kept.
  nonisolated(unsafe) static var cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appending(components: "im.rime.ohmyrime.settings", "rime-ice")

  @ObservationIgnored private var process: Process?
  /// show() pretends a download runs, so that the snapshot has the cancel button.
  private var showsRunning = false
  @ObservationIgnored private var cancelled = false
  /// Output not yet ending in a line break, per stream (true: stderr).
  @ObservationIgnored private var pending: [Bool: Data] = [:]
  @ObservationIgnored private var openStreams = 0

  var isRunning: Bool {
    switch phase {
    case .downloading, .installing: true
    default: false
    }
  }

  /// Only the download can be stopped: half a copy would be worse than either.
  var canCancel: Bool {
    switch phase {
    case .downloading: process != nil || showsRunning
    default: false
    }
  }

  /// Shows that an install starts, while the app saves first.
  func willRun() {
    guard process == nil else { return }
    log = []
    summary = nil
    finishedAt = nil
    showsRunning = false
    phase = .downloading(nil)
  }

  /// Runs the script, backing the user folder up into `backupDir`; returns whether it succeeded.
  func run(from source: Source = .download, backupDir: URL) async -> Bool {
    guard process == nil else { return false }
    guard let script = Self.script, FileManager.default.fileExists(atPath: script.path) else {
      phase = .failed("App 里没有安装脚本 rime-ice.sh，请用 scripts/build-settings.sh 重新构建。")
      return false
    }
    log = []
    summary = nil
    finishedAt = nil
    cancelled = false
    pending = [:]
    phase = source == .download ? .downloading(nil) : .installing

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path] + source.arguments
    var environment = ProcessInfo.processInfo.environment
    environment["OHMYRIME_RIME_DIR"] = RimePaths.userDir.path
    environment["OHMYRIME_CACHE_DIR"] = Self.cacheDir.path
    environment["OHMYRIME_BACKUP_DIR"] = backupDir.path
    // The app deploys by itself, and hears how it went.
    environment["OHMYRIME_NO_RELOAD"] = "1"
    if let templates = Self.templates {
      environment["OHMYRIME_TEMPLATES_DIR"] = templates.path
    }
    process.environment = environment
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    openStreams = 2
    for (pipe, isError) in [(output, false), (errors, true)] {
      pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
        let data = handle.availableData
        if data.isEmpty {
          handle.readabilityHandler = nil
        }
        // The main queue keeps the order the output came in.
        DispatchQueue.main.async {
          MainActor.assumeIsolated { self?.received(data, isError: isError) }
        }
      }
    }
    do {
      try process.run()
    } catch {
      phase = .failed("没能运行安装脚本：\(error.localizedDescription)")
      return false
    }
    self.process = process
    while process.isRunning {
      try? await Task.sleep(for: .milliseconds(100))
    }
    // The rest of the output, unless something the script started holds the pipes open.
    let deadline = Date().addingTimeInterval(2)
    while openStreams > 0 && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(50))
    }
    for isError in [false, true] {
      if let rest = pending[isError], !rest.isEmpty {
        handle(String(decoding: rest, as: UTF8.self), isError: isError)
      }
    }
    pending = [:]
    self.process = nil

    if cancelled {
      try? FileManager.default.removeItem(at: Self.cacheDir.appending(component: "full.zip.part"))
      log.append("已取消")
      phase = .cancelled
      return false
    }
    guard process.terminationStatus == 0 else {
      phase = .failed(Self.explain(status: process.terminationStatus, log: log))
      return false
    }
    finishedAt = Date()
    phase = .finished
    return true
  }

  /// Stops the download. curl is the script's child: find it first (once the script is gone it
  /// would belong to launchd), stop the script while curl still runs, so that it cannot take
  /// curl's end for a failed download and go on to the next try, then stop curl.
  func cancel() {
    guard canCancel, let process, process.isRunning else {
      if showsRunning {
        show(.cancelled)
      }
      return
    }
    cancelled = true
    let children = Self.children(of: process.processIdentifier)
    process.terminate()
    for child in children {
      kill(child, SIGTERM)
    }
  }

  private static func children(of pid: Int32) -> [Int32] {
    let pgrep = Process()
    pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    pgrep.arguments = ["-P", String(pid)]
    let pipe = Pipe()
    pgrep.standardOutput = pipe
    guard (try? pgrep.run()) != nil else { return [] }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    pgrep.waitUntilExit()
    return String(decoding: output, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { Int32($0) }
  }

  /// For the snapshots: shows a phase without running anything.
  func show(_ phase: Phase, log: [String] = []) {
    guard process == nil else { return }
    showsRunning = phase != .idle
    self.phase = phase
    self.log = log
    finishedAt = phase == .finished ? Date() : nil
  }

  // MARK: Output

  private func received(_ data: Data, isError: Bool) {
    guard !data.isEmpty else {
      openStreams -= 1
      return
    }
    // Lines end in \n; curl redraws its bar after \r. Neither byte can be inside a UTF-8 character.
    var buffer = (pending[isError] ?? Data()) + data
    if let end = buffer.lastIndex(where: { $0 == 10 || $0 == 13 }) {
      let complete = String(decoding: buffer[buffer.startIndex...end], as: UTF8.self)
      buffer = Data(buffer[buffer.index(after: end)...])
      for segment in complete.components(separatedBy: CharacterSet(charactersIn: "\r\n")) {
        handle(segment, isError: isError)
      }
    }
    pending[isError] = buffer
    // curl draws a bar and sends the \r only before the next one: show it now.
    if isError, let fraction = Self.progress(in: String(decoding: buffer, as: UTF8.self)) {
      update(fraction)
    }
  }

  private func handle(_ segment: String, isError: Bool) {
    if isError {
      if let fraction = Self.progress(in: segment) {
        update(fraction)
        return
      }
      // curl's spinner while it does not know the size yet ("#=#=#", "##O#-#").
      if segment.allSatisfy({ "#=O-# ".contains($0) }) {
        return
      }
    }
    let line = segment.trimmingCharacters(in: .whitespaces)
    guard !line.isEmpty else { return }
    // curl wraps its warnings, starting each piece with "Warning: ".
    if line.hasPrefix("Warning: "), let last = log.last, last.hasPrefix("Warning: "), !last.hasSuffix(".") {
      log[log.count - 1] = last + " " + line.dropFirst("Warning: ".count)
      return
    }
    log.append(line)
    if line.hasPrefix("解压：") {
      phase = .installing
    }
  }

  private func update(_ fraction: Double) {
    if case .downloading = phase {
      phase = .downloading(fraction)
    }
  }

  /// The share done in curl -#'s bar: "######        42.3%".
  nonisolated static func progress(in text: String) -> Double? {
    guard let match = text.wholeMatch(of: /[#\s]*([0-9]{1,3}(?:\.[0-9]+)?)%\s*/), let value = Double(match.1) else { return nil }
    return min(1, value / 100)
  }

  /// Why the script failed, for the page.
  nonisolated static func explain(status: Int32, log: [String]) -> String {
    if let curl = log.last(where: { $0.hasPrefix("curl:") }) {
      if curl.contains("(22)") {
        return "下载失败，服务器返回错误，稍后再试。（\(curl)）"
      }
      return "连不上 GitHub，检查网络后再试。（\(curl)）"
    }
    if let last = log.last(where: { !$0.hasPrefix("下载：") && !$0.hasPrefix("解压：") }) {
      return "安装没有完成：\(last)"
    }
    return "安装脚本出错（退出码 \(status)）"
  }
}
