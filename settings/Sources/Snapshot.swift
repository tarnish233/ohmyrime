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
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      NSApp.appearance = NSAppearance(named: appearance)
      for page in Page.allCases {
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

/// SQUIRREL_SETTINGS_SELFTEST=deploy: raises style/scroll_mode/max_rows by one and puts it back,
/// each time saving and waiting for Squirrel's deploy; the file must end up as it was.
@MainActor
struct DeploySelfTest {
  let store: SettingsStore

  func run() async {
    let file = store.squirrel
    let before = (try? String(contentsOf: file.customURL, encoding: .utf8)) ?? ""
    let original = store.int(file, "style/scroll_mode/max_rows") ?? 5
    var ok = true
    for value in [original + 1, original] {
      store.set(file, "style/scroll_mode/max_rows", .int(value))
      let start = Date()
      store.saveNow()
      // The save may wait for the second after the last deploy.
      while (store.hasUnsavedChanges || store.deployer.state == .deploying) && Date().timeIntervalSince(start) < 50 {
        try? await Task.sleep(for: .milliseconds(100))
      }
      let deployed = (try? String(contentsOf: RimePaths.buildDir.appending(component: "squirrel.yaml"), encoding: .utf8)) ?? ""
      let applied = deployed.contains("max_rows: \(value)")
      print(String(format: "max_rows %d: %@ after %.1f s, build/squirrel.yaml %@", value, "\(store.deployer.state)",
                   Date().timeIntervalSince(start), applied ? "has it" : "does not have it"))
      if case .succeeded = store.deployer.state, applied {} else { ok = false }
    }
    let after = (try? String(contentsOf: file.customURL, encoding: .utf8)) ?? ""
    print(after == before ? "squirrel.custom.yaml is as it was" : "squirrel.custom.yaml changed")
    exit(ok && after == before ? 0 : 1)
  }
}
