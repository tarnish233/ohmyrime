//
//  PhraseBook.swift
//  鼠须管设置
//
//  custom_phrase.txt: 「短语<Tab>编码<Tab>权重」 lines under a comment header. Edited in place, so
//  the header, blank lines and the order of the other phrases stay.
//

import Foundation

struct Phrase: Identifiable, Hashable {
  let id: UUID
  var text: String
  var code: String
  /// Empty when not given.
  var weight: String

  init(id: UUID = UUID(), text: String, code: String, weight: String = "") {
    self.id = id
    self.text = text
    self.code = code
    self.weight = weight
  }

  var line: String {
    [text, code, weight].prefix(weight.isEmpty ? 2 : 3).joined(separator: "\t")
  }

  /// What would keep Rime from reading it.
  var problem: String? {
    if text.isEmpty || code.isEmpty {
      return "短语和编码都不能为空"
    }
    if text.contains("\t") || code.contains("\t") || code.contains(" ") {
      return "编码里不能有空格或 Tab"
    }
    if !weight.isEmpty && Int(weight) == nil {
      return "权重要是整数"
    }
    return nil
  }
}

final class PhraseBook {
  let url: URL
  private enum Line: Hashable {
    case other(String)
    case phrase(Phrase)
  }
  private var lines = [Line]()
  private var savedText = ""
  private var loadedDate: Date?

  init(url: URL) {
    self.url = url
    reload()
  }

  var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

  func reload() {
    lines = Self.parse((try? String(contentsOf: url, encoding: .utf8)) ?? "")
    savedText = text
    loadedDate = modificationDate
  }

  private static func parse(_ text: String) -> [Line] {
    var rows = text.components(separatedBy: "\n")
    if rows.last == "" {
      rows.removeLast()
    }
    return rows.map { row in
      let fields = row.components(separatedBy: "\t")
      guard !row.hasPrefix("#"), fields.count >= 2, !fields[0].isEmpty else { return .other(row) }
      return .phrase(Phrase(text: fields[0], code: fields[1], weight: fields.count > 2 ? fields[2] : ""))
    }
  }

  private var modificationDate: Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
  }

  var changedOnDisk: Bool { modificationDate != loadedDate }

  var phrases: [Phrase] {
    lines.compactMap { if case .phrase(let phrase) = $0 { phrase } else { nil } }
  }

  var text: String {
    let rows = lines.map { line -> String in
      switch line {
      case .other(let text): text
      case .phrase(let phrase): phrase.line
      }
    }
    return rows.isEmpty ? "" : rows.joined(separator: "\n") + "\n"
  }

  var isDirty: Bool { text != savedText }

  func update(_ phrase: Phrase) {
    guard let index = lines.firstIndex(where: { if case .phrase(let old) = $0 { old.id == phrase.id } else { false } }) else { return }
    lines[index] = .phrase(phrase)
  }

  func add(_ phrase: Phrase) {
    if lines.isEmpty {
      lines = Self.parse(Self.header)
    }
    lines.append(.phrase(phrase))
  }

  func remove(_ ids: Set<UUID>) {
    lines.removeAll { if case .phrase(let phrase) = $0 { ids.contains(phrase.id) } else { false } }
  }

  @discardableResult
  func save(backupStamp: String) throws -> Bool {
    // Half-typed rows wait until they are complete.
    guard isDirty, phrases.allSatisfy({ $0.problem == nil }) else { return false }
    ConfigFile.backUp(url, stamp: backupStamp)
    let text = self.text
    try text.write(to: url, atomically: true, encoding: .utf8)
    savedText = text
    loadedDate = modificationDate
    return true
  }

  static let header = """
    # Rime table
    # coding: utf-8
    #@/db_name\tcustom_phrase.txt
    #@/db_type\ttabledb
    #
    # 自定义短语：短语<Tab>编码<Tab>权重（权重可省略）
    # 此行之后不能写注释

    """
}
