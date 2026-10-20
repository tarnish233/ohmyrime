//
//  SettingsApp.swift
//  鼠须管设置
//
//  A settings app for ohmyrime's Squirrel: edits the *.custom.yaml patches in ~/Library/Rime,
//  and asks Squirrel to deploy after each change. It is ohmyrime's installer too: it carries
//  Squirrel and rime-ice, and shows the welcome (WelcomeView) while they are not set up.
//
//  Environment variables, for tests (not arguments: AppKit reads "-key value" pairs from the
//  command line, and takes a path left over for a file to open, which skips the first window):
//    SQUIRREL_SETTINGS_USER_DIR=<dir>   edit a copy of the user folder (backups go next to it)
//    SQUIRREL_SETTINGS_NO_DEPLOY=1      save without asking Squirrel to deploy
//    SQUIRREL_SETTINGS_SNAPSHOT=<dir>   capture every page into <dir>, then quit (Snapshot.swift);
//                                       SQUIRREL_SETTINGS_SNAPSHOT_PAGES=input,ice for some of them
//    SQUIRREL_SETTINGS_SELFTEST=deploy  change a setting and back, through Squirrel's deploy
//    SQUIRREL_SETTINGS_SELFTEST=install-ice | install-ice-offline | install-ice-cancel
//                                       install rime-ice into the copy as the page does
//

import AppKit
import SwiftUI

/// Squirrel's sources compiled into this app (for the preview) refer to these.
enum SquirrelApp {
  static var userDir: URL { RimePaths.userDir }
  static var appDir: URL { RimePaths.squirrelApp }
  static var logDir: URL { RimePaths.logDir }
}

struct LaunchOptions {
  var userDir: URL?
  var deploys = true
  var snapshotDir: URL?

