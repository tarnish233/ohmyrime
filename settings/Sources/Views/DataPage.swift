//
//  DataPage.swift
//  鼠须管设置
//
//  The user dictionaries, sync and backup, deploying, and the folders behind it all.
//

import SwiftUI
import UniformTypeIdentifiers

struct DataPage: View {
  @Environment(SettingsStore.self) private var store
  @Environment(InstallState.self) private var install
  @State private var dictionaries = UserDictionary.all()
  @State private var backupMessage: String?
  @State private var confirmsUninstall = false

  var body: some View {
    Form {
      Section {
        if dictionaries.isEmpty {
          Text("还没有用户词库：打几个字后就会有。").foregroundStyle(.secondary)
        }
        ForEach(dictionaries) { dictionary in
          LabeledContent {
            Text(ByteCountFormatter.string(fromByteCount: dictionary.size, countStyle: .file) + (dictionary.modified.map { " · " + $0.formatted(.relative(presentation: .named)) + "更新" } ?? ""))
          } label: {
            Text(dictionary.id + ".userdb")
            Text(description(of: dictionary.id)).font(.caption).foregroundStyle(.secondary)
          }
        }
      } header: {
        Text("用户词库")
      } footer: {
        Note("打字时学到的新词、调整过的候选顺序，存在 ~/Library/Rime 里，只在这台 Mac 上，不会上传。")
      }

      Section {
        LabeledContent("同步文件夹") {
          HStack {
            Text(store.syncFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
              .lineLimit(1)
              .truncationMode(.middle)
              .textSelection(.enabled)
            Button("更改…") { chooseSyncFolder() }
            if store.installation.syncDir != nil {
              Button("恢复默认") { store.setSyncDir(nil) }
            }
          }
        }
        HStack {
          Button("立即同步") {
            store.deployer.syncUserData()
          }
          Button("在访达中显示") {
            NSWorkspace.shared.open(FileManager.default.fileExists(atPath: store.syncFolder.path) ? store.syncFolder : store.syncFolder.deletingLastPathComponent())
          }
          Spacer()
          Button("备份用户文件夹…") { backUp() }
        }
        if let backupMessage {
          Note(backupMessage)
        }
      } header: {
        Text("同步与备份")
      } footer: {
        Note("同步：把词库导出成文本（如 rime_ice.userdb.txt）和配置一起放进同步文件夹，同时合并别的电脑放在那里的词库。把同步文件夹设在 iCloud 云盘里，就能在多台 Mac 间共用。备份：把整个用户文件夹（不含部署产物）存成一个 .tar.gz。")
      }

      Section("部署") {
        LabeledContent("状态") {
          DeployStatusButton()
        }
        if !store.deployer.errors.isEmpty {
          Text(store.deployer.errors.suffix(12).joined(separator: "\n"))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        HStack {
          Button("重新部署") { store.redeploy() }
          Spacer()
          Button("打开日志文件夹") { NSWorkspace.shared.open(RimePaths.logDir) }
        }
      }

      Section("文件夹") {
        HStack {
          Button("打开用户文件夹") { NSWorkspace.shared.open(RimePaths.userDir) }
          Button("打开改动前的备份") {
            try? FileManager.default.createDirectory(at: RimePaths.backupDir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(RimePaths.backupDir)
          }
          Spacer()
        }
      }

      Section {
        HStack {
          Text("卸载 ohmyrime")
          Spacer()
          if install.uninstaller.isRunning {
            ProgressView().controlSize(.small)
            Text(install.uninstaller.steps.last ?? "正在卸载…").foregroundStyle(.secondary)
          } else {
            Button("卸载…") { confirmsUninstall = true }
              .disabled(Payload.uninstallScript == nil)
          }
        }
        if let failure = install.uninstaller.failure {
          Text(failure).font(.callout).foregroundStyle(.red).textSelection(.enabled)
        }
      } header: {
        Text("卸载")
      } footer: {
        Note("从输入法里移除鼠须管，删除鼠须管和这个 App，会弹一次管理员密码框。配置和用户词库默认保留，以后再装还能接着用。")
      }
    }
    .formStyle(.grouped)
    .confirmationDialog("卸载 ohmyrime？", isPresented: $confirmsUninstall) {
      Button("卸载，保留配置和词库") { uninstall(purge: false) }
      Button("卸载，并删除配置和词库", role: .destructive) { uninstall(purge: true) }
      Button("取消", role: .cancel) {}
    } message: {
      Text("卸载后系统会换成别的输入法。删除配置和词库会一并删掉 ~/Library/Rime 和改设置前的备份，删了就找不回来。")
    }
    .onAppear { dictionaries = UserDictionary.all() }
  }

  /// Uninstalls with the bundled uninstall.sh, then quits: the app is gone.
  private func uninstall(purge: Bool) {
    Task {
      // Changes still waiting to be saved would come back into a deleted folder.
      if purge {
        store.discardUnsavedChanges()
      } else if store.hasUnsavedChanges {
        store.saveNow(immediately: true)
      }
      if await install.uninstall(purge: purge) {
        NSApp.terminate(nil)
      }
    }
  }

  private func description(of dictionary: String) -> String {
    let names = Dictionary(store.schemas.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    switch dictionary {
    case "rime_ice": return "雾凇拼音（全拼、双拼共用）"
    case "luna_pinyin": return "朙月拼音（换成雾凇之前用的，已不再使用）"
    default: return names[dictionary] ?? ""
    }
  }

  private func chooseSyncFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.prompt = "选择"
    panel.message = "选一个文件夹存放同步数据，比如 iCloud 云盘里的一个文件夹"
    let iCloud = FileManager.default.homeDirectoryForCurrentUser.appending(components: "Library", "Mobile Documents", "com~apple~CloudDocs")
    panel.directoryURL = FileManager.default.fileExists(atPath: iCloud.path) ? iCloud : nil
    guard panel.runModal() == .OK, let url = panel.url else { return }
    store.setSyncDir(url.path)
  }

  private func backUp() {
    let panel = NSSavePanel()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    panel.nameFieldStringValue = "Rime-\(formatter.string(from: Date())).tar.gz"
    panel.allowedContentTypes = [UTType(filenameExtension: "gz") ?? .data]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try SettingsStore.backUpUserFolder(to: url)
      backupMessage = "已备份到 \(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
    } catch {
      backupMessage = "备份失败：\(error.localizedDescription)"
    }
  }
}
