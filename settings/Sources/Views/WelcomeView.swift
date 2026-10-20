//
//  WelcomeView.swift
//  鼠须管设置
//
//  The welcome, in place of the settings while ohmyrime is not set up: install (the app carries
//  Squirrel and rime-ice), add Squirrel to the input sources (macOS wants the user to do it: a
//  floating card guides them through System Settings and ticks off when it is done), pick the
//  schema and the Chinese / English key, and try it.
//

import AppKit
import SwiftUI

enum WelcomeStep: Int, CaseIterable, Identifiable {
  case install, add, choose, tryIt
  var id: Int { rawValue }

  var title: String {
    switch self {
    case .install: "安装"
    case .add: "添加输入法"
    case .choose: "选择方案"
    case .tryIt: "试一试"
    }
  }
}

struct WelcomeView: View {
  @Environment(AppState.self) private var state

  var body: some View {
    let step = state.welcome ?? .install
    VStack(spacing: 0) {
      Header(updates: state.welcomeUpdates, step: state.welcomeUpdates ? nil : step)
      Divider()
      StepContent(step: step, updates: state.welcomeUpdates)
      Divider()
      StepFooter(step: step, updates: state.welcomeUpdates)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .navigationTitle(state.welcomeUpdates ? "更新 ohmyrime" : "欢迎使用 ohmyrime")
  }
}

/// The app's name and what this is, centred like a setup assistant, and where the welcome is.
private struct Header: View {
  let updates: Bool
  let step: WelcomeStep?

  var body: some View {
    VStack(spacing: 0) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 58, height: 58)
        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
      Text(updates ? "更新 ohmyrime" : "欢迎使用 ohmyrime")
        .font(.system(size: 24, weight: .semibold))
        .padding(.top, 10)
      HStack(spacing: 6) {
        Text("鼠须管输入法 · 雾凇拼音 · 液态玻璃候选框")
        Text("·").foregroundStyle(.quaternary)
        Text("版本 \(Payload.version)")
      }
      .font(.callout)
      .foregroundStyle(.secondary)
      .padding(.top, 5)
      if let step {
        StepBar(current: step)
          .padding(.top, 17)
          .frame(maxWidth: 500)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 22)
    .padding(.horizontal, 32)
    .padding(.bottom, updates ? 20 : 17)
  }
}

/// Where the welcome is: done steps ticked off, the current one filled.
struct StepBar: View {
  let current: WelcomeStep

  var body: some View {
    HStack(spacing: 0) {
      ForEach(WelcomeStep.allCases) { step in
        if step != WelcomeStep.allCases.first {
          Rectangle()
            .fill(step.rawValue <= current.rawValue ? AnyShapeStyle(Color.accentColor.opacity(0.45)) : AnyShapeStyle(.quaternary))
            .frame(height: 1.5)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
        }
        HStack(spacing: 6) {
          ZStack {
            Circle()
              .fill(step.rawValue < current.rawValue ? AnyShapeStyle(Color.accentColor.opacity(0.15))
                    : step == current ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
              .frame(width: 22, height: 22)
            if step.rawValue < current.rawValue {
              Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.accentColor)
            } else {
              Text("\(step.rawValue + 1)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(step == current ? Color.white : Color.secondary)
            }
          }
          Text(step.title)
            .font(.callout.weight(step == current ? .semibold : .regular))
            .foregroundStyle(step == current ? Color.primary : step.rawValue < current.rawValue ? Color.secondary : Color.secondary.opacity(0.7))
            .fixedSize()
        }
      }
    }
  }
}

private struct StepContent: View {
  @Environment(SettingsStore.self) private var store
  @Environment(AppState.self) private var state
  @Environment(InstallState.self) private var install
  let step: WelcomeStep
  let updates: Bool

  var body: some View {
    GeometryReader { proxy in
      ScrollView(.vertical) {
        VStack(spacing: 0) {
          Group {
            switch step {
            case .install: InstallStep()
            case .add: AddStep()
            case .choose: ChooseStep()
            case .tryIt: TryStep()
            }
          }
          .frame(maxWidth: 560, alignment: .leading)
        }
        // Centred while it fits, from the top once it does not.
        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
      }
      .scrollBounceBehavior(.basedOnSize)
      .scrollIndicators(.never)
    }
  }
}

/// What the step comes to, along the bottom.
private struct StepFooter: View {
  @Environment(AppState.self) private var state
  @Environment(InstallState.self) private var install
  let step: WelcomeStep
  let updates: Bool

