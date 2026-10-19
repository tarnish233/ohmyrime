//
//  YAML.swift
//  鼠须管设置
//
//  YAML values as Rime reads them, parsed by librime itself (yaml-cpp) and written back as
//  text for *.custom.yaml patches.
//

import Foundation

struct YAMLEntry: Hashable {
  var key: String
  var value: YAMLNode
}

/// A YAML value as Rime sees it: every scalar is a string, and maps keep Rime's sorted key order.
indirect enum YAMLNode: Hashable {
  case null
  case scalar(String)
  case list([YAMLNode])
  case map([YAMLEntry])

  static func bool(_ value: Bool) -> YAMLNode { .scalar(value ? "true" : "false") }
  static func int(_ value: Int) -> YAMLNode { .scalar(String(value)) }
  static func number(_ value: Double) -> YAMLNode { .scalar(format(value)) }
  static func strings(_ values: [String]) -> YAMLNode { .list(values.map { .scalar($0) }) }

  /// Up to three decimals, without trailing zeros: 9.5, 4.8, 16.
  static func format(_ value: Double) -> String {
    let rounded = (value * 1000).rounded() / 1000
    if rounded == rounded.rounded() && abs(rounded) < 1e9 {
      return String(Int(rounded))
    }
    var text = String(format: "%.3f", rounded)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
  }

  var scalar: String? {
    if case .scalar(let text) = self { text } else { nil }
  }
  /// Like librime's ConfigValue::GetBool: only true and false, in any case.
  var boolValue: Bool? {
    switch scalar?.lowercased() {
    case "true": true
    case "false": false
    default: nil
    }
  }
  var doubleValue: Double? { scalar.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } }
  var intValue: Int? {
    guard let text = scalar?.trimmingCharacters(in: .whitespaces) else { return nil }
    return Int(text) ?? Double(text).map { Int($0) }
  }
  var listValue: [YAMLNode]? {
    if case .list(let items) = self { items } else { nil }
  }
  var mapValue: [YAMLEntry]? {
    if case .map(let entries) = self { entries } else { nil }
  }
  subscript(key: String) -> YAMLNode? {
    mapValue?.first { $0.key == key }?.value
  }
}

// MARK: - Paths

extension YAMLNode {
  /// Rime's path syntax: keys separated by "/", and "@N", "@last" or "@next" for list items.
  static func components(_ path: String) -> [String] {
    path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
  }

  static func listIndex(_ component: String, count: Int) -> Int? {
    guard component.hasPrefix("@") else { return nil }
    switch component.dropFirst() {
    case "last": return count - 1
    case "next": return count
    case let number: return Int(number)
    }
  }

  func value(at path: String) -> YAMLNode? {
    var node = self
    for component in Self.components(path) {
      switch node {
      case .map(let entries):
        guard let next = entries.first(where: { $0.key == component })?.value else { return nil }
        node = next
      case .list(let items):
        guard let index = Self.listIndex(component, count: items.count), items.indices.contains(index) else { return nil }
        node = items[index]
      default:
        return nil
      }
    }
    return node
  }

  /// The node with `value` set at `path`, creating maps on the way, as a Rime patch does.
  /// A last component "+" appends to a list or merges into a map (Rime's `key/+:`).
  func setting(_ value: YAMLNode, at path: String) -> YAMLNode {
    setting(value, at: Self.components(path)[...])
  }

  private func setting(_ value: YAMLNode, at path: ArraySlice<String>) -> YAMLNode {
    guard let first = path.first else { return value }
    let rest = path.dropFirst()
    if first == "+" && rest.isEmpty {
      switch (self, value) {
      case (.list(let items), .list(let more)):
        return .list(items + more)
      case (.map, .map(let more)):
        return more.reduce(self) { $0.setting($1.value, at: [$1.key][...]) }
      default:
        return value
      }
    }
    switch self {
    case .list(var items):
      guard let index = Self.listIndex(first, count: items.count) else {
        return YAMLNode.map([]).setting(value, at: path)
      }
      if index == items.count {
        items.append(YAMLNode.null.setting(value, at: rest))
      } else if items.indices.contains(index) {
        items[index] = items[index].setting(value, at: rest)
      }
      return .list(items)
    case .map(var entries):
      if let index = entries.firstIndex(where: { $0.key == first }) {
        entries[index].value = entries[index].value.setting(value, at: rest)
      } else {
        entries.append(YAMLEntry(key: first, value: YAMLNode.null.setting(value, at: rest)))
        // librime keeps maps in a std::map.
        entries.sort { Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8)) }
      }
      return .map(entries)
    case .null, .scalar:
      if Self.listIndex(first, count: 0) != nil {
        return YAMLNode.list([]).setting(value, at: path)
      }
      return YAMLNode.map([]).setting(value, at: path)
    }
  }
}

// MARK: - Writing

