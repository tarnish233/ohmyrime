//
//  Snapshot.swift
//  鼠须管设置
//
//  SQUIRREL_SETTINGS_SNAPSHOT=<dir>: shows every page in light and dark mode and captures the
//  window, never another app's content: the screen region only when nothing but this app's
//  windows is in front of it (CGWindowList is front to back), the windows by themselves otherwise.
//

import AppKit

@MainActor
struct Snapshot {
  let store: SettingsStore
  let state: AppState
  let folder: URL

  func run() async {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? await Task.sleep(for: .seconds(1))
    NSApp.activate(ignoringOtherApps: true)
    guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else {
      print("✗ no window")
      exit(1)
    }
    // Apps may not bring themselves to the front any more; float above the others meanwhile.
    window.level = .screenSaver
    window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
    // A taller window shows whole pages (SQUIRREL_SETTINGS_SNAPSHOT_HEIGHT).
    let height = ProcessInfo.processInfo.environment["SQUIRREL_SETTINGS_SNAPSHOT_HEIGHT"].flatMap(Double.init) ?? 780
    window.setFrame(NSRect(x: 80, y: 110, width: 900, height: height), display: true)
    // Onto the current space, full-screen ones included.
    window.orderOut(nil)
    window.orderFrontRegardless()
    window.makeKey()
    var failures = 0
    // Only some pages: SQUIRREL_SETTINGS_SNAPSHOT_PAGES=input,ice
    let only = ProcessInfo.processInfo.environment["SQUIRREL_SETTINGS_SNAPSHOT_PAGES"]?.split(separator: ",").map(String.init)
    let pages = Page.allCases.filter { only?.contains($0.rawValue) ?? true }
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      NSApp.appearance = NSAppearance(named: appearance)
      for page in pages {
        state.page = page
        state.previewExpanded = false
        try? await Task.sleep(for: .seconds(1.2))
        let base = "\(name)-\(Page.allCases.firstIndex(of: page)! + 1)-\(page.rawValue)"
        failures += capture(window, base) ? 0 : 1
        // The rest of a long page, a screen at a time.
        if let scroll = mainScrollView(in: window), let document = scroll.documentView {
          var part = 2
          let step = scroll.contentView.bounds.height * 0.85
          while scroll.contentView.bounds.maxY < document.frame.height - 4 && part <= 6 {
            let y = min(scroll.contentView.bounds.minY + step, document.frame.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            try? await Task.sleep(for: .seconds(0.6))
            failures += capture(window, "\(base)-\(part)") ? 0 : 1
            part += 1
          }
          scroll.contentView.scroll(to: .zero)
          scroll.reflectScrolledClipView(scroll.contentView)
        }
        if page == .appearance {
          state.previewExpanded = true
          try? await Task.sleep(for: .seconds(1.2))
          failures += capture(window, "\(name)-1-appearance-expanded") ? 0 : 1
          state.previewExpanded = false
        }
      }
    }
    // The installer's states on the 雾凇拼音 page (its row is at the end once rime-ice is in).
    NSApp.appearance = NSAppearance(named: .aqua)
    state.page = .ice
    let states: [(String, RimeIceInstaller.Phase, [String])] = [
      ("downloading", .downloading(0.42), ["代理：http://127.0.0.1:7890", "下载：https://github.com/iDvel/rime-ice/releases/latest/download/full.zip"]),
      ("failed", .failed(RimeIceInstaller.explain(status: 7, log: ["curl: (7) Failed to connect to github.com port 443 after 20001 ms: Couldn't connect to server"])),
       ["下载：https://github.com/iDvel/rime-ice/releases/latest/download/full.zip",
        "curl: (7) Failed to connect to github.com port 443 after 20001 ms: Couldn't connect to server"]),
    ]
    for (label, phase, log) in states {
      store.iceInstaller.show(phase, log: log)
      try? await Task.sleep(for: .seconds(1.2))
      if let scroll = mainScrollView(in: window), let document = scroll.documentView {
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        try? await Task.sleep(for: .seconds(0.6))
      }
      failures += capture(window, "light-3-ice-\(label)") ? 0 : 1
    }
    store.iceInstaller.show(.idle)
    NSApp.appearance = nil
    print(failures == 0 ? "snapshots done" : "\(failures) snapshot(s) skipped")
    exit(failures == 0 ? 0 : 1)
  }