  var body: some View {
    HStack(spacing: 12) {
      switch step {
      case .install: InstallFooter(updates: updates)
      case .add:
        if !install.inputSource.isAdded {
          Button("以后再说") { state.welcome = .choose }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        AddFooter()
      case .choose:
        Button("下一步") { state.welcome = .tryIt }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      case .tryIt:
        Button("完成") { finishWelcome(state: state, install: install) }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
    }
    .controlSize(.large)
    .padding(.horizontal, 24)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .trailing)
    .background(Rectangle().fill(.bar))
  }
}

/// Done: on in the installed copy if this one is the download, or to the settings.
@MainActor
func finishWelcome(state: AppState, install: InstallState) {
  AddGuidePanel.shared.close()
  if !install.runsFromInstalledApp, let installed = install.installedApp {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: installed, configuration: configuration) { _, _ in
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
  } else {
    state.welcome = nil
    state.welcomeUpdates = false
  }
}

// MARK: - Building blocks

/// A caption over a card, like a form section's.
private struct Caption: View {
  let text: String

  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.system(size: 11.5, weight: .semibold))
      .foregroundStyle(.secondary)
      .padding(.leading, 2)
  }
}

/// A rounded container for a list of rows, in the settings' grouped look.
private struct Card<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) { content }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.quaternary.opacity(0.55)))
  }
}

private struct CardDivider: View {
  var body: some View {
    Divider().padding(.leading, 46)
  }
}

/// A row of a card: a symbol in a coloured tile, a title and a line about it.
struct WelcomeItem: View {
  let symbol: String
  let color: Color
  let title: String
  let detail: String
  var detailColor: Color?

  var body: some View {
    HStack(alignment: .top, spacing: 11) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 25, height: 25)
        .background(RoundedRectangle(cornerRadius: 6.5, style: .continuous).fill(color.gradient))
        .padding(.top, 1)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 13, weight: .semibold))
        Text(detail)
          .font(.system(size: 12))
          .foregroundStyle(detailColor ?? .secondary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}

/// A small status: a tick, a spinner or a hollow circle, and what it says.
private struct StatusLine: View {
  enum Kind { case done, waiting, idle, failed }

  let kind: Kind
  let text: String

  var body: some View {
    HStack(spacing: 8) {
      switch kind {
      case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
      case .waiting: ProgressView().controlSize(.small)
      case .idle: Image(systemName: "circle.dashed").foregroundStyle(.secondary)
      case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
      }
      Text(text).font(.system(size: 12.5))
    }
    .frame(height: 18)
  }
}

// MARK: - Install

private struct InstallStep: View {
  @Environment(SettingsStore.self) private var store
  @Environment(AppState.self) private var state
  @Environment(InstallState.self) private var install
  @State private var showsLog = false
  @State private var hasUserData = InstallStep.userDataExists()

  var body: some View {
    let runner = install.installer
    let running = runner.phase != .idle
    VStack(alignment: .leading, spacing: 12) {
      if running {
        Caption(runner.failure != nil ? "没有装好" : "正在安装")
        Card {
          InstallProgress(installer: runner, showsLog: $showsLog)
        }
      } else {
        Caption(Payload.canInstall ? "将要安装" : "缺少安装包")
        Card {
          WelcomeItem(symbol: "keyboard.fill", color: .blue, title: "鼠须管输入法", detail: squirrelDetail)
          CardDivider()
          WelcomeItem(symbol: "leaf.fill", color: .green, title: "雾凇拼音", detail: iceDetail)
          CardDivider()
          WelcomeItem(symbol: "gearshape.fill", color: .gray, title: "鼠须管设置",
                      detail: "就是这个 App，装进「应用程序」。以后从鼠须管的菜单里打开，改完自动生效。")
          if hasUserData {
            CardDivider()
            WelcomeItem(symbol: "person.crop.circle.fill", color: .orange, title: "你的配置和词库",
                        detail: "~/Library/Rime 里已有的都保留，不会被覆盖。")
          }
        }
        Text(footnote)
          .font(.system(size: 11.5))
          .foregroundStyle(.tertiary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 2)
      }
    }
  }

  private var footnote: String {
    if !Payload.canInstall { return "这个 App 没有带着安装包：用 scripts/build-settings.sh 重新构建它。" }
    if state.welcomeUpdates { return "只会替换鼠须管和这个 App，配置和词库不动。会弹一次管理员密码框。" }
    return "写入系统需要输入一次管理员密码。装完就可以用了，不用注销。"
  }

  private var squirrelDetail: String {
    switch install.squirrel {
    case .missing: "装到 /Library/Input Methods。"
    case .other: "替换已装的鼠须管；配置和词库不动。"
    case .current, .newer: "已经装好了这一版。"
    }
  }

