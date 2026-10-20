//
//  ContentView.swift
//  鼠须管设置
//
//  A sidebar of pages, like System Settings, and the deploy status in the toolbar.
//

import SwiftUI

enum Page: String, CaseIterable, Identifiable {
  case appearance, input, ice, apps, phrases, data
  var id: String { rawValue }

  var title: String {
    switch self {
    case .appearance: "外观"
    case .input: "输入"
    case .ice: "雾凇拼音"
    case .apps: "应用"
    case .phrases: "短语"
    case .data: "词库与部署"
    }
  }

  var symbol: String {
    switch self {
    case .appearance: "paintpalette.fill"
    case .input: "keyboard.fill"
    case .ice: "leaf.fill"
    case .apps: "square.grid.2x2.fill"
    case .phrases: "text.bubble.fill"
    case .data: "books.vertical.fill"
    }
  }

  var color: Color {
    switch self {
    case .appearance: .blue
    case .input: .gray
    case .ice: .green
    case .apps: .purple
    case .phrases: .orange
    case .data: .brown
    }
  }
}

struct SidebarIcon: View {
  let page: Page

  var body: some View {
    Image(systemName: page.symbol)
      .font(.system(size: 11.5, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 22, height: 22)
      .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(page.color.gradient))
  }
}

struct ContentView: View {
  @Environment(SettingsStore.self) private var store
  @Environment(AppState.self) private var state

  var body: some View {
    @Bindable var state = state
    NavigationSplitView {
      List(selection: Binding<Page?>(get: { state.page }, set: { state.page = $0 ?? state.page })) {
        ForEach(Page.allCases) { page in
          Label { Text(page.title) } icon: { SidebarIcon(page: page) }
            .tag(page)
        }
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
    } detail: {
      VStack(spacing: 0) {
        if !store.problems.isEmpty || store.saveError != nil {
          ProblemBanner(messages: store.problems + [store.saveError].compactMap { $0 })
        }
        if store.typesOnlyEnglish && state.page != .ice {
          EnglishOnlyBanner()
        }
        page(state.page)
      }
      .navigationTitle(state.page.title)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          DeployStatusButton()
        }
      }
    }
  }

  @ViewBuilder
  private func page(_ page: Page) -> some View {
    switch page {
    case .appearance: AppearancePage()
    case .input: InputPage()
    case .ice: IcePage()
    case .apps: AppsPage()
    case .phrases: PhrasesPage()
    case .data: DataPage()
    }
  }
}

struct ProblemBanner: View {
  let messages: [String]

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 2) {
        ForEach(messages, id: \.self) { Text($0) }
      }
      .font(.callout)
      Spacer()
    }
    .padding(10)
    .background(.orange.opacity(0.12))
  }
}

/// Every enabled schema is missing (rime-ice is not installed yet, say): Squirrel types only English.
struct EnglishOnlyBanner: View {
  @Environment(SettingsStore.self) private var store
  @Environment(AppState.self) private var state

  var body: some View {
    let ice = store.missingSchemas.contains(where: SettingsStore.isIceSchema)
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      Text(ice ? "雾凇拼音还没有安装，鼠须管现在只能打英文。" : "启用的输入方案都找不到方案文件，鼠须管现在只能打英文。")
        .font(.callout)
      Spacer()
      if ice {
        Button("安装雾凇拼音…") { state.page = .ice }
      } else if state.page != .input {
        Button("选择输入方案…") { state.page = .input }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.orange.opacity(0.12))
  }
}

/// Saved and deployed, deploying, or why not; details and 「重新部署」 in a popover.
struct DeployStatusButton: View {
  @Environment(SettingsStore.self) private var store
  @State private var showsDetails = false

  var body: some View {
    Button {
      showsDetails.toggle()
    } label: {
      HStack(spacing: 6) {
        indicator
        Text(title)
      }
      .padding(.horizontal, 4)
    }
    .help("部署状态")
    .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
      DeployDetails()
        .environment(store)
    }
  }

  private var deployer: Deployer { store.deployer }

  @ViewBuilder
  private var indicator: some View {
    if store.hasUnsavedChanges || deployer.state == .deploying {
      ProgressView().controlSize(.small)
    } else {
      switch deployer.state {
      case .failed, .noAnswer:
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      case .succeeded:
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
      default:
        Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
      }
    }
  }

  private var title: String {
    if store.hasUnsavedChanges {
      return "保存中…"
    }
    switch deployer.state {
    case .idle: return "已是最新"
    case .deploying: return "部署中…"
    case .succeeded: return deployer.errors.isEmpty ? "已生效" : "已生效（有警告）"
    case .failed: return "部署失败"
    case .noAnswer: return "已保存"
    }
  }
}

struct DeployDetails: View {
  @Environment(SettingsStore.self) private var store

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(summary).font(.headline)
      Text(explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if !store.deployer.errors.isEmpty {
        ScrollView {
          Text(store.deployer.errors.suffix(30).joined(separator: "\n"))
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 160)
      }
      HStack {
        Button("重新部署") { store.redeploy() }
        Button("打开日志文件夹") { NSWorkspace.shared.open(RimePaths.logDir) }
        Spacer()
      }
    }
    .padding(16)
    .frame(width: 380)
  }

  private var summary: String {
    switch store.deployer.state {
    case .idle: "设置会在改动后自动保存并生效"
    case .deploying: "鼠须管正在部署…"
    case .succeeded(let date): "\(date.formatted(date: .omitted, time: .standard)) 已生效"
    case .failed: "部署失败"
    case .noAnswer: "已保存，但鼠须管没有回应"
    }
  }

  private var explanation: String {
    switch store.deployer.state {
    case .failed: "Rime 没能读懂改过的配置，下面是日志里的错误。可以改回刚才的设置，或打开日志查看。"
    case .noAnswer: "改动已写进 ~/Library/Rime，但没收到鼠须管部署完成的消息：鼠须管可能没在运行，或者还是旧版本。在菜单栏输入法菜单里选一次鼠须管，或点「重新部署」。"
    case .succeeded where store.deployer.lastOutcome == "reloaded":
      "只改了外观：鼠须管重新载入了外观，Rime 没有重启，各应用里正在输入的内容和中英状态都不受影响。改之前的文件备份在 ~/Library/Application Support/鼠须管设置/Backups。"
    default: "改动写进 ~/Library/Rime 下的 *.custom.yaml。只改外观时，鼠须管只重新载入外观；其他改动重新部署 Rime，要零点几秒到几秒：「输入」页的改动会重建每个方案（约 3 秒），装新方案时要十几秒。改之前的文件备份在 ~/Library/Application Support/鼠须管设置/Backups。"
    }
  }
}