  /// The settings window by itself when another app's window is in front of it (or it is on
  /// another space): screencapture -l takes only that window's pixels. The preview panel is a
  /// window of its own, captured the same way and drawn at its place, without what is behind it.
  /// Otherwise the screen region, so that the glass shows what is behind it.
  private func capture(_ window: NSWindow, _ name: String) -> Bool {
    let url = folder.appending(component: "\(name).png")
    let region = window.frame.insetBy(dx: 10, dy: 10).integral
    if let other = windowInFront(of: region, main: window) {
      print("  (\(name): \(other) in front, capturing the windows by themselves)")
      // screencapture cannot make an image of a window with child windows.
      let children = (window.childWindows ?? []).filter(\.isVisible)
      children.forEach(window.removeChildWindow)
      defer { children.forEach { window.addChildWindow($0, ordered: .above) } }
      guard screencapture(["-o", "-l\(window.windowNumber)"], to: url) else { return false }
      for child in children {
        let childURL = folder.appending(component: "\(name)-panel.png")
        guard screencapture(["-o", "-l\(child.windowNumber)"], to: childURL),
              let base = NSImage(contentsOf: url), let overlay = NSImage(contentsOf: childURL) else { continue }
        let scale = window.backingScaleFactor
        let size = NSSize(width: window.frame.width * scale, height: window.frame.height * scale)
        let image = NSImage(size: size)
        image.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size))
        let origin = NSPoint(x: (child.frame.minX - window.frame.minX) * scale, y: (child.frame.minY - window.frame.minY) * scale)
        overlay.draw(in: NSRect(origin: origin, size: NSSize(width: child.frame.width * scale, height: child.frame.height * scale)))
        image.unlockFocus()
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
          try? png.write(to: url)
        }
        try? FileManager.default.removeItem(at: childURL)
      }
      print("→ \(name).png (windows only)")
      return true
    }
    let screenHeight = NSScreen.screens[0].frame.height
    guard screencapture(["-R\(Int(region.minX)),\(Int(screenHeight - region.maxY)),\(Int(region.width)),\(Int(region.height))"], to: url) else { return false }
    print("→ \(name).png")
    return true
  }

  private func screencapture(_ arguments: [String], to url: URL) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x"] + arguments + [url.path]
    try? task.run()
    task.waitUntilExit()
    return task.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path)
  }

  /// The page's scroll view: the widest one, not the sidebar's.
  private func mainScrollView(in window: NSWindow) -> NSScrollView? {
    func all(_ view: NSView) -> [NSScrollView] {
      (view as? NSScrollView).map { [$0] } ?? [] + view.subviews.flatMap(all)
    }
    return (window.contentView.map(all) ?? []).filter { $0.documentView != nil && !$0.isHiddenOrHasHiddenAncestor }
      .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
  }

  /// The owner of a window over the region in front of the settings window, if any.
  private func windowInFront(of region: NSRect, main: NSWindow) -> String? {
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return "?" }
    let screenHeight = NSScreen.screens[0].frame.height
    for info in windows {
      guard let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }) else { continue }
      let frame = NSRect(x: bounds.minX, y: screenHeight - bounds.maxY, width: bounds.width, height: bounds.height)
      guard frame.intersects(region), (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
      guard (info[kCGWindowOwnerPID as String] as? Int32) == getpid() else { return info[kCGWindowOwnerName as String] as? String ?? "?" }
      if (info[kCGWindowNumber as String] as? Int) == main.windowNumber {
        return frame.contains(region) ? nil : "（窗口不在屏幕内）"
      }
    }
    return "（找不到窗口）"
  }
}

