//
//  CandidatePreview.swift
//  鼠须管设置
//
//  The real candidate panel (Squirrel's SquirrelPanel) over a sample document, with the
//  settings as they are in this window, saved or not: what typing will look like.
//

import AppKit
import SwiftUI

enum PreviewAppearance: String, CaseIterable, Identifiable {
  case system, light, dark
  var id: String { rawValue }
  var title: String {
    switch self {
    case .system: "跟随系统"
    case .light: "浅色"
    case .dark: "深色"
    }
  }
  var appearance: NSAppearance? {
    switch self {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }
}

struct CandidatePreview: View {
  @Environment(SettingsStore.self) private var store
  @Environment(AppState.self) private var state
  @State private var appearance = PreviewAppearance.system

  var body: some View {
    @Bindable var state = state
    VStack(spacing: 10) {
      PreviewCanvas(store: store, revision: store.revision, expanded: state.previewExpanded)
        .frame(height: 188)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
      HStack {
        Picker("预览", selection: $state.previewExpanded) {
          Text("单行").tag(false)
          Text("展开").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("展开：按 Tab 后的样子")
        Spacer()
        Picker("外观", selection: $appearance) {
          ForEach(PreviewAppearance.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("预览浅色或深色模式（整个设置窗口一起切换）")
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 16)
    .padding(.bottom, 6)
    .onChange(of: appearance) { _, value in
      NSApp.appearance = value.appearance
    }
  }
}

struct PreviewCanvas: NSViewRepresentable {
  let store: SettingsStore
  let revision: Int
  let expanded: Bool

  func makeNSView(context: Context) -> PreviewCanvasView {
    PreviewCanvasView()
  }

  func updateNSView(_ view: PreviewCanvasView, context: Context) {
    view.update(store: store, revision: revision, expanded: expanded)
  }

  static func dismantleNSView(_ view: PreviewCanvasView, coordinator: ()) {
    view.dismiss()
  }
}

/// A document with text being typed, and the panel below it as a child window.
final class PreviewCanvasView: NSView {
  private var panel: SquirrelPanel?
  private var loadedRevision = -1
  private var expanded = false
  private var generation = 0
  private var pageSize = 5
  private var labels = [String]()
  private var inlinePreedit = true
  private var scrollMode = false
  private var maxRows = 5
  private var observers = [NSObjectProtocol]()
  private static let font = NSFont.systemFont(ofSize: 14)
  private static let typed = NSAttributedString(string: "今天想跟你说一声：", attributes: [.font: font, .foregroundColor: NSColor.labelColor])
  /// Where the composition starts, in this view.
  private var caretRect: NSRect {
    NSRect(x: 24 + Self.typed.size().width, y: 18, width: 1, height: Self.font.ascender - Self.font.descender + 2)
  }

  override var isFlipped: Bool { true }

  private static let words = ["你好", "👋", "泥嚎", "你号", "拟好", "倪浩", "你", "尼", "泥", "呢", "拟", "逆", "腻", "妮", "霓",
                              "倪", "昵", "溺", "匿", "睨", "鲵", "伲", "怩", "旎", "坭", "铌", "祢", "猊", "妳", "苨"]

  func update(store: SettingsStore, revision: Int, expanded: Bool) {
    if panel == nil || revision != loadedRevision {
      loadTheme(store)
      loadedRevision = revision
      needsDisplay = true
    }
    if expanded != self.expanded {
      self.expanded = expanded
      generation += 1
    }
    showPanel()
  }

  private func loadTheme(_ store: SettingsStore) {
    let panel = self.panel ?? makePanel()
    let config = SquirrelConfig()
    if config.open(yaml: store.squirrel.effective.documentText) {
      panel.load(config: config, forDarkMode: false)
      panel.load(config: config, forDarkMode: true)
    }
    config.close()
    pageSize = min(max(store.int(store.defaults, "menu/page_size") ?? 5, 1), 10)
    labels = store.strings(store.defaults, "menu/alternative_select_labels")
    inlinePreedit = store.bool(store.squirrel, "style/inline_preedit") ?? true
    let linear = store.string(store.squirrel, "style/candidate_list_layout") == "linear"
    let horizontal = store.string(store.squirrel, "style/text_orientation") != "vertical"
    scrollMode = linear && horizontal && store.bool(store.squirrel, "style/scroll_mode/enable") == true
    maxRows = min(max(store.int(store.squirrel, "style/scroll_mode/max_rows") ?? 5, 2), 20)
  }

  private func makePanel() -> SquirrelPanel {
    let panel = SquirrelPanel(position: .zero)
    // Above the settings window only, not above every app like the input method's panel.
    panel.level = .normal
    panel.hidesOnDeactivate = false
    self.panel = panel
    return panel
  }

  func dismiss() {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    if let panel {
      panel.parent?.removeChildWindow(panel)
      panel.hide()
    }
  }

  /// Light or dark: the panel picks its theme when it lays out.
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
    DispatchQueue.main.async { [weak self] in self?.showPanel() }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    guard let window else {
      panel?.hide()
      return
    }
    postsFrameChangedNotifications = true
    let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification, NSWindow.didDeminiaturizeNotification,
                                      NSWindow.didEndLiveResizeNotification, NSView.frameDidChangeNotification]
    for name in names {
      let object: AnyObject = name == NSView.frameDidChangeNotification ? self : window
      observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.showPanel() }
      })
    }
    DispatchQueue.main.async { [weak self] in self?.showPanel() }
  }

