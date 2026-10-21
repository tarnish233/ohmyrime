//
//  InputPage.swift
//  鼠须管设置
//
//  Schemas, candidates per page, the Chinese / English switch, paging and other keys.
//  default.custom.yaml (and scroll mode's Tab paging in squirrel.custom.yaml).
//

import SwiftUI

struct InputPage: View {
  @Environment(SettingsStore.self) private var store
  @Environment(AppState.self) private var state
  @State private var showsAllSchemas = false

  var body: some View {
    Form {
      schemaSection
      Section {
        StepperRow(title: "每页候选数", value: store.binding(store.defaults, "menu/page_size", default: 5).asDouble, range: 1...10)
      } header: {
        Text("候选")
      } footer: {
        Note("卷轴模式下也是每行的个数。")
      }
      punctuationSection
      switchSection
      pagingSection
      Section {
        Picker("以词定字", selection: Binding(get: { store.selectCharacterKeys?.rawValue ?? "" },
                                         set: { store.setSelectCharacterKeys(PagingKeys(rawValue: $0)) })) {
          ForEach(PagingKeys.allCases) { Text($0.title).tag($0.rawValue) }
          Text("不使用").tag("")
        }
      } footer: {
        Note("打出一个词后按左边的键只上屏它的第一个字，右边的键只上屏最后一个字。")
      }
      Section {
        ForEach(SettingsStore.switcherHotkeys) { hotkey in
          Toggle(hotkey.title, isOn: Binding(get: { store.hotkeys.contains(hotkey.value) }, set: { store.setHotkey(hotkey.value, $0) }))
        }
      } header: {
        Text("方案选单")
      } footer: {
        Note("按这些键打开方案选单：切换输入方案、简繁、全半角等。")
      }
    }
    .formStyle(.grouped)
  }

  // MARK: Schemas

  private var orderedSchemas: (enabled: [SchemaInfo], rest: [SchemaInfo]) {
    let enabledIDs = store.enabledSchemas
    let byID = Dictionary(store.schemas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let enabled = enabledIDs.map {
      byID[$0] ?? SchemaInfo(id: $0, name: $0 == "rime_ice" ? "雾凇拼音" : $0, dependencies: [], bundled: false, missing: true)
    }
    // 雾凇拼音自带好几个双拼方案，加上鼠须管自带的，没启用的都收起来：大多数人用不到，全摆在面上太满。
    let rest = store.schemas.filter { !enabledIDs.contains($0.id) }
    return (enabled, rest)
  }

  @ViewBuilder
  private var schemaSection: some View {
    let schemas = orderedSchemas
    Section {
      ForEach(Array(schemas.enabled.enumerated()), id: \.element.id) { index, schema in
        schemaRow(schema, enabled: true, index: index, count: schemas.enabled.count)
      }
      if !schemas.rest.isEmpty {
        DisclosureGroup("更多方案（\(schemas.rest.count)）", isExpanded: $showsAllSchemas) {
          ForEach(schemas.rest) { schemaRow($0, enabled: false, index: 0, count: 0) }
        }
      }
    } header: {
      Text("输入方案")
    } footer: {
      Note(schemaFooter)
    }
  }

  private var schemaFooter: String {
    var text = ""
    if !store.missingSchemas.isEmpty {
      text = "标着「未安装」的方案找不到方案文件，鼠须管用不了"
      text += store.typesOnlyEnglish ? "；现在启用的方案都用不了，只能打英文。" : "。"
    }
    return text + "排在第一个的是默认方案。打字时按 F4 切换方案。新启用的方案第一次部署要多等几秒。"
  }

  private func schemaRow(_ schema: SchemaInfo, enabled: Bool, index: Int, count: Int) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 6) {
          Text(schema.name)
          if schema.missing {
            Text("未安装")
              .font(.caption.weight(.medium))
              .foregroundStyle(.orange)
              .padding(.horizontal, 6)
              .padding(.vertical, 1)
              .background(Capsule().fill(.orange.opacity(0.15)))
          }
        }
        Text(schema.id).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if schema.missing && SettingsStore.isIceSchema(schema.id) {
        Button("安装雾凇拼音…") { state.page = .ice }
          .buttonStyle(.link)
      }
      if enabled && count > 1 {
        Button {
          move(schema.id, by: -1)
        } label: {
          Image(systemName: "chevron.up")
        }
        .buttonStyle(.borderless)
        .disabled(index == 0)
        .help("上移")
        Button {
          move(schema.id, by: 1)
        } label: {
          Image(systemName: "chevron.down")
        }
        .buttonStyle(.borderless)
        .disabled(index == count - 1)
        .help("下移")
      }
      Toggle("启用", isOn: Binding(get: { enabled }, set: { setEnabled(schema.id, $0) }))
        .labelsHidden()
        .toggleStyle(.switch)
        .disabled(enabled && count == 1)
    }
  }

  private func setEnabled(_ id: String, _ enabled: Bool) {
    var ids = store.enabledSchemas.filter { $0 != id }
    if enabled {
      ids.append(id)
    }
    store.setEnabledSchemas(ids)
  }

  private func move(_ id: String, by offset: Int) {
    var ids = store.enabledSchemas
    guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
    ids.swapAt(index, index + offset)
    store.setEnabledSchemas(ids)
  }

  private var punctuationSection: some View {
    Section {
      Toggle("中文标点下 / 打成「、」", isOn: Binding(get: { store.slashIsIdea }, set: { store.setSlashIsIdea($0) }))
    } header: {
      Text("标点")
    } footer: {
      Note("打开后，中文标点状态下按 / 直接上屏顿号「、」，英文标点状态还是 /。微信输入法也是这样。")
    }
  }

  // MARK: Keys

  @ViewBuilder
  private var switchSection: some View {
    Section {
      ForEach(SwitchKey.allCases) { key in
        Picker(key.title, selection: Binding(get: { store.switchKey(key) }, set: { store.setSwitchKey(key, $0) })) {
          ForEach(key.actions) { Text($0.title).tag($0.value) }
        }
      }
      Toggle("Caps Lock 打开时输入大写字母", isOn: store.binding(store.defaults, "ascii_composer/good_old_caps_lock", default: true))
    } header: {
      Text("中英切换")
    } footer: {
      Note("单独按一下这些键时怎样切换。系统设置里勾选了「使用大写锁定键切换“ABC”输入法」时，Caps Lock 总是用来切换输入法。")
    }
  }

  @ViewBuilder
  private var pagingSection: some View {
    let conflict = store.selectCharacterKeys.map { store.isPaging($0) } ?? false
    Section {
      ForEach(PagingKeys.allCases) { keys in
        Toggle(keys.title, isOn: Binding(get: { store.isPaging(keys) }, set: { store.setPaging(keys, $0) }))
      }
      let scrollMode = store.bool(store.squirrel, "style/scroll_mode/enable") == true
      Toggle("Tab 和 Shift-Tab（卷轴模式）", isOn: store.binding(store.squirrel, "style/scroll_mode/tab_paging", default: true))
        .disabled(!scrollMode)
    } header: {
      Text("翻页")
    } footer: {
      if conflict {
        Label("翻页键和以词定字用了同一对键，以词定字会先起作用。", systemImage: "exclamationmark.triangle")
          .font(.callout)
          .foregroundStyle(.orange)
      } else {
        Note("左边的键上一页，右边的键下一页。Tab 翻页需要在「外观」里打开卷轴模式。")
      }
    }
  }
}
