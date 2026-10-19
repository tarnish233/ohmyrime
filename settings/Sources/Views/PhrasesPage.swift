//
//  PhrasesPage.swift
//  鼠须管设置
//
//  custom_phrase.txt: phrases pinned to the top for a code, such as an e-mail address.
//

import SwiftUI

extension SettingsStore {
  var phraseList: [Phrase] {
    _ = revision
    return phrases.phrases
  }

  func updatePhrase(_ phrase: Phrase) {
    phrases.update(phrase)
    changed()
  }

  func addPhrase(_ phrase: Phrase) {
    phrases.add(phrase)
    changed()
  }

  func removePhrases(_ ids: Set<UUID>) {
    phrases.remove(ids)
    changed()
  }
}

struct PhrasesPage: View {
  @Environment(SettingsStore.self) private var store
  @State private var selection = Set<UUID>()
  @State private var search = ""

  var body: some View {
    let all = store.phraseList
    let shown = search.isEmpty ? all : all.filter { $0.text.localizedCaseInsensitiveContains(search) || $0.code.localizedCaseInsensitiveContains(search) }
    let incomplete = all.filter { $0.problem != nil }.count
    VStack(alignment: .leading, spacing: 0) {
      Note("输入编码时，这里的短语排在候选的最前面，适合邮箱、手机号、常用的句子。编码最好不用完整的拼音：用了完整拼音的词不能再参与造词。")
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
      Table(shown, selection: $selection) {
        TableColumn("短语") { phrase in
          CommitField(value: phrase.text, prompt: "短语") { update(phrase, text: $0) }
        }
        TableColumn("编码") { phrase in
          CommitField(value: phrase.code, prompt: "编码", monospaced: true) { update(phrase, code: $0) }
        }
        .width(min: 80, ideal: 130)
        TableColumn("权重") { phrase in
          CommitField(value: phrase.weight, prompt: "可省略", monospaced: true) { update(phrase, weight: $0) }
        }
        .width(70)
      }
      .tableStyle(.inset(alternatesRowBackgrounds: true))
      // Otherwise the table asks for all its rows' height, more than the window has.
      .frame(minHeight: 160, maxHeight: .infinity)
      Divider()
      HStack(spacing: 0) {
        Button {
          let phrase = Phrase(text: "", code: "")
          store.addPhrase(phrase)
          search = ""
          selection = [phrase.id]
        } label: {
          Image(systemName: "plus").frame(width: 24, height: 20)
        }
        .help("添加短语")
        Divider().frame(height: 16)
        Button {
          store.removePhrases(selection)
          selection = []
        } label: {
          Image(systemName: "minus").frame(width: 24, height: 20)
        }
        .disabled(selection.isEmpty)
        .help("删除选中的短语")
        Spacer()
        Group {
          if incomplete > 0 {
            Label("\(incomplete) 条还没填完，填好短语和编码后才会保存", systemImage: "exclamationmark.circle")
              .foregroundStyle(.orange)
          } else {
            Text("\(all.count) 条")
              .foregroundStyle(.secondary)
          }
        }
        .font(.callout)
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
    }
    .searchable(text: $search, placement: .toolbar, prompt: "搜索短语或编码")
  }

  private func update(_ phrase: Phrase, text: String? = nil, code: String? = nil, weight: String? = nil) {
    var changed = phrase
    changed.text = text ?? phrase.text
    changed.code = (code ?? phrase.code).trimmingCharacters(in: .whitespaces)
    changed.weight = (weight ?? phrase.weight).trimmingCharacters(in: .whitespaces)
    if changed != phrase {
      store.updatePhrase(changed)
    }
  }
}

/// A table cell that commits on Return or when it loses focus, not on every key.
struct CommitField: View {
  let value: String
  var prompt = ""
  var monospaced = false
  let commit: (String) -> Void
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    TextField(prompt, text: $text)
      .textFieldStyle(.plain)
      .font(monospaced ? .body.monospaced() : .body)
      .focused($focused)
      .onAppear { text = value }
      .onChange(of: value) { _, newValue in
        if !focused {
          text = newValue
        }
      }
      .onChange(of: focused) { _, isFocused in
        if !isFocused && text != value {
          commit(text)
        }
      }
      .onSubmit {
        if text != value {
          commit(text)
        }
      }
  }
}