/// SQUIRREL_SETTINGS_SELFTEST=deploy, with the real Squirrel: a look change and back, which Squirrel
/// applies by reloading its look, then a page size change and back, a full deploy. Every file must
/// end up as it was, and Rime's log must show no restart for the look changes.
@MainActor
struct DeploySelfTest {
  let store: SettingsStore

  func run() async {
    let start = Self.stamp(Date())
    print("== a look change (style/scroll_mode/max_rows)")
    var ok = await roundTrip(store.squirrel, "style/scroll_mode/max_rows", fallback: 5, built: "squirrel.yaml", outcome: "reloaded")
    let lookEnd = Self.stamp(Date())
    print("== a change to typing (menu/page_size)")
    ok = await roundTrip(store.defaults, "menu/page_size", fallback: 5, built: "default.yaml", outcome: "success") && ok
    // glog writes Rime's INFO log out every 30 s: wait, then have Squirrel log something.
    print("== Rime's log (waiting 31 s for glog)")
    try? await Task.sleep(for: .seconds(31))
    store.deployer.deploy(styleOnly: true)
    await waitForDeploy()
    let lines = Self.logLines().filter { $0.stamp >= start }
    let look = lines.filter { $0.stamp < lookEnd }
    let full = lines.filter { $0.stamp >= lookEnd }
    func count(_ lines: [(stamp: String, text: String)], _ text: String) -> Int { lines.filter { $0.text.contains(text) }.count }
    func check(_ condition: Bool, _ message: String) {
      print("  \(condition ? "✓" : "✗") \(message)")
      ok = ok && condition
    }
    check(!lines.isEmpty, "read \(lines.count) lines")
    check(count(look, "engine disposed") == 0 && count(look, "closed db") == 0 && count(look, "starting work thread") == 0,
          "look changes: Rime kept running, no input session closed, no deploy")
    check(count(look, "build/squirrel.yaml'") >= 2, "look changes: build/squirrel.yaml rebuilt twice")
    check(count(full, "starting work thread") >= 2, "page size: deployed twice (\(count(full, "engine disposed")) sessions closed)")
    exit(ok ? 0 : 1)
  }

  private func roundTrip(_ file: ConfigFile, _ path: String, fallback: Int, built: String, outcome: String) async -> Bool {
    let before = (try? String(contentsOf: file.customURL, encoding: .utf8)) ?? ""
    let original = store.int(file, path) ?? fallback
    let key = path.split(separator: "/").last.map(String.init) ?? path
    var ok = true
    for value in [original + 1, original] {
      store.set(file, path, .int(value))
      store.saveNow()
      await waitForDeploy()
      let deployed = (try? String(contentsOf: RimePaths.buildDir.appending(component: built), encoding: .utf8)) ?? ""
      let applied = deployed.contains("\(key): \(value)")
      let said = store.deployer.lastOutcome ?? "nothing"
      var succeeded = false
      if case .succeeded = store.deployer.state { succeeded = true }
      let good = succeeded && applied && said == outcome
      print(String(format: "  %@ %@ %d: %@ in %.0f ms, build/%@ %@", good ? "✓" : "✗", key, value, said,
                   (store.deployer.lastDuration ?? -1) * 1000, built, applied ? "has it" : "does not have it"))
      ok = ok && good
    }
    let after = (try? String(contentsOf: file.customURL, encoding: .utf8)) ?? ""
    print("  \(after == before ? "✓" : "✗") \(file.fileName) is \(after == before ? "as it was" : "changed")")
    return ok && after == before
  }

  private func waitForDeploy() async {
    let start = Date()
    while (store.hasUnsavedChanges || store.deployer.state == .deploying) && Date().timeIntervalSince(start) < 50 {
      try? await Task.sleep(for: .milliseconds(20))
    }
  }

