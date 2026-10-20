//
//  SettingsApp.swift
//  鼠须管设置
//
//  A settings app for ohmyrime's Squirrel: edits the *.custom.yaml patches in ~/Library/Rime,
//  and asks Squirrel to deploy after each change.
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
}

@main
struct SettingsApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var store: SettingsStore
  @State private var state = AppState()

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
  }

  var body: some Scene {
    Window("鼠须管设置", id: "settings") {
      ContentView()
        .environment(store)
        .environment(state)
        .frame(minWidth: 780, minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
          store.reloadChangedFiles()
        }
        .task {
          if let folder = LaunchOptions.current.snapshotDir {
            await Snapshot(store: store, state: state, folder: folder).run()
          } else if let test = ProcessInfo.processInfo.environment["SQUIRREL_SETTINGS_SELFTEST"] {
            if test == "deploy" {
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
      CommandGroup(replacing: .newItem) {}
      CommandGroup(after: .saveItem) {
        Button("立即保存并部署") { store.redeploy() }
          .keyboardShortcut("s")
      }
    }
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
