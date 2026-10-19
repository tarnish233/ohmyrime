//
//  Controls.swift
//  鼠须管设置
//
//  Form rows shared by the pages.
//

import SwiftUI

/// A slider with its value beside it.
struct SliderRow: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  var step: Double = 1
  var unit = "pt"

  var body: some View {
    LabeledContent(title) {
      HStack(spacing: 10) {
        Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: { value = ($0 / step).rounded() * step }),
               in: range)
          .frame(minWidth: 150, maxWidth: 240)
        Text(YAMLNode.format(value) + (unit.isEmpty ? "" : " " + unit))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(width: 58, alignment: .trailing)
      }
    }
  }
}

/// A stepper with its value beside it.
struct StepperRow: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  var step: Double = 1
  var unit = ""

  var body: some View {
    LabeledContent(title) {
      Stepper(value: $value, in: range, step: step) {
        Text(YAMLNode.format(value) + (unit.isEmpty ? "" : " " + unit))
          .monospacedDigit()
      }
    }
  }
}

extension Binding where Value == Int {
  /// For StepperRow.
  var asDouble: Binding<Double> {
    Binding<Double>(get: { Double(wrappedValue) }, set: { wrappedValue = Int($0.rounded()) })
  }
}

/// A menu of choices, showing the current value even when it is not one of them.
struct ChoicePicker: View {
  let title: String
  @Binding var selection: String
  let choices: [Choice]

  var body: some View {
    Picker(title, selection: $selection) {
      if !choices.contains(where: { $0.value == selection }) {
        Text(selection.isEmpty ? "（未设置）" : selection).tag(selection)
        Divider()
      }
      ForEach(choices) { choice in
        Text(choice.title).tag(choice.value)
      }
    }
  }
}

/// Smaller explanatory text below a row.
struct Note: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    // No fixedSize: measured without a width (the window's minimum size), it would wrap at every
    // character and ask for a window taller than the screen.
    Text(text)
      .font(.callout)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