  /// glog's time stamps, which sort as text: "20261020 10:23:45.123456".
  static func stamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd HH:mm:ss.SSSSSS"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
  }

  /// The running Squirrel's Rime log: "I20261020 10:23:45.123456 0x16fdcf000 file.cc:12] text".
  static func logLines() -> [(stamp: String, text: String)] {
    let link = RimePaths.logDir.appending(component: "rime.squirrel.INFO")
    guard let log = try? String(contentsOf: link.resolvingSymlinksInPath(), encoding: .utf8) else { return [] }
    return log.split(separator: "\n").compactMap { line in
      guard line.count > 25, line.first == "I" || line.first == "W" || line.first == "E" else { return nil }
      return (String(line.dropFirst().prefix(24)), String(line))
    }
  }
}

/// SQUIRREL_SETTINGS_SELFTEST=install-ice… with SQUIRREL_SETTINGS_USER_DIR: installs rime-ice into
/// that copy the way the page's button does (the bundled script), printing the phases.
///   install-ice          download the latest release
///   install-ice-offline  the download from last time (cached)
///   install-ice-cancel   start downloading, then cancel: nothing installed, no curl left behind
@MainActor
struct IceInstallSelfTest {
  enum Mode: String {
    case online = "install-ice"
    case offline = "install-ice-offline"
    case cancel = "install-ice-cancel"
  }

  let store: SettingsStore
  let mode: Mode

  func run() async {
    guard LaunchOptions.current.userDir != nil else {
      print("✗ only with SQUIRREL_SETTINGS_USER_DIR (a copy)")
      exit(2)
    }
    let installer = store.iceInstaller
    let start = Date()
    var shown = ""
    func show() {
      let now: String
      switch installer.phase {
      case .downloading(let fraction): now = "downloading" + (fraction.map { String(format: " %d%%", Int($0 * 10) * 10) } ?? "")
      default: now = "\(installer.phase)"
      }
      if now != shown {
        print(String(format: "%5.1f s  %@", Date().timeIntervalSince(start), now))
        shown = now
      }
    }
    let wasInstalled = store.iceInstalled
    let task = Task { await store.installRimeIce(offline: mode == .offline) }
    var ok = true
    while Date().timeIntervalSince(start) < 300 {
      show()
      if mode == .cancel, case .downloading(let fraction?) = installer.phase, fraction > 0.02 {
        installer.cancel()
      }
      if [.finished, .cancelled].contains(installer.phase) { break }
      if case .failed = installer.phase { break }
      try? await Task.sleep(for: .milliseconds(50))
    }
    await task.value
    show()
    let folder = RimePaths.userDir
    let manager = FileManager.default
    func check(_ condition: Bool, _ message: String) {
      print("  \(condition ? "✓" : "✗") \(message)")
      ok = ok && condition
    }
    if mode == .cancel {
      check(installer.phase == .cancelled, "cancelled")
      check(store.iceInstalled == wasInstalled, "nothing installed")
      let pgrep = Process()
      pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
      pgrep.arguments = ["-f", "full.zip.part"]
      pgrep.standardOutput = FileHandle.nullDevice
      try? pgrep.run()
      pgrep.waitUntilExit()
      check(pgrep.terminationStatus != 0, "no curl left downloading")
    } else {
      check(installer.phase == .finished, "finished: \(installer.summary ?? "")")
      check(store.iceInstalled && store.mainIceSchema == "rime_ice", "rime-ice is in the folder, version \(store.iceVersion ?? "?")")
      check(store.enabledSchemas.first == "rime_ice", "rime_ice is the default schema: \(store.enabledSchemas)")
      check(store.missingSchemas.isEmpty && !store.typesOnlyEnglish, "no missing schema")
      check(!manager.fileExists(atPath: folder.appending(component: "squirrel.yaml").path), "rime-ice's squirrel.yaml is not installed")
      let backups = (try? manager.subpathsOfDirectory(atPath: RimePaths.backupDir.path)) ?? []
      check(backups.contains { $0.hasSuffix(".tar.gz") }, "the folder was backed up in \(RimePaths.backupDir.path)")
      check(!store.hasUnsavedChanges, "everything saved")
    }
    print("  log: " + installer.log.suffix(6).joined(separator: " | "))
    exit(ok ? 0 : 1)
  }
}