  private var iceDetail: String {
    if let version = store.iceVersion {
      return "已经装好（\(version)），保留现在的版本。"
    }
    let version = Payload.rimeIceVersion.map { " \($0)" } ?? ""
    return "App 自带\(version)，不用下载：词库、全拼与各种双拼、Emoji、以词定字。"
  }

  /// The user's own settings or dictionaries are in the user folder.
  static func userDataExists() -> Bool {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: RimePaths.userDir.path)) ?? []
    return files.contains { $0.hasSuffix(".custom.yaml") || $0.hasSuffix(".userdb") }
  }
}

/// The steps install.sh is on, and its log if something goes wrong.
private struct InstallProgress: View {
  let installer: ScriptRunner
  @Binding var showsLog: Bool

  var body: some View {
    let failed = installer.failure != nil
    VStack(alignment: .leading, spacing: 7) {
      ForEach(Array(installer.steps.enumerated()), id: \.offset) { index, step in
        let last = index == installer.steps.count - 1
        HStack(spacing: 9) {
          if last && installer.isRunning {
            ProgressView().controlSize(.small).frame(width: 13, height: 13)
          } else if last && failed {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).frame(width: 13)
          } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(width: 13)
          }
          Text(step).font(.system(size: 12.5))
        }
      }
      if let failure = installer.failure {
        Text(failure)
          .font(.system(size: 12))
          .foregroundStyle(.red)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
      if installer.isRunning {
        ProgressView().progressViewStyle(.linear).controlSize(.small).padding(.top, 1)
      }
      if !installer.log.isEmpty {
        DisclosureGroup("详细信息", isExpanded: $showsLog) {
          ScrollView {
            Text(installer.log.joined(separator: "\n"))
              .font(.system(size: 11, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 120)
        }
        .font(.system(size: 12))
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }
}

private struct InstallFooter: View {
  @Environment(SettingsStore.self) private var store
  @Environment(AppState.self) private var state
  @Environment(InstallState.self) private var install
  let updates: Bool

  var body: some View {
    let runner = install.installer
    if runner.isRunning {
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text(updates ? "正在更新…" : "正在安装…").foregroundStyle(.secondary)
      }
    } else if runner.phase == .finished {
      Button(updates ? "完成" : "下一步") { next() }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    } else {
      Button(runner.failure != nil ? "重试" : updates ? "更新" : "安装") { start() }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!Payload.canInstall)
    }
  }

  private func start() {
    Task {
      guard await install.install() else { return }
      store.reloadChangedFiles()
      if updates {
        return
      }
      // A moment to read the ticks, then on to adding Squirrel.
      try? await Task.sleep(for: .seconds(0.9))
      if state.welcome == .install {
        next()
      }
    }
  }

  private func next() {
    if updates {
      finishWelcome(state: state, install: install)
    } else {
      state.welcome = install.inputSource.isAdded ? .choose : .add
    }
  }
}

// MARK: - Add to the input sources

private struct AddStep: View {
  @Environment(AppState.self) private var state
  @Environment(InstallState.self) private var install

  var body: some View {
    let added = install.inputSource.isAdded
    let phase = install.addPhase
    VStack(alignment: .leading, spacing: 12) {
      Card {
        HStack(spacing: 10) {
          if added {
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
            Text("已添加鼠须管").font(.system(size: 13, weight: .semibold))
          } else if phase == .idle {
            Image(systemName: "circle.dashed").font(.title3).foregroundStyle(.secondary)
            Text("还没有添加").font(.system(size: 13)).foregroundStyle(.secondary)
          } else {
            ProgressView().controlSize(.small)
            Text(phase == .asking ? "等系统确认…" : "等你在系统设置里添加…")
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
          }
          Spacer()
          if !added && phase != .idle {
            Text("加好了会自动打勾").font(.system(size: 11.5)).foregroundStyle(.tertiary)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
      }
      Caption("在系统设置的「键盘」里")
      Card {
        GuideSteps()
          .padding(12)
      }
      Text("macOS 只让你自己添加第三方输入法，App 不能代做。点「添加鼠须管」会先请系统帮你加；不成的话就照上面三步点几下。")
        .font(.system(size: 11.5))
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 2)
    }
    .task(id: install.addPhase) {
      guard install.addPhase != .idle else { return }
      if install.addPhase == .guiding {
        AddGuidePanel.shared.show(install: install)
      }
      await install.watchForAdded()
    }
    .onChange(of: added) { _, now in
      guard now else { return }
      AddGuidePanel.shared.finish()
      Task {
        try? await Task.sleep(for: .seconds(1.2))
        NSApp.activate()
        if state.welcome == .add {
          state.welcome = .choose
        }
      }
    }
    .onDisappear { AddGuidePanel.shared.close() }
  }
}

private struct AddFooter: View {
  @Environment(AppState.self) private var state
  @Environment(InstallState.self) private var install

