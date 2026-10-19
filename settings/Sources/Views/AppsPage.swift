//
//  AppsPage.swift
//  鼠须管设置
//
//  How Squirrel starts in particular apps: English, without inline composition, Vim mode.
//  app_options in squirrel.custom.yaml.
//

import SwiftUI
import UniformTypeIdentifiers

struct AppsPage: View {
  @Environment(SettingsStore.self) private var store
  @State private var selection = Set<String>()

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Note("切到这些应用时，鼠须管按这里的设置开始。默认英文：适合终端、代码编辑器；不内嵌编码：编码显示在候选框里，不插进正在输入的文字；Vim 模式：按 Esc 离开插入模式时自动切到英文。")
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
      Table(store.apps, selection: $selection) {
        TableColumn("应用") { app in
          HStack(spacing: 8) {
            Image(nsImage: app.icon)
              .resizable()
              .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 0) {
              Text(app.name)
                .foregroundStyle(app.url == nil ? .secondary : .primary)
              if app.name != app.id {
                Text(app.id).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
        TableColumn("默认英文") { app in optionToggle(app, "ascii_mode") }
          .width(76)
        TableColumn("不内嵌编码") { app in optionToggle(app, "no_inline") }
          .width(76)
        TableColumn("Vim 模式") { app in optionToggle(app, "vim_mode") }
          .width(76)
      }
      .tableStyle(.inset(alternatesRowBackgrounds: true))
      // Otherwise the table asks for all its rows' height, more than the window has.
      .frame(minHeight: 160, maxHeight: .infinity)
      Divider()
      HStack(spacing: 0) {
        Button {
          addApp()
        } label: {
          Image(systemName: "plus").frame(width: 24, height: 20)
        }
        .help("添加应用")
        Divider().frame(height: 16)
        Button {
          selection.forEach(store.removeApp)
          selection = []
        } label: {
          Image(systemName: "minus").frame(width: 24, height: 20)
        }
        .disabled(selection.isEmpty)
        .help("移除选中的应用")
        Spacer()
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
    }
  }

  private func optionToggle(_ app: AppEntry, _ option: String) -> some View {
    Toggle(option, isOn: Binding(get: { app.options[option] ?? false }, set: { store.setAppOption(app.id, option, $0) }))
      .labelsHidden()
      .toggleStyle(.checkbox)
  }

  private func addApp() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = true
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.prompt = "添加"
    guard panel.runModal() == .OK else { return }
    for url in panel.urls {
      if let id = Bundle(url: url)?.bundleIdentifier {
        store.addApp(id)
        selection = [id]
      }
    }
  }
}
