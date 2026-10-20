//
//  InstallState.swift
//  鼠须管设置
//
//  What is installed, kept up to date while the app runs: Squirrel (compared with what the app
//  carries), whether the user added it to the input sources, whether it runs, and the app itself.
//  And what the welcome does with them: install, add (with the system's help or in System
//  Settings), switch to Squirrel.
//

import AppKit
import Carbon
import Observation

@MainActor @Observable
final class InstallState {
  struct InputSource: Equatable {
    /// The system knows Squirrel's input mode (it was registered).
    var registered = false
    var enabled = false
    var selected = false
    /// In the system's list of input sources the user added; nil if there is no list to read.
    var remembered: Bool?
    /// Added for good: enabled, and the system remembers it after logging in again.
    var isAdded: Bool { enabled && remembered != false }
  }

  private(set) var squirrel: SquirrelStatus = .missing
  private(set) var inputSource = InputSource()
  private(set) var isSquirrelRunning = false
  /// The copy in /Applications (or ~/Applications), if there is one.
  private(set) var installedApp: URL?
  /// Squirrel's last deploy since this app started: when it ended, and whether it worked.
  private(set) var lastDeploy: (date: Date, succeeded: Bool)?
  let installer = ScriptRunner()
  let uninstaller = ScriptRunner()
  /// Snapshots show made-up states, which refreshing would undo.
  private(set) var isSimulated = false

  @ObservationIgnored private var observers: [NSObjectProtocol] = []
  @ObservationIgnored private var hashCache: (path: String, date: Date, hash: String)?