extension YAMLNode {
  /// Plain when YAML reads it back as the same string, quoted otherwise.
  static func quoted(_ text: String) -> String {
    if text.isEmpty {
      return "''"
    }
    if text.contains(where: { $0.isNewline || $0 == "\t" }) {
      let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
      return "\"\(escaped)\""
    }
    if isPlain(text) {
      return text
    }
    return "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
  }

  /// Conservative: also safe inside flow collections, where , [ ] { } are special everywhere.
  private static func isPlain(_ text: String) -> Bool {
    if ["~", "null"].contains(text.lowercased()) {
      return false
    }
    let inner = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-./+()^$=<>?%"))
    guard text.unicodeScalars.allSatisfy({ inner.contains($0) }), let first = text.unicodeScalars.first else { return false }
    return !CharacterSet(charactersIn: "-?%<>=").contains(first)
  }

  /// Inline text: scalars, and collections in [ ] or { }.
  var flowText: String {
    switch self {
    case .null:
      "~"
    case .scalar(let text):
      Self.quoted(text)
    case .list(let items):
      items.isEmpty ? "[]" : "[" + items.map(\.flowText).joined(separator: ", ") + "]"
    case .map(let entries):
      entries.isEmpty ? "{}" : "{ " + entries.map { Self.quoted($0.key) + ": " + $0.value.flowText }.joined(separator: ", ") + " }"
    }
  }

  /// Whether the value goes on its key's line.
  var isInline: Bool {
    switch self {
    case .null, .scalar: true
    case .list(let items): items.isEmpty
    case .map(let entries): entries.isEmpty
    }
  }

  /// Lines of a block value, indented by `indent`: one item per line, maps of scalars in { }.
  func blockLines(indent: Int) -> [String] {
    let pad = String(repeating: " ", count: indent)
    switch self {
    case .list(let items):
      return items.flatMap { item -> [String] in
        switch item {
        case .null, .scalar:
          return [pad + "- " + item.flowText]
        case .map(let entries) where entries.count == 1 && entries[0].value.isInline:
          return [pad + "- " + Self.quoted(entries[0].key) + ": " + entries[0].value.flowText]
        case .map(let entries) where entries.allSatisfy({ $0.value.isInline }) && item.flowText.count <= 100:
          return [pad + "- " + item.flowText]
        case .list(let items) where items.allSatisfy(\.isInline):
          return [pad + "- " + item.flowText]
        default:
          // The item's own block, its first line on the dash.
          let inner = item.blockLines(indent: indent + 2)
          guard let head = inner.first else { return [pad + "- " + item.flowText] }
          return [pad + "- " + head.dropFirst(indent + 2)] + inner.dropFirst()
        }
      }
    case .map(let entries):
      return entries.flatMap { entry -> [String] in
        let key = pad + Self.quoted(entry.key) + ":"
        if entry.value.isInline {
          return [key + " " + entry.value.flowText]
        }
        return [key] + entry.value.blockLines(indent: indent + 2)
      }
    case .null, .scalar:
      return [pad + flowText]
    }
  }

  /// A whole YAML document.
  var documentText: String {
    switch self {
    case .map(let entries) where !entries.isEmpty:
      blockLines(indent: 0).joined(separator: "\n") + "\n"
    default:
      flowText + "\n"
    }
  }
}

// MARK: - Reading with librime

enum RimeYAML {
  private static var api: RimeApi_stdbool { rime_get_api_stdbool().pointee }

  /// Parses YAML text as Rime does. Nil when it is not valid YAML.
  /// Keys containing "/" cannot be read back this way (librime paths); patch files are read
  /// entry by entry instead (see PatchDocument).
  static func parse(_ text: String) -> YAMLNode? {
    var config = RimeConfig()
    defer { _ = api.config_close(&config) }
    guard api.config_load_string(&config, text) else { return nil }
    return read(&config, path: "")
  }

  /// Whether librime reads the text as YAML.
  static func isValid(_ text: String) -> Bool {
    var config = RimeConfig()
    defer { _ = api.config_close(&config) }
    return api.config_load_string(&config, text)
  }

  private static func read(_ config: inout RimeConfig, path: String) -> YAMLNode {
    var iterator = RimeConfigIterator()
    if api.config_begin_map(&iterator, &config, path) {
      var children = [(String, String)]()
      while api.config_next(&iterator) {
        children.append((String(cString: iterator.key), String(cString: iterator.path)))
      }
      api.config_end(&iterator)
      return .map(children.map { YAMLEntry(key: $0.0, value: read(&config, path: $0.1)) })
    }
    if api.config_begin_list(&iterator, &config, path) {
      var paths = [String]()
      while api.config_next(&iterator) {
        paths.append(String(cString: iterator.path))
      }
      api.config_end(&iterator)
      return .list(paths.map { read(&config, path: $0) })
    }
    if let value = api.config_get_cstring(&config, path) {
      return .scalar(String(cString: value))
    }
    return .null
  }
}
