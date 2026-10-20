//
//  IcePage.swift
//  鼠须管设置
//
//  rime-ice's options: the default state of its switches, and fuzzy pinyin.
//  rime_ice.custom.yaml (and double_pinyin_*.custom.yaml for enabled 双拼 schemas).
//  Installing rime-ice when it is not there (the copy the app carries, without downloading),
//  updating it when it is (the latest release, from GitHub) (RimeIceInstaller).
//

import SwiftUI

struct IcePage: View {
  @Environment(SettingsStore.self) private var store

  var body: some View {
    Form {
      if let main = store.mainIceSchema {
        Section {
          ForEach(store.switches(of: main)) { item in
            Picker(item.title, selection: Binding(get: { store.switchDefault(item.name) }, set: { store.setSwitchDefault(item.name, $0) })) {
              Text(item.options[0]).tag(0)
              Text(item.options[1]).tag(1)
            }
            .pickerStyle(.segmented)
          }
        } header: {
          Text("新输入框的默认状态")
        } footer: {
          Note("每切到一个新的输入框时从这个状态开始。打字时可以临时切换：Control-Shift-3 中英标点，Control-Shift-4 简繁，或按 F4 打开方案选单。")
        }
        Section {
          ForEach(SettingsStore.fuzzyRules) { rule in
            Toggle(rule.title, isOn: Binding(get: { store.isFuzzy(rule) }, set: { store.setFuzzy(rule, $0) }))
          }
        } header: {
          Text("模糊音")
        } footer: {
          Note("分不清这些音时打开，两种拼法都能打出字。开得越多，重码越多。对\(schemaNames)生效。")
        }
        Section {
          IceInstallRow()
        } header: {
          Text("雾凇拼音")
        } footer: {
          Note("下载最新发布版，覆盖雾凇拼音自己的文件（词库、方案、脚本）。你的设置、用户词库和自定义短语不动；更新前会把用户文件夹备份到 ~/Library/Application Support/鼠须管设置/Backups。")
        }
      } else {
        Section {
          VStack(alignment: .leading, spacing: 6) {
            Label("还没有安装雾凇拼音", systemImage: "leaf.fill")
              .font(.headline)
            Text("雾凇拼音是一整套 Rime 配置：常用词库、全拼和双拼方案、Emoji、以词定字、日期和计算器等。装好后，这一页可以设置它的默认状态和模糊音。")
              .font(.callout)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(.vertical, 4)
          IceInstallRow()
        } footer: {
          Note("装 App 自带的版本\(Payload.rimeIceVersion.map { "（\($0)）" } ?? "")，不用下载；装进 ~/Library/Rime 并设为默认方案。你的 *.custom.yaml、用户词库和自定义短语都会保留；不装它的 squirrel.yaml，外观仍按「外观」页的设置。安装前会把用户文件夹备份到 ~/Library/Application Support/鼠须管设置/Backups。")
        }
      }
    }
    .formStyle(.grouped)
  }

  private var schemaNames: String {
    let names = Dictionary(store.schemas.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    return store.iceSchemas.map { "「\(names[$0] ?? $0)」" }.joined(separator: "、")
  }
}

/// Installs or updates rime-ice: the button, the download's progress, how it went, and the log.
struct IceInstallRow: View {
  @Environment(SettingsStore.self) private var store
  @State private var showsLog = false

  var body: some View {
    let installer = store.iceInstaller
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
          if let detail {
            Text(detail)
              .font(.callout)
              .foregroundStyle(isFailure ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        Spacer()
        if installer.canCancel {
          Button("取消") { installer.cancel() }
        } else if installer.isRunning {
          ProgressView().controlSize(.small)
        } else if store.iceInstalled {
          Button(isFailure ? "重试" : "更新到最新版") { start() }
        } else {
          Button(isFailure ? "重试" : "安装雾凇拼音") { start() }
            .buttonStyle(.borderedProminent)
        }
      }
      if case .downloading(let fraction) = installer.phase {
        if let fraction {
          ProgressView(value: fraction)
        } else {
          ProgressView().progressViewStyle(.linear)
        }
      }
      if !installer.log.isEmpty {
        DisclosureGroup("详细信息", isExpanded: $showsLog) {
          ScrollView {
            Text(installer.log.joined(separator: "\n"))
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 140)
        }
        .font(.callout)
      }
    }
    .padding(.vertical, 2)
  }

  /// Not installed: the copy the app carries. Installed: the latest release.
  private func start() {
    showsLog = false
    let bundled = store.iceInstalled ? nil : Payload.rimeIceArchive
    Task { await store.installRimeIce(from: bundled.map { .archive($0) } ?? .download) }
  }

  private var isFailure: Bool {
    switch store.iceInstaller.phase {
    case .failed: true
    default: false
    }
  }

  private var title: String {
    switch store.iceInstaller.phase {
    case .downloading(let fraction): "正在下载…" + (fraction.map { " \(Int($0 * 100))%" } ?? "")
    case .installing: "正在安装…"
    case .finished: store.iceInstaller.summary ?? "已安装"
    case .failed: "没有装上"
    case .cancelled: "已取消"
    case .idle: store.iceInstalled ? "已安装" + (store.iceVersion.map { "：版本 \($0)" } ?? "") : "安装雾凇拼音"
    }
  }

  private var detail: String? {
    switch store.iceInstaller.phase {
    case .downloading: "从 GitHub 下载 full.zip，约 16 MB"
    case .installing: "备份用户文件夹，复制词库、方案和脚本"
    case .failed(let message): message
    case .finished: deployStatus
    case .idle: store.iceInstalled ? nil : (Payload.rimeIceArchive != nil ? "App 自带，不用下载，几秒钟装好" : "从 GitHub 下载，约 16 MB")
    case .cancelled: nil
    }
  }

  /// The deploy after the install: building rime-ice's dictionaries takes a while the first time.
  private var deployStatus: String? {
    guard let finished = store.iceInstaller.finishedAt else { return nil }
    switch store.deployer.state {
    case .deploying: return "鼠须管正在部署：第一次要编译词库，大约十几秒…"
    case .succeeded(let date) where date >= finished: return "已生效，可以打字了。"
    case .failed(let date) where date >= finished: return "部署失败，详情见右上角的部署状态。"
    case .noAnswer: return "鼠须管没有回应：在输入法菜单里选一次鼠须管。"
    default: return store.deploysAfterSaving ? "等待部署…" : nil
    }
  }
}