  init() {
    refresh()
    let distributed = DistributedNotificationCenter.default()
    let changes: [CFString?] = [kTISNotifyEnabledKeyboardInputSourcesChanged, kTISNotifySelectedKeyboardInputSourceChanged]
    for case let name? in changes {
      observers.append(distributed.addObserver(forName: Notification.Name(name as String), object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.refreshInputSource() }
      })
    }
    observers.append(distributed.addObserver(forName: .init("SquirrelDeployDidFinishNotification"), object: nil, queue: .main) { [weak self] note in
      let outcome = note.object as? String
      MainActor.assumeIsolated {
        guard let self, outcome == "success" || outcome == "failure" else { return }
        self.lastDeploy = (Date(), outcome == "success")
      }
    })
    let workspace = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
      observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard app?.bundleIdentifier == InputSourceRecord.squirrelBundle else { return }
        MainActor.assumeIsolated { self?.refreshRunning() }
      })
    }
  }

  // MARK: State

  func refresh() {
    guard !isSimulated else { return }
    let executable = RimePaths.squirrelApp.appending(components: "Contents", "MacOS", "Squirrel")
    squirrel = SquirrelStatus.of(installedHash: installedHash(executable), carriedHash: Payload.squirrelHash,
                                 marker: InstallMarker.read(), version: Payload.version)
    installedApp = Self.applicationsCopies.first { FileManager.default.fileExists(atPath: $0.path) }
    refreshInputSource()
    // The system can keep the record of an input method that was uninstalled: it means nothing
    // until Squirrel is back.
    if squirrel == .missing {
      inputSource = InputSource()
    }
    refreshRunning()
  }

  func refreshInputSource() {
    guard !isSimulated else { return }
    let state = Self.readInputSource()
    if state != inputSource {
      inputSource = state
    }
  }

  private func refreshRunning() {
    guard !isSimulated else { return }
    isSquirrelRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: InputSourceRecord.squirrelBundle).isEmpty
  }

  /// Where the welcome starts when the app opens; nil when there is nothing to do.
  var firstWelcomeStep: WelcomeStep? {
    switch squirrel {
    case .missing, .other: return .install
    case .current, .newer: break
    }
    if !inputSource.isAdded {
      return .add
    }
    return installedApp == nil ? .install : nil
  }

  /// Installing replaces a Squirrel the user already added: an update, nothing else to set up.
  var installUpdates: Bool { squirrel == .other && inputSource.isAdded }

  static var applicationsCopies: [URL] {
    [URL(fileURLWithPath: "/Applications/鼠须管设置.app"),
     FileManager.default.homeDirectoryForCurrentUser.appending(components: "Applications", "鼠须管设置.app")]
  }

  /// This is the installed copy, not a download (or a build).
  var runsFromInstalledApp: Bool {
    let path = { (url: URL) in url.resolvingSymlinksInPath().standardizedFileURL.path }
    return Self.applicationsCopies.contains { path($0) == path(Bundle.main.bundleURL) }
  }

  /// The installed Squirrel's hash, worked out again only when the file changed.
  private func installedHash(_ url: URL) -> String? {
    guard let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return nil }
    if let hashCache, hashCache.path == url.path, hashCache.date == date {
      return hashCache.hash
    }
    guard let hash = SquirrelStatus.hash(of: url) else { return nil }
    hashCache = (url.path, date, hash)
    return hash
  }

  static func readInputSource() -> InputSource {
    var state = InputSource()
    let conditions = [kTISPropertyBundleID as String: InputSourceRecord.squirrelBundle] as CFDictionary
    let sources = (TISCreateInputSourceList(conditions, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
    for source in sources where string(source, kTISPropertyInputSourceID) == InputSourceRecord.squirrelHans {
      state.registered = true
      state.enabled = bool(source, kTISPropertyInputSourceIsEnabled) ?? false
      state.selected = bool(source, kTISPropertyInputSourceIsSelected) ?? false
    }
    state.remembered = InputSourceRecord.remembersSquirrel()
    return state
  }

  private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
  }

  private static func bool(_ source: TISInputSource, _ key: CFString) -> Bool? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
  }

  // MARK: Actions

  /// Installs, or updates, with the bundled install.sh.
  func install() async -> Bool {
    guard let script = Payload.installScript else { return false }
    let installed = await installer.run(script)
    refresh()
    return installed
  }

  /// Uninstalls with the bundled uninstall.sh; `purge` deletes the user folder too.
  func uninstall(purge: Bool) async -> Bool {
    guard let script = Payload.uninstallScript else { return false }
    let done = await uninstaller.run(script, arguments: purge ? ["--purge"] : [])
    refresh()
    return done
  }

  // MARK: Adding to the input sources

  /// The add step: asking the system, then guiding through System Settings.
  enum AddPhase: Equatable { case idle, asking, guiding }
  private(set) var addPhase: AddPhase = .idle

  /// Asks the system to enable Squirrel; when it does not do it, System Settings and the card.
  func addToInputSources() async {
    guard addPhase != .asking else { return }
    addPhase = .asking
    let settingsRan = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").isEmpty
    if !inputSource.registered {
      register()
      try? await Task.sleep(for: .seconds(1.5))
    }
    if !isSquirrelRunning {
      launchSquirrel()
    }
    requestEnable()
    // The system's confirmation takes the focus from this app: wait until it is answered.
    try? await Task.sleep(for: .seconds(1.5))
    let start = Date()
    while !NSApp.isActive && !inputSource.isAdded && Date().timeIntervalSince(start) < 90 {
      try? await Task.sleep(for: .milliseconds(300))
      refreshInputSource()
    }
    refreshInputSource()
    guard !inputSource.isAdded else {
      addPhase = .idle
      return
    }
    // System Settings that ran before may have an old list of input methods.
    addPhase = .guiding
    await openKeyboardSettings(restart: settingsRan)
  }

  /// Until the user added Squirrel: looks again every second, and registers it again if the
  /// system lost it (then it is not in System Settings' list either).
  func watchForAdded() async {
    guard addPhase != .idle else { return }
    var registered = Date()
    while !Task.isCancelled && !inputSource.isAdded {
      refreshInputSource()
      if !inputSource.registered && Date().timeIntervalSince(registered) > 5 {
        register()
        registered = Date()
      }
      try? await Task.sleep(for: .seconds(1))
    }
    if !Task.isCancelled {
      addPhase = .idle
    }
  }

  /// Registers Squirrel with the system again: after the app is replaced, the system sometimes
  /// loses it, and then System Settings' list does not have it.
  func register() {
    SquirrelInstaller().register()
    refreshInputSource()
  }

  /// Asks the system to enable Squirrel. Since macOS 13 it asks the user to confirm, and may not
  /// keep it; then the user adds it in System Settings.
  func requestEnable() {
    SquirrelInstaller().enable()
    refreshInputSource()
  }

  /// Switches to Squirrel (the user asked); whether it is selected afterwards.
  @discardableResult
  func select() -> Bool {
    SquirrelInstaller().select()
    refreshInputSource()
    return inputSource.selected
  }

  /// Starts Squirrel in the background: in the login it was installed in, the system may not
  /// start a new input method by itself.
  func launchSquirrel() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.openApplication(at: RimePaths.squirrelApp, configuration: configuration) { _, _ in }
  }

  /// Opens System Settings at Keyboard. `restart`: quit it first if it runs, since it reads the
  /// list of input methods when it starts, and one installed since would not be in it.
  func openKeyboardSettings(restart: Bool = true) async {
    let identifier = "com.apple.systempreferences"
    if restart {
      for app in NSRunningApplication.runningApplications(withBundleIdentifier: identifier) {
        app.terminate()
      }
      for _ in 0..<40 where !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty {
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
      NSWorkspace.shared.open(url)
    }
  }

  /// For snapshots: shows a made-up state.
  func simulate(squirrel: SquirrelStatus, inputSource: InputSource, running: Bool = true, deployed: Bool? = nil) {
    isSimulated = true
    self.squirrel = squirrel
    self.inputSource = inputSource
    isSquirrelRunning = running
    lastDeploy = deployed.map { (Date(), $0) }
  }
}