  var body: some View {
    if install.inputSource.isAdded {
      Button("下一步") { state.welcome = .choose }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    } else if install.addPhase == .guiding {
      Button("重新打开系统设置") {
        Task { await install.openKeyboardSettings(restart: true) }
      }
    } else {
      Button("添加鼠须管") {
        Task { await install.addToInputSources() }
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut(.defaultAction)
      .disabled(install.addPhase == .asking)
    }
  }
}

/// What to click in System Settings' Keyboard pane.
struct GuideSteps: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      row(1, "在「文字输入」一栏，点「输入法」右边的「编辑…」")
      row(2, "点左下角的「+」")
      row(3, "左边选「简体中文」，右边选「鼠须管」，点「添加」")
    }
  }

  private func row(_ number: Int, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 9) {
      Text("\(number)")
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .frame(width: 17, height: 17)
        .background(Circle().fill(Color.accentColor))
      Text(text)
        .font(.system(size: 12.5))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// The card that floats over System Settings while the user adds Squirrel; it does not take the
/// focus, and stays when System Settings is in front.
@MainActor
final class AddGuidePanel {
  static let shared = AddGuidePanel()
  private var panel: NSPanel?

  func show(install: InstallState) {
    let panel = panel ?? make(install: install)
    self.panel = panel
    if let frame = NSScreen.main?.visibleFrame {
      panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - panel.frame.width - 24, y: frame.maxY - 24))
    }
    panel.orderFrontRegardless()
  }

  private func make(install: InstallState) -> NSPanel {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 214),
                        styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.title = "添加鼠须管"
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentView = NSHostingView(rootView: AddGuideCard().environment(install))
    return panel
  }

  /// Added: the card says so for a moment, then goes.
  func finish() {
    guard let panel, panel.isVisible else { return }
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.5))
      panel.orderOut(nil)
    }
  }

  func close() {
    panel?.orderOut(nil)
  }
}

struct AddGuideCard: View {
  @Environment(InstallState.self) private var install

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if install.inputSource.isAdded {
        HStack(spacing: 9) {
          Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
          VStack(alignment: .leading, spacing: 1) {
            Text("已添加鼠须管").font(.headline)
            Text("回到「鼠须管设置」继续。").font(.callout).foregroundStyle(.secondary)
          }
        }
      } else {
        Text("在系统设置的「键盘」里").font(.headline)
        GuideSteps()
        HStack(spacing: 7) {
          ProgressView().controlSize(.small)
          Text("加好了这里会打勾").font(.callout).foregroundStyle(.secondary)
        }
        .padding(.top, 2)
        Button("列表里没有鼠须管？") {
          install.register()
          Task { await install.openKeyboardSettings(restart: true) }
        }
        .buttonStyle(.link)
        .font(.callout)
      }
      Spacer(minLength: 0)
    }
    .padding(18)
    .frame(width: 350, height: 214, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

// MARK: - Choose

private struct ChooseStep: View {
  @Environment(SettingsStore.self) private var store

  /// rime-ice's pinyin schemas: full pinyin and the 双拼 ones.
  static let pinyin: [Choice] = [
    Choice(value: "rime_ice", title: "全拼"),
    Choice(value: "double_pinyin_flypy", title: "小鹤双拼"),
    Choice(value: "double_pinyin", title: "自然码双拼"),
    Choice(value: "double_pinyin_mspy", title: "微软双拼"),
    Choice(value: "double_pinyin_sogou", title: "搜狗双拼"),
    Choice(value: "double_pinyin_abc", title: "智能 ABC 双拼"),
    Choice(value: "double_pinyin_ziguang", title: "紫光双拼"),
    Choice(value: "double_pinyin_jiajia", title: "拼音加加双拼"),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Caption("打字")
      Card {
        row("拼音") {
          Picker("拼音", selection: scheme) {
            ForEach(schemes) { Text($0.title).tag($0.value) }
          }
          .labelsHidden()
          .fixedSize()
        }
        CardDivider()
        row("中英切换") {
          Picker("中英切换", selection: switchKey) {
            Text("Shift").tag(0)
            Text("Control").tag(1)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .fixedSize()
        }
        if store.look != .liquidGlass {
          CardDivider()
          row("候选框") {
            Button("换成液态玻璃") { store.applyRecommendedLook() }
          }
        }
      }
      Text("单独按一下 \(switchKey.wrappedValue == 1 ? "Control" : "Shift") 切换中文和英文。这些以后都能在设置里改；也可以同时启用几种方案，打字时按 F4 切换。")
        .font(.system(size: 11.5))
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 2)
    }
  }

  private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack {
      Text(title).font(.system(size: 13))
      Spacer()
      content()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
  }

  /// The installed ones, and the current default if it is another schema.
  private var schemes: [Choice] {
    let installed = Set(store.schemas.map(\.id))
    var choices = Self.pinyin.filter { installed.contains($0.value) }
    if let first = store.enabledSchemas.first, !choices.contains(where: { $0.value == first }) {
      choices.append(Choice(value: first, title: store.schemas.first { $0.id == first }?.name ?? first))
    }
    return choices
  }

  /// The default schema; picking one puts it first instead of the pinyin schema there was.
  private var scheme: Binding<String> {
    Binding(get: { store.enabledSchemas.first ?? "rime_ice" }, set: { id in
      let pinyin = Set(Self.pinyin.map(\.value))
      store.setEnabledSchemas([id] + store.enabledSchemas.filter { $0 != id && !pinyin.contains($0) })
    })
  }

  /// 0: Shift switches, 1: Control does.
  private var switchKey: Binding<Int> {
    Binding(get: {
      store.switchKey(.leftShift) == "noop" && store.switchKey(.leftControl) != "noop" ? 1 : 0
    }, set: { control in
      let (shift, ctrl) = control == 1 ? ("noop", "commit_code") : ("commit_code", "noop")
      store.setSwitchKey(.leftShift, shift)
      store.setSwitchKey(.rightShift, shift)
      store.setSwitchKey(.leftControl, ctrl)
      store.setSwitchKey(.rightControl, ctrl)
    })
  }
}

