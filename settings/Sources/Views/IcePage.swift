//
//  IcePage.swift
//  鼠须管设置
//
//  rime-ice's options: the default state of its switches, and fuzzy pinyin.
//  rime_ice.custom.yaml (and double_pinyin_*.custom.yaml for enabled 双拼 schemas).
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
      } else {
        Section {
          Label("没有找到雾凇拼音（rime_ice.schema.yaml）。用 ohmyrime 的 scripts/rime-ice.sh 安装后再来这里。", systemImage: "leaf")
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
