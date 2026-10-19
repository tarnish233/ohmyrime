//
//  AppearancePage.swift
//  鼠须管设置
//
//  The candidate panel: look, layout and scroll mode, fonts, sizes. squirrel.custom.yaml.
//

import SwiftUI

struct AppearancePage: View {
  @Environment(SettingsStore.self) private var store

  var body: some View {
    VStack(spacing: 0) {
      CandidatePreview()
      Form {
        lookSection
        layoutSection
        fontSection
        sizeSection
        otherSection
        Section {
          HStack {
            Button("恢复推荐外观") { store.applyRecommendedLook() }
            Spacer()
          }
        } footer: {
          Note("液态玻璃、苹方 16、卷轴模式和动效：照微信输入法玻璃主题调好的一组设置。")
        }
      }
      .formStyle(.grouped)
    }
  }

  private var squirrel: ConfigFile { store.squirrel }

  @ViewBuilder
  private var lookSection: some View {
    Section("风格") {
      Picker("风格", selection: Binding(get: { store.look }, set: { store.setLook($0) })) {
        ForEach(PanelLook.allCases) { Text($0.title).tag($0) }
      }
      switch store.look {
      case .liquidGlass:
        Picker("玻璃质感", selection: store.binding(squirrel, "style/glass_style", default: "regular")) {
          Text("磨砂").tag("regular")
          Text("通透").tag("clear")
        }
        .pickerStyle(.segmented)
      case .preset:
        ChoicePicker(title: "浅色模式配色", selection: store.binding(squirrel, "style/color_scheme", default: "native"), choices: store.colorSchemes)
        ChoicePicker(title: "深色模式配色",
                     selection: Binding(get: { store.string(squirrel, "style/color_scheme_dark") ?? "" },
                                        set: { store.set(squirrel, "style/color_scheme_dark", $0.isEmpty ? nil : .scalar($0)) }),
                     choices: [Choice(value: "", title: "与浅色相同")] + store.colorSchemes)
      case .native:
        EmptyView()
      }
    }
  }

  private var isLinear: Bool { store.string(squirrel, "style/candidate_list_layout") == "linear" }
  private var isHorizontal: Bool { store.string(squirrel, "style/text_orientation") != "vertical" }
  private var scrollModeOn: Bool { store.bool(squirrel, "style/scroll_mode/enable") == true }

  @ViewBuilder
  private var layoutSection: some View {
    Section {
      Picker("候选排列", selection: store.binding(squirrel, "style/candidate_list_layout", default: "stacked")) {
        Text("一行").tag("linear")
        Text("一列").tag("stacked")
      }
      .pickerStyle(.segmented)
      Picker("文字方向", selection: store.binding(squirrel, "style/text_orientation", default: "horizontal")) {
        Text("横排").tag("horizontal")
        Text("竖排").tag("vertical")
      }
      .pickerStyle(.segmented)
      Toggle("卷轴模式", isOn: store.binding(squirrel, "style/scroll_mode/enable", default: false))
        .disabled(!(isLinear && isHorizontal))
      if scrollModeOn && isLinear && isHorizontal {
        StepperRow(title: "展开后最多显示", value: store.binding(squirrel, "style/scroll_mode/max_rows", default: 5).asDouble, range: 2...20, unit: "行")
        Toggle("Tab / Shift-Tab 翻页", isOn: store.binding(squirrel, "style/scroll_mode/tab_paging", default: true))
        SliderRow(title: "展开后的最小列宽", value: store.binding(squirrel, "style/scroll_mode/column_width", default: 0.0), range: 0...160, step: 2)
      }
      Toggle("编码显示在正在输入的文字里", isOn: store.binding(squirrel, "style/inline_preedit", default: true))
      Toggle("显示翻页箭头", isOn: store.binding(squirrel, "style/show_paging", default: false))
      Toggle("展开、收起动效", isOn: store.binding(squirrel, "style/motion", default: false))
    } header: {
      Text("布局")
    } footer: {
      Note(isLinear && isHorizontal
           ? "卷轴模式：Tab、↓ 或 = 把单行候选展开成多行，每行一页，可以上下滚动；在第一行按 Shift-Tab 或 ↑ 收起。系统开了「减弱动态效果」时不播放动效。"
           : "卷轴模式需要「一行」「横排」。")
    }
  }

  @ViewBuilder
  private var fontSection: some View {
    Section("字体") {
      Picker("字体", selection: Binding(get: { store.fontFamily }, set: { store.setFontFamily($0) })) {
        if !SettingsStore.fontFamilies.contains(where: { $0.value == store.fontFamily }) {
          Text(store.fontFamily).tag(store.fontFamily)
        }
        ForEach(SettingsStore.fontFamilies) { Text($0.title).tag($0.value) }
      }
      Picker("选中的候选", selection: Binding(get: { store.highlightWeight }, set: { store.setHighlightWeight($0) })) {
        ForEach(SettingsStore.highlightWeights) { Text($0.title).tag($0.value) }
      }
      let fontSize = store.double(squirrel, "style/font_point") ?? 16
      StepperRow(title: "候选字号", value: store.binding(squirrel, "style/font_point", default: 16.0), range: 10...40, unit: "pt")
      StepperRow(title: "序号字号", value: store.binding(squirrel, "style/label_font_point", default: fontSize), range: 8...40, unit: "pt")
      StepperRow(title: "注释字号", value: store.binding(squirrel, "style/comment_font_point", default: fontSize), range: 8...40, unit: "pt")
      ChoicePicker(title: "候选格式", selection: store.binding(squirrel, "style/candidate_format", default: "[label]. [candidate] [comment]"),
                   choices: SettingsStore.candidateFormats)
    }
  }

  @ViewBuilder
  private var sizeSection: some View {
    Section {
      SliderRow(title: "圆角", value: store.binding(squirrel, "style/corner_radius", default: 7.0), range: 0...30)
      SliderRow(title: "左右留白", value: store.binding(squirrel, "style/border_width", default: 0.0), range: 0...24, step: 0.5)
      SliderRow(title: "上下留白", value: store.binding(squirrel, "style/border_height", default: 0.0), range: 0...16, step: 0.2)
      SliderRow(title: "候选间距", value: store.binding(squirrel, "style/candidate_spacing", default: 8.0), range: 0...40)
      SliderRow(title: "行距", value: store.binding(squirrel, "style/line_spacing", default: 5.0), range: 0...24, step: 0.2)
      SliderRow(title: "文字上下微调", value: store.binding(squirrel, "style/base_offset", default: 0.0), range: -6...6, step: 0.5)
    } header: {
      Text("尺寸与间距")
    } footer: {
      Note(store.look == .liquidGlass ? "液态玻璃下，单行时总是胶囊形，圆角只用于展开后的多行；文字上下微调是负数时往下移。" : "文字上下微调是负数时往下移。")
    }
  }

  @ViewBuilder
  private var otherSection: some View {
    Section("其他") {
      Toggle("菜单栏显示中 / 英状态图标", isOn: store.binding(squirrel, "status_icon/show", default: true))
      Picker("部署通知", selection: store.binding(squirrel, "show_notifications_when", default: "appropriate")) {
        Text("需要时").tag("appropriate")
        Text("总是").tag("always")
        Text("从不").tag("never")
      }
    }
  }
}