  static let current: LaunchOptions = {
    let environment = ProcessInfo.processInfo.environment
    var options = LaunchOptions()
    options.userDir = environment["SQUIRREL_SETTINGS_USER_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    options.deploys = environment["SQUIRREL_SETTINGS_NO_DEPLOY"] == nil
    options.snapshotDir = environment["SQUIRREL_SETTINGS_SNAPSHOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    return options
  }()
}

@MainActor @Observable
final class AppState {
  var page: Page = .appearance
  var previewExpanded = false
  /// The welcome's step, in place of the settings; nil: the settings.
  var welcome: WelcomeStep?
  /// The welcome only updates an ohmyrime that is set up: it ends after installing.
  var welcomeUpdates = false

  /// Opens the welcome where there is something to do: installing, adding Squirrel, or (all done)
  /// choosing the schema again.
  func showWelcome(_ install: InstallState) {
    welcomeUpdates = install.installUpdates
    welcome = install.firstWelcomeStep ?? .choose
  }
}

/// The welcome while ohmyrime is not set up, the settings otherwise.
struct RootView: View {
  @Environment(AppState.self) private var state

  var body: some View {
    if state.welcome != nil {
      WelcomeView()
    } else {
      ContentView()
    }
  }
}

@main
struct SettingsApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var store: SettingsStore
  @State private var state: AppState
  @State private var install: InstallState

  init() {
    let options = LaunchOptions.current
    if let userDir = options.userDir {
      RimePaths.userDir = userDir
      RimePaths.backupDir = userDir.deletingLastPathComponent().appending(component: "Backups")
    }
    // librime only parses YAML here; errors go to stderr, nothing to the user's log folder.
    var traits = RimeTraits.rimeStructInit()
    traits.min_log_level = 2
    traits.setCString("", to: \.log_dir)
    traits.setCString("rime.squirrel-settings", to: \.app_name)
    rime_get_api_stdbool().pointee.setup(&traits)

    let store = SettingsStore()
    store.deploysAfterSaving = options.deploys
    _store = State(initialValue: store)
    AppDelegate.store = store
    let install = InstallState()
    let state = AppState()
    // Not in snapshots and self-tests, which drive the window themselves.
    let environment = ProcessInfo.processInfo.environment
    if options.snapshotDir == nil && environment["SQUIRREL_SETTINGS_SELFTEST"] == nil && options.userDir == nil,
       install.firstWelcomeStep != nil {
      state.showWelcome(install)
    }
    _install = State(initialValue: install)
    _state = State(initialValue: state)
  }

  var body: some Scene {
    Window("鼠须管设置", id: "settings") {
      RootView()
        .environment(store)
        .environment(state)
        .environment(install)
        .environment(UpdateCenter.shared)
        .frame(minWidth: 780, minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
          store.reloadChangedFiles()
          install.refresh()
        }
        // The welcome is a short page: a smaller window, back to the settings' size after it.
        .onChange(of: state.welcome == nil) { _, settings in
          guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
          window.setContentSize(settings ? NSSize(width: 880, height: 720) : NSSize(width: 860, height: 640))
          window.center()
        }
        .task {
          // Once a day, quietly; the banner in the settings says when there is something.
          Task { await UpdateCenter.shared.checkIfDue() }
          if let folder = LaunchOptions.current.snapshotDir {
            await Snapshot(store: store, state: state, install: install, folder: folder).run()
          } else if let test = ProcessInfo.processInfo.environment["SQUIRREL_SETTINGS_SELFTEST"] {
            if test == "update-install" {
              // Installs the app in OHMYRIME_UPDATE_SOURCE over the copy running here, as the
              // About page would install a release.
              let source = ProcessInfo.processInfo.environment["OHMYRIME_UPDATE_SOURCE"]
              if let source {
                UpdateCheck.assetBaseURL = URL(fileURLWithPath: source, isDirectory: true)
              }
              var version = Payload.version
              if let forced = ProcessInfo.processInfo.environment["OHMYRIME_UPDATE_VERSION"] {
                version = forced
              }
              let release = UpdateCheck.Release(version: "v\(version)",
                                                pageURL: URL(string: "https://example.invalid")!)
              UpdateCenter.shared.show(.available(release))
              await UpdateCenter.shared.installRelease()
              print(UpdateCenter.shared.installFailure ?? "installed")
              exit(UpdateCenter.shared.installFailure == nil ? 0 : 1)
            } else if test == "update" {
              // Checks GitHub as the About window does, and says what came of it.
              let outcome = await UpdateCheck.check(currentVersion: Payload.version)
              print(outcome)
              exit(0)
            } else if test == "deploy" {
              await DeploySelfTest(store: store).run()
            } else if let mode = IceInstallSelfTest.Mode(rawValue: test) {
              await IceInstallSelfTest(store: store, mode: mode).run()
            }
          }
        }
    }
    .defaultSize(width: 880, height: 720)
    .windowResizability(.contentMinSize)
    .commands {
      CommandGroup(replacing: .appInfo) {
        Button("关于 ohmyrime") { showAbout() }
      }
      CommandGroup(after: .appInfo) {
        Button("检查更新…") {
          showAbout()
          Task { await UpdateCenter.shared.check() }
        }
        Divider()
        Button("欢迎使用 ohmyrime…") { state.showWelcome(install) }
          .disabled(state.welcome != nil)
      }
      CommandGroup(replacing: .newItem) {}
      CommandGroup(after: .saveItem) {
        Button("立即保存并部署") { store.redeploy() }
          .keyboardShortcut("s")
      }
    }
  }
}

extension SettingsApp {
  /// 「关于」in the app menu: the About page of the settings window, brought forward.
  @MainActor
  private func showAbout() {
    state.page = .about
    state.welcome = nil
    NSApp.activate(ignoringOtherApps: true)
    NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  @MainActor static var store: SettingsStore?

  func applicationDidFinishLaunching(_ notification: Notification) {
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  func applicationWillTerminate(_ notification: Notification) {
    MainActor.assumeIsolated {
      guard let store = Self.store else { return }
      // A download stops (copying, a second or two, finishes by itself).
      store.iceInstaller.cancel()
      // Changes still waiting for the save delay.
      if store.hasUnsavedChanges {
        store.saveNow(immediately: true)
      }
    }
  }
}
