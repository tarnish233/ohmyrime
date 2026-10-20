//
//  AboutPage.swift
//  鼠须管设置
//
//  The About page, in the sidebar below the user data: what this is, which versions are
//  installed, checking for a newer ohmyrime and installing it, and where to read more.
//

import AppKit
import SwiftUI

struct AboutPage: View {
  @Environment(SettingsStore.self) private var store
  @Environment(InstallState.self) private var install
  @Environment(UpdateCenter.self) private var updates

  var body: some View {
    Form {
      Section {
        HStack(spacing: 14) {
          Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 64, height: 64)
            .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
          VStack(alignment: .leading, spacing: 3) {
            Text("鼠须管设置")
              .font(.title3.weight(.semibold))
            Text("ohmyrime，鼠须管 + 雾凇拼音")
              .font(.callout)
              .foregroundStyle(.secondary)
            Text("版本 \(Payload.version)")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
          Spacer()
        }
        .padding(.vertical, 4)
      }

      Section {
        HStack(spacing: 10) {
          updateStatus
          Spacer(minLength: 8)
          updateButtons
        }
      } header: {
        Text("更新")
      } footer: {
        Note("每天自动检查一次。检查走 GitHub 的发布页，不用代理，也不上报任何信息。")
      }

      Section {
        LabeledContent("鼠须管") {
          Text(squirrelDetail)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }
        LabeledContent("雾凇拼音") {
          Text(store.iceVersion.map { "版本 \($0)" } ?? "没有安装")
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("已安装")
      } footer: {
        Note("鼠须管装到 /Library/Input Methods，雾凇拼音和你的配置在 ~/Library/Rime。")
      }

      Section {
        HStack {
          link("项目主页", "https://github.com/tarnish233/ohmyrime")
          link("发布页", "https://github.com/tarnish233/ohmyrime/releases")
          link("技术文档", "https://github.com/tarnish233/ohmyrime/blob/main/docs/development.md")
          link("许可证", "https://github.com/tarnish233/ohmyrime/blob/main/LICENSE")
          Spacer()
        }
      } header: {
        Text("链接")
      } footer: {
        Note("鼠须管来自 rime/squirrel，雾凇拼音来自 iDvel/rime-ice，都按 GPL-3.0 发布；ohmyrime 同为 GPL-3.0。© 2026 tarnish233")
      }
    }
    .formStyle(.grouped)
  }

  // MARK: Update

  @ViewBuilder
  private var updateStatus: some View {
    if let message = updates.installFailure {
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .font(.callout)
        .foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
    } else {
      switch updates.install {
      case .downloading:
        status(.waiting, "正在下载…")
      case .verifying:
        status(.waiting, "正在校验…")
      case .replacing:
        status(.waiting, "正在替换这个 App…")
      case .idle:
        switch updates.phase {
        case .idle:
          status(.idle, "还没检查过")
        case .checking:
          status(.waiting, "正在检查…")
        case .upToDate(let date):
          status(.done, "已是最新版本（\(date.formatted(date: .omitted, time: .shortened)) 查过）")
        case .available(let release):
          status(.new, "有新版本 \(release.shortVersion)，现在装的是 \(Payload.version)")
        case .failed(let message):
          Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      case .failed:
        EmptyView()
      }
    }
  }

  private enum StatusKind { case idle, waiting, done, new }

  private func status(_ kind: StatusKind, _ text: String) -> some View {
    HStack(spacing: 8) {
      switch kind {
      case .idle: Image(systemName: "circle.dashed").foregroundStyle(.secondary)
      case .waiting: ProgressView().controlSize(.small)
      case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
      case .new: Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
      }
      Text(text).font(.callout)
    }
  }

  @ViewBuilder
  private var updateButtons: some View {
    if let release = updates.release, updates.installFailure == nil {
      HStack(spacing: 8) {
        Button("发布说明") { NSWorkspace.shared.open(release.pageURL) }
        Button("下载并安装") { Task { await updates.installRelease() } }
        .buttonStyle(.borderedProminent)
        .disabled(updates.install != .idle)
      }
    } else if updates.installFailure != nil {
      Button("重试") { Task { await updates.installRelease() } }
        .buttonStyle(.borderedProminent)
    } else if updates.install == .idle {
      Button(updates.isChecking ? "检查中…" : "检查更新") {
        Task { await updates.check() }
      }
      .disabled(updates.isChecking)
    }
  }

  private var squirrelDetail: String {
    switch install.squirrel {
    case .missing: "没有安装"
    case .current: "这一版自带的，已安装"
    case .other: "已安装的是另一版，在「欢迎使用 ohmyrime…」里可以更新"
    case .newer: "已安装的是更新版本"
    }
  }

  private func link(_ title: String, _ address: String) -> some View {
    Button(title) {
      if let url = URL(string: address) {
        NSWorkspace.shared.open(url)
      }
    }
  }
}