// MARK: - Try

private struct TryStep: View {
  @Environment(SettingsStore.self) private var store
  @Environment(InstallState.self) private var install
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Card {
        HStack(spacing: 9) {
          if install.inputSource.selected {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("正在用鼠须管").font(.system(size: 13, weight: .semibold))
          } else {
            Image(systemName: "keyboard").foregroundStyle(.secondary)
            Text("现在用的不是鼠须管").font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
            Button("切换到鼠须管") {
              install.select()
              focused = true
            }
            .disabled(!install.inputSource.isAdded)
          }
          Spacer(minLength: 8)
          deployStatus
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        CardDivider()
        TextField("在这里打字试试，比如 nihao", text: $text)
          .textFieldStyle(.plain)
          .font(.system(size: 15))
          .focused($focused)
          .padding(.horizontal, 12)
          .padding(.vertical, 11)
      }
      Caption("几个常用按键")
      Card {
        tip("Tab", "展开更多候选，接着按往下翻；Shift-Tab 往回")
        CardDivider()
        tip(store.switchKey(.leftShift) == "noop" && store.switchKey(.leftControl) != "noop" ? "Control" : "Shift", "切换中文和英文")
        CardDivider()
        tip("-  =", "上一页、下一页")
        CardDivider()
        tip("[  ]", "以词定字：只上屏词的第一个字、最后一个字")
      }
    }
    .onAppear { focused = true }
  }

  private func tip(_ key: String, _ text: String) -> some View {
    HStack(spacing: 10) {
      Text(key)
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.quaternary))
        .foregroundStyle(.secondary)
        .frame(width: 66, alignment: .center)
      Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }

  /// Whether Squirrel can type yet: the first deploy builds rime-ice's dictionaries.
  @ViewBuilder
  private var deployStatus: some View {
    let schema = store.enabledSchemas.first ?? "rime_ice"
    let built = FileManager.default.fileExists(atPath: RimePaths.buildDir.appending(component: "\(schema).prism.bin").path)
    if store.deployer.state == .deploying || store.hasUnsavedChanges {
      StatusLine(kind: .waiting, text: "正在准备词库…")
    } else if install.lastDeploy?.succeeded == false {
      StatusLine(kind: .failed, text: "部署出错")
    } else if install.lastDeploy?.succeeded == true || built {
      StatusLine(kind: .done, text: "可以打字了")
    } else if !install.isSquirrelRunning {
      Button("启动鼠须管") { install.launchSquirrel() }
        .buttonStyle(.link)
        .font(.system(size: 12))
    } else {
      StatusLine(kind: .waiting, text: "第一次要准备词库，约十几秒")
    }
  }
}
