//
//  Deployer.swift
//  鼠须管设置
//
//  Asks the running Squirrel to deploy (quietly: the settings app saves after every change), or
//  only to reload its look, and hears how it went.
//

import AppKit
import Observation

@MainActor @Observable
final class Deployer {
  enum State: Equatable {
    case idle
    case deploying
    case succeeded(Date)
    case failed(Date)
    /// Squirrel did not answer: not running, or a Squirrel without the settings app support.
    case noAnswer
  }

  static let squirrelIdentifier = "im.rime.inputmethod.Squirrel"
  private(set) var state: State = .idle
  /// Error lines Rime logged during the last deploy.
  private(set) var errors: [String] = []
  private var startedAt = Date.distantPast
  private var timeout: Task<Void, Never>?
  /// When the last deploy ended.
  private(set) var lastFinish: Date?
  /// Files saved for the running deploy, and whether it was asked for again.
  private var savedFiles = [URL]()
  private var retried = false
  /// The running request only reloads Squirrel's look.
  private var styleOnly = false
  /// What Squirrel said last: success, failure, unchanged, or reloaded (the look only).
  private(set) var lastOutcome: String?
  /// How long the last request took Squirrel, from asking to its answer.
  var lastDuration: TimeInterval? { lastFinish.map { $0.timeIntervalSince(startedAt) } }
  private var observer: NSObjectProtocol?

  init() {
    observer = DistributedNotificationCenter.default().addObserver(forName: .init("SquirrelDeployDidFinishNotification"), object: nil, queue: .main) { [weak self] note in
      let outcome = note.object as? String
      MainActor.assumeIsolated { self?.finished(outcome) }
    }
  }

  var isSquirrelRunning: Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: Self.squirrelIdentifier).isEmpty
  }

  /// Rime notices changed files by their time stamps, to the second: a file saved in the second
  /// the last deploy ended in counts as unchanged. Until then, saving should wait.
  var nextSafeSave: Date? {
    guard let lastFinish else { return nil }
    let next = Date(timeIntervalSince1970: lastFinish.timeIntervalSince1970.rounded(.down) + 1.05)
    return next > Date() ? next : nil
  }

  /// Asks Squirrel to deploy; no answer within `seconds` shows as noAnswer. `styleOnly`: only the
  /// look changed (squirrel.custom.yaml's style), so Squirrel rebuilds build/squirrel.yaml and
  /// reloads the look without restarting Rime, keeping every input session.
  func deploy(saved files: [URL] = [], styleOnly: Bool = false, timeout seconds: Double = 45) {
    state = .deploying
    errors = []
    startedAt = Date()
    savedFiles = files
    retried = false
    self.styleOnly = styleOnly
    timeout?.cancel()
    if isSquirrelRunning {
      postReload()
    } else {
      // Not started since login (it starts when first selected): start it, it deploys on its own.
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = false
      NSWorkspace.shared.openApplication(at: RimePaths.squirrelApp, configuration: configuration) { _, _ in
        Task { @MainActor in
          try? await Task.sleep(for: .seconds(2))
          self.postReload()
        }
      }
    }
    timeout = Task { [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled, let self, self.state == .deploying else { return }
      self.state = .noAnswer
      self.errors = Self.errorLines(since: self.startedAt)
    }
  }

  private func postReload() {
    DistributedNotificationCenter.default().postNotificationName(.init("SquirrelReloadNotification"), object: styleOnly ? "style" : "quiet",
                                                                 userInfo: nil, deliverImmediately: true)
  }

  func syncUserData() {
    DistributedNotificationCenter.default().postNotificationName(.init("SquirrelSyncNotification"), object: nil, userInfo: nil, deliverImmediately: true)
  }

  private func finished(_ outcome: String?) {
    guard state == .deploying else { return }
    lastFinish = Date()
    lastOutcome = outcome
    if outcome == "unchanged" && !savedFiles.isEmpty && !retried {
      // Saved in the second of the deploy before: date the files after it and ask again.
      retried = true
      let files = savedFiles
      Task { @MainActor in
        if let wait = self.nextSafeSave?.timeIntervalSinceNow, wait > 0 {
          try? await Task.sleep(for: .seconds(wait))
        }
        for file in files {
          try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        }
        self.postReload()
      }
      return
    }
    timeout?.cancel()
    errors = Self.errorLines(since: startedAt)
    state = outcome == "failure" ? .failed(Date()) : .succeeded(Date())
  }

  /// Lines of Rime's error log written since a time ("E20261019 22:19:20.351529 …").
  nonisolated static func errorLines(since date: Date) -> [String] {
    let link = RimePaths.logDir.appending(component: "rime.squirrel.ERROR")
    guard let text = try? String(contentsOf: link.resolvingSymlinksInPath(), encoding: .utf8) else { return [] }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd HH:mm:ss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return text.split(separator: "\n").compactMap { line -> String? in
      guard line.hasPrefix("E"), line.count > 18,
            let time = formatter.date(from: String(line.dropFirst().prefix(17))), time >= date.addingTimeInterval(-1) else { return nil }
      // Drop the glog prefix up to "] ".
      if let end = line.range(of: "] ") {
        return String(line[end.upperBound...])
      }
      return String(line)
    }
  }
}