  private func showPanel() {
    guard let panel, let window, window.isVisible, !isHiddenOrHasHiddenAncestor, bounds.width > 0 else {
      panel?.hide()
      return
    }
    panel.position = window.convertToScreen(convert(caretRect, to: nil))
    panel.level = window.level
    panel.collectionBehavior = window.collectionBehavior
    let size = pageSize
    var candidates = Array(Self.words.prefix(size))
    var highlighted = 0
    var page = 0
    var layout: SquirrelScrollLayout?
    if expanded && scrollMode {
      let rows = min(maxRows, 3)
      candidates = Array(Self.words.prefix(size * rows))
      highlighted = size
      page = 1
      layout = SquirrelScrollLayout(rowSize: size, highlightedRow: 1, hasRowsAbove: false, hasRowsBelow: true, generation: generation)
    } else if expanded {
      // Without scroll mode, Tab is the next page.
      candidates = Array(Self.words[size..<size * 2])
      page = 1
    }
    let preedit = inlinePreedit ? "" : "ni hao"
    panel.update(preedit: preedit, selRange: NSRange(location: 0, length: preedit.utf16.count), caretPos: preedit.utf16.count,
                 candidates: candidates, comments: candidates.map { _ in "" }, labels: labels, highlighted: highlighted,
                 page: page, lastPage: false, scroll: layout, update: true)
    if panel.parent !== window {
      window.addChildWindow(panel, ordered: .above)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.textBackgroundColor.setFill()
    bounds.fill()
    // A colorful picture on the right, to show how the glass reads over it.
    let split = (bounds.width * 0.6).rounded()
    let picture = NSRect(x: split, y: 14, width: bounds.width - split - 14, height: bounds.height - 28)
    NSGradient(colors: [.systemPink, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple])?
      .draw(in: NSBezierPath(roundedRect: picture, xRadius: 10, yRadius: 10), angle: -40)

    let text: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.labelColor]
    let faint: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.secondaryLabelColor]
    NSAttributedString(string: Self.typed.string, attributes: text).draw(at: NSPoint(x: 24, y: 18))
    let caretRect = self.caretRect
    if inlinePreedit {
      // The composition, underlined, as apps show marked text.
      let marked = NSAttributedString(string: "ni hao", attributes: text.merging([.underlineStyle: NSUnderlineStyle.single.rawValue]) { $1 })
      marked.draw(at: NSPoint(x: caretRect.minX, y: 18))
      NSColor.labelColor.setFill()
      NSRect(x: caretRect.minX + marked.size().width + 1, y: 19, width: 1.5, height: caretRect.height - 2).fill()
    }
    let lines = ["落霞与孤鹜齐飞，秋水共长天一色。", "The quick brown fox jumps over the lazy dog.", "遥襟甫畅，逸兴遄飞。爽籁发而清风生，", "纤歌凝而白云遏。睢园绿竹，气凌彭泽之樽；",
                 "邺水朱华，光照临川之笔。四美具，二难并。", "穷睇眄于中天，极娱游于暇日。"]
    for (index, line) in lines.enumerated() {
      NSAttributedString(string: line, attributes: faint).draw(in: NSRect(x: 24, y: 50 + CGFloat(index) * 22, width: split - 40, height: 20))
    }
  }
}
