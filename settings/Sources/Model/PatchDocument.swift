//
//  PatchDocument.swift
//  鼠须管设置
//
//  Edits the `patch:` map of a Rime *.custom.yaml file line by line, so that comments, blank
//  lines and entries it does not touch stay exactly as they are.
//

import Foundation

struct PatchDocument: Equatable {
  enum Failure: Error, CustomStringConvertible {
    /// `patch: { ... }` written inline.
    case inlinePatch(line: Int)

    var description: String {
      switch self {
      case .inlinePatch(let line): "第 \(line) 行的 patch 写在了一行里（patch: { … }），无法逐项修改"
      }
    }
  }

  private(set) var lines: [String]
  /// Edit top-level keys instead of the patch map (installation.yaml).
  let topLevel: Bool

  init(text: String, topLevel: Bool = false) {
    var lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    if lines.last == "" {
      lines.removeLast()
    }
    self.lines = lines
    self.topLevel = topLevel
  }

  var text: String {
    lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
  }

  struct Entry: Equatable {
    let key: String
    /// The key as written, quotes included.
    let keyText: String
    /// The key line and the value's lines below it.
    let range: Range<Int>
    /// What follows the colon on the key line, without the comment.
    let inlineValue: String
    let comment: String?
  }

  // MARK: Reading

  func entries() throws -> [Entry] {
    guard let block = try block() else { return [] }
    var entries = [Entry]()
    var index = block.range.lowerBound
    while index < block.range.upperBound {
      let line = lines[index]
      guard Self.contentIndent(line) == block.indent,
            let (keyText, key, rest) = Self.splitKey(String(line.dropFirst(block.indent))) else {
        index += 1
        continue
      }
      // The value's lines are indented deeper; blank lines count only when more follow.
      var end = index + 1
      var scan = index + 1
      while scan < block.range.upperBound {
        let indent = Self.indent(lines[scan])
        if lines[scan].allSatisfy({ $0 == " " || $0 == "\t" }) {
          scan += 1
          continue
        }
        guard indent > block.indent else { break }
        end = scan + 1
        scan += 1
      }
      let (value, comment) = Self.splitComment(rest)
      entries.append(Entry(key: key, keyText: keyText, range: index..<end, inlineValue: value, comment: comment))
      index = end
    }
    return entries
  }

  func entry(_ key: String) -> Entry? {
    (try? entries())?.first { $0.key == key }
  }

  /// The entry's value, read by librime.
  func value(of entry: Entry) -> YAMLNode? {
    var text = "value:" + (entry.inlineValue.isEmpty ? "" : " " + entry.inlineValue) + "\n"
    for line in lines[entry.range.dropFirst()] {
      text += line + "\n"
    }
    return RimeYAML.parse(text)?["value"]
  }

  func value(_ key: String) -> YAMLNode? {
    entry(key).flatMap(value(of:))
  }

  /// Every entry's value, in file order.
  func values() -> [(key: String, value: YAMLNode)] {
    ((try? entries()) ?? []).compactMap { entry in value(of: entry).map { (entry.key, $0) } }
  }

  // MARK: Writing

  mutating func set(_ key: String, _ value: YAMLNode) throws {
    try prepareBlock()
    guard let block = try block() else { return }
    if let entry = try entries().first(where: { $0.key == key }) {
      lines.replaceSubrange(entry.range, with: Self.render(keyText: entry.keyText, value: value, indent: block.indent, comment: entry.comment))
    } else {
      let rendered = Self.render(keyText: YAMLNode.quoted(key), value: value, indent: block.indent, comment: nil)
      // After the block's last line that is not blank.
      var insertion = block.range.lowerBound
      for index in block.range where !lines[index].allSatisfy({ $0 == " " || $0 == "\t" }) {
        insertion = index + 1
      }
      lines.insert(contentsOf: rendered, at: insertion)
    }
  }

  mutating func remove(_ key: String) throws {
    try removeAll { $0 == key }
  }

  /// Removes the entries whose keys match, such as all of one app's options.
  mutating func removeAll(where matches: (String) -> Bool) throws {
    for entry in try entries().reversed() where matches(entry.key) {
      lines.removeSubrange(entry.range)
    }
  }

  // MARK: - Lines

  private struct Block {
    let range: Range<Int>
    let indent: Int
  }

  private static let patchHeader = /^patch:\s*(#.*)?$/
  private static let emptyInlinePatch = /^patch:\s*\{\s*\}\s*(#.*)?$/

  private func block() throws -> Block? {
    if topLevel {
      return Block(range: 0..<lines.count, indent: 0)
    }
    guard let header = lines.firstIndex(where: { $0.hasPrefix("patch:") }) else { return nil }
    guard lines[header].wholeMatch(of: Self.patchHeader) != nil else {
      if lines[header].wholeMatch(of: Self.emptyInlinePatch) != nil {
        return Block(range: header + 1..<header + 1, indent: 2)
      }
      throw Failure.inlinePatch(line: header + 1)
    }
    // Up to the next top-level key; comments may start in the first column.
    var end = header + 1
    while end < lines.count {
      if let first = lines[end].first, first != " ", first != "\t", first != "#" {
        break
      }
      end += 1
    }
    let indent = (header + 1..<end).lazy.compactMap { Self.contentIndent(self.lines[$0]) }.first ?? 2
    return Block(range: header + 1..<end, indent: indent)
  }

  /// Makes sure there is a `patch:` line to add entries under.
  private mutating func prepareBlock() throws {
    if topLevel {
      return
    }
    if let header = lines.firstIndex(where: { $0.hasPrefix("patch:") }) {
      if let match = lines[header].wholeMatch(of: Self.emptyInlinePatch) {
        lines[header] = "patch:" + (match.output.1.map { "  " + $0 } ?? "")
      }
      _ = try block()
      return
    }
    if let last = lines.last, !last.isEmpty {
      lines.append("")
    }
    lines.append("patch:")
  }

  static func indent(_ line: String) -> Int {
    line.prefix { $0 == " " }.count
  }

  /// Indentation of a line with content; nil for blank and comment lines.
  static func contentIndent(_ line: String) -> Int? {
    let trimmed = line.drop { $0 == " " || $0 == "\t" }
    guard let first = trimmed.first, first != "#" else { return nil }
    return indent(line)
  }

  /// "key: rest" into the key as written, the key, and what follows the colon.
  static func splitKey(_ content: String) -> (String, String, String)? {
    let characters = Array(content)
    guard let first = characters.first, first != "-", first != "#", first != "[", first != "{" else { return nil }
    var key = ""
    var index = 0
    if first == "\"" || first == "'" {
      index = 1
      while index < characters.count {
        let character = characters[index]
        if first == "\"" && character == "\\" && index + 1 < characters.count {
          let next = characters[index + 1]
          key.append(next == "n" ? "\n" : next == "t" ? "\t" : next)
          index += 2
          continue
        }
        if character == first {
          if first == "'" && index + 1 < characters.count && characters[index + 1] == "'" {
            key.append("'")
            index += 2
            continue
          }
          break
        }
        key.append(character)
        index += 1
      }
      guard index < characters.count else { return nil }
      index += 1
      while index < characters.count && characters[index] == " " {
        index += 1
      }
      guard index < characters.count && characters[index] == ":" else { return nil }
    } else {
      while index < characters.count {
        if characters[index] == ":" && (index + 1 == characters.count || characters[index + 1] == " " || characters[index + 1] == "\t") {
          break
        }
        if characters[index] == " " && index + 1 < characters.count && characters[index + 1] == "#" {
          return nil
        }
        index += 1
      }
      guard index < characters.count else { return nil }
      key = String(characters[0..<index]).trimmingCharacters(in: .whitespaces)
    }
    let keyText = String(characters[0..<index]).trimmingCharacters(in: .whitespaces)
    return (keyText, key, String(characters[(index + 1)...]))
  }

  /// The value and a trailing comment: a # after whitespace, outside quotes.
  static func splitComment(_ rest: String) -> (String, String?) {
    var quote: Character?
    var previous: Character = " "
    for (offset, character) in rest.enumerated() {
      if let open = quote {
        if character == open {
          quote = nil
        }
      } else if character == "\"" || character == "'" {
        quote = character
      } else if character == "#" && (previous == " " || previous == "\t") {
        let index = rest.index(rest.startIndex, offsetBy: offset)
        let comment = rest[rest.index(after: index)...].trimmingCharacters(in: .whitespaces)
        return (rest[..<index].trimmingCharacters(in: .whitespaces), comment)
      }
      previous = character
    }
    return (rest.trimmingCharacters(in: .whitespaces), nil)
  }

  static func render(keyText: String, value: YAMLNode, indent: Int, comment: String?) -> [String] {
    let pad = String(repeating: " ", count: indent)
    let suffix = comment.map { "  # " + $0 } ?? ""
    if value.isInline {
      return [pad + keyText + ": " + value.flowText + suffix]
    }
    return [pad + keyText + ":" + suffix] + value.blockLines(indent: indent + 2)
  }
}
