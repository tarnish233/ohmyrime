//
//  Settings.swift
//  鼠须管设置
//
//  The settings of each page, on top of the raw config values.
//

import AppKit

// MARK: - Appearance

enum PanelLook: String, CaseIterable, Identifiable {
  /// Native colors over the system's Liquid Glass material.
  case liquidGlass
  /// Native colors, opaque.
  case native
  /// One of Squirrel's preset color schemes.
  case preset

  var id: String { rawValue }
  var title: String {
    switch self {
    case .liquidGlass: "液态玻璃"
    case .native: "系统配色（不透明）"
    case .preset: "预设配色"
    }
  }
}

struct Choice: Hashable, Identifiable {
  let value: String
  let title: String
  var id: String { value }
}

extension SettingsStore {
  /// nil: back to Squirrel's default.
  static let recommendedLook: [(String, YAMLNode?)] = [
    ("style/candidate_list_layout", .scalar("linear")),
    ("style/text_orientation", .scalar("horizontal")),
    ("style/scroll_mode/enable", .bool(true)),
    ("style/scroll_mode/max_rows", .int(5)),
    ("style/scroll_mode/tab_paging", .bool(true)),
    ("style/scroll_mode/column_width", .int(66)),
    ("style/color_scheme", .scalar("native")),
    ("style/color_scheme_dark", nil),
    ("style/translucency", .bool(true)),
    ("style/glass_style", .scalar("regular")),
    ("style/corner_radius", .int(18)),
    ("style/hilited_corner_radius", .int(0)),
    ("style/border_width", .number(9.5)),
    ("style/border_height", .number(4.8)),
    ("style/candidate_spacing", .int(13)),
    ("style/line_spacing", .number(9.6)),
    ("style/font_face", .scalar("PingFang SC")),
    ("style/hilited_font_face", .scalar("PingFangSC-Medium")),
    ("style/font_point", .int(16)),
    ("style/label_font_point", .int(16)),
    ("style/comment_font_point", .int(13)),
    ("style/candidate_format", .scalar("[label][candidate] [comment]")),
    ("style/base_offset", .number(-1.5)),
    ("style/motion", .bool(true)),
  ]

  /// The ohmyrime look: Liquid Glass after WeType, scroll mode.
  func applyRecommendedLook() {
    for (path, value) in Self.recommendedLook {
      squirrel.set(path, value)
    }
    changed()
  }

  var look: PanelLook {
    if (string(squirrel, "style/color_scheme") ?? "native") != "native" {
      return .preset
    }
    return bool(squirrel, "style/translucency") == true ? .liquidGlass : .native
  }

  func setLook(_ look: PanelLook) {
    switch look {
    case .liquidGlass, .native:
      squirrel.set("style/color_scheme", .scalar("native"))
      squirrel.set("style/color_scheme_dark", nil)
      squirrel.set("style/translucency", .bool(look == .liquidGlass))
    case .preset:
      if self.look != .preset {
        squirrel.set("style/color_scheme", .scalar(colorSchemes.first { $0.value != "native" }?.value ?? "aqua"))
        squirrel.set("style/translucency", .bool(false))
      }
    }
    changed()
  }

  /// Squirrel's preset color schemes, by name.
  var colorSchemes: [Choice] {
    (value(squirrel, "preset_color_schemes")?.mapValue ?? []).map {
      Choice(value: $0.key, title: $0.value["name"]?.scalar ?? $0.key)
    }
  }

  /// Font families: the system font first, then the installed ones by their localized names.
  static let fontFamilies: [Choice] = {
    let manager = NSFontManager.shared
    let families = manager.availableFontFamilies.filter { !$0.hasPrefix(".") }.map { family in
      Choice(value: family, title: manager.localizedName(forFamily: family, face: nil))
    }
    return [Choice(value: "system", title: "系统字体（SF + 苹方）")] + families.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }()

  /// Weights for the highlighted candidate, as font names of a family.
  static let highlightWeights: [Choice] = [
    Choice(value: "", title: "与候选相同"),
    Choice(value: "medium", title: "中等"),
    Choice(value: "semibold", title: "中粗"),
    Choice(value: "bold", title: "粗体"),
  ]

  /// The family of the first font in font_face.
  var fontFamily: String {
    let face = (string(squirrel, "style/font_face") ?? "Avenir").split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "Avenir"
    if face.hasPrefix("system") {
      return "system"
    }
    return NSFont(name: face, size: 12)?.familyName ?? face
  }

  func setFontFamily(_ family: String) {
    let weight = highlightWeight
    squirrel.set("style/font_face", .scalar(family))
    squirrel.set("style/hilited_font_face", Self.fontName(family: family, weight: weight).map { .scalar($0) })
    changed()
  }

  var highlightWeight: String {
    guard let face = string(squirrel, "style/hilited_font_face") else { return "" }
    if face.hasPrefix("system-") {
      return String(face.dropFirst("system-".count))
    }
    guard let font = NSFont(name: face, size: 12) else { return "" }
    let weight = NSFontManager.shared.weight(of: font)
    return weight >= 9 ? "bold" : weight >= 7 ? "semibold" : weight >= 6 ? "medium" : ""
  }

  func setHighlightWeight(_ weight: String) {
    squirrel.set("style/hilited_font_face", Self.fontName(family: fontFamily, weight: weight).map { .scalar($0) })
    changed()
  }

  /// A family member of a weight, by its font name: PingFangSC-Medium, system-medium.
  static func fontName(family: String, weight: String) -> String? {
    guard !weight.isEmpty else { return nil }
    if family == "system" {
      return "system-\(weight)"
    }
    let wanted: ClosedRange<Int> = switch weight {
    case "medium": 6...6
    case "semibold": 7...8
    default: 9...10
    }
    let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
    let upright = members.filter { ($0[3] as? UInt).map { $0 & NSFontTraitMask.italicFontMask.rawValue == 0 } ?? true }
    let match = upright.first { wanted.contains(($0[2] as? Int) ?? 5) } ?? upright.min { abs((($0[2] as? Int) ?? 5) - wanted.lowerBound) < abs((($1[2] as? Int) ?? 5) - wanted.lowerBound) }
    return match?[0] as? String
  }

  static let candidateFormats: [Choice] = [
    Choice(value: "[label][candidate] [comment]", title: "1你好"),
    Choice(value: "[label] [candidate] [comment]", title: "1 你好"),
    Choice(value: "[label]. [candidate] [comment]", title: "1. 你好"),
    Choice(value: "[candidate] [comment]", title: "你好（不显示序号）"),
  ]
}

// MARK: - Input

/// What a modifier key does on its own: switch between Chinese and English, and what to do with
/// what is being typed.
enum SwitchKey: String, CaseIterable, Identifiable {
  case leftShift = "Shift_L", rightShift = "Shift_R", leftControl = "Control_L", rightControl = "Control_R", capsLock = "Caps_Lock"
  var id: String { rawValue }
  var title: String {
    switch self {
    case .leftShift: "左 Shift"
    case .rightShift: "右 Shift"
    case .leftControl: "左 Control"
    case .rightControl: "右 Control"
    case .capsLock: "Caps Lock"
    }
  }
  var actions: [Choice] {
    let all = [
      Choice(value: "commit_code", title: "切换中英，已输入的编码上屏"),
      Choice(value: "commit_text", title: "切换中英，已拼出的字词上屏"),
      Choice(value: "clear", title: "切换中英，清空已输入的编码"),
      Choice(value: "inline_ascii", title: "临时英文，回车上屏后回到中文"),
      Choice(value: "noop", title: "不切换"),
    ]
    return self == .capsLock ? all.filter { ["commit_code", "commit_text", "clear", "noop"].contains($0.value) } : all
  }
}

enum PagingKeys: String, CaseIterable, Identifiable {
  case minusEqual, commaPeriod, brackets
  var id: String { rawValue }
  var keys: (up: String, down: String) {
    switch self {
    case .minusEqual: ("minus", "equal")
    case .commaPeriod: ("comma", "period")
    case .brackets: ("bracketleft", "bracketright")
    }
  }
  var title: String {
    switch self {
    case .minusEqual: "- 和 ="
    case .commaPeriod: ", 和 ."
    case .brackets: "[ 和 ]"
    }
  }
}

extension SettingsStore {
  var enabledSchemas: [String] {
    value(defaults, "schema_list")?.listValue?.compactMap { $0["schema"]?.scalar } ?? []
  }

  func setEnabledSchemas(_ ids: [String]) {
    set(defaults, "schema_list", .list(ids.map { .map([YAMLEntry(key: "schema", value: .scalar($0))]) }))
  }

  /// Schemas other schemas use (melt_eng, radical_pinyin…), hidden unless enabled.
  var dependencySchemas: Set<String> {
    Set(schemas.flatMap(\.dependencies))
  }

  func switchKey(_ key: SwitchKey) -> String {
    string(defaults, "ascii_composer/switch_key/\(key.rawValue)") ?? "noop"
  }

  func setSwitchKey(_ key: SwitchKey, _ action: String) {
    set(defaults, "ascii_composer/switch_key/\(key.rawValue)", .scalar(action))
  }

  private var bindings: [YAMLNode] {
    value(defaults, "key_binder/bindings")?.listValue ?? []
  }

  func isPaging(_ paging: PagingKeys) -> Bool {
    func has(_ accept: String, _ send: String) -> Bool {
      bindings.contains { $0["accept"]?.scalar == accept && $0["send"]?.scalar == send }
    }
    return has(paging.keys.up, "Page_Up") && has(paging.keys.down, "Page_Down")
  }

  func setPaging(_ paging: PagingKeys, _ enabled: Bool) {
    let keys = [paging.keys.up, paging.keys.down]
    var list = bindings.filter { binding in
      !(keys.contains(binding["accept"]?.scalar ?? "") && ["Page_Up", "Page_Down"].contains(binding["send"]?.scalar ?? ""))
    }
    if enabled {
      for (accept, send) in [(paging.keys.up, "Page_Up"), (paging.keys.down, "Page_Down")] {
        list.append(.map([YAMLEntry(key: "accept", value: .scalar(accept)), YAMLEntry(key: "send", value: .scalar(send)),
                          YAMLEntry(key: "when", value: .scalar("has_menu"))]))
      }
    }
    setUnordered(defaults, "key_binder/bindings", list)
  }

  /// The keys of 以词定字 (rime-ice's select_character.lua), as a pair, or none.
  var selectCharacterKeys: PagingKeys? {
    let first = string(defaults, "key_binder/select_first_character") ?? ""
    return PagingKeys.allCases.first { $0.keys.up == first }
  }

  func setSelectCharacterKeys(_ keys: PagingKeys?) {
    set(defaults, "key_binder/select_first_character", .scalar(keys?.keys.up ?? ""))
    set(defaults, "key_binder/select_last_character", .scalar(keys?.keys.down ?? ""))
  }

  static let switcherHotkeys: [Choice] = [
    Choice(value: "F4", title: "F4"),
    Choice(value: "Control+grave", title: "Control-`"),
    Choice(value: "Control+Shift+grave", title: "Control-Shift-`"),
    Choice(value: "Alt+grave", title: "Option-`"),
  ]

  var hotkeys: [String] { strings(defaults, "switcher/hotkeys") }

  func setHotkey(_ key: String, _ enabled: Bool) {
    var keys = hotkeys.filter { $0 != key }
    if enabled {
      keys.append(key)
    }
    setUnordered(defaults, "switcher/hotkeys", keys.map { .scalar($0) })
  }
}

// MARK: - rime-ice

struct SchemaSwitch: Identifiable, Hashable {
  let index: Int
  let name: String
  let states: [String]
  let reset: Int?
  var id: String { name }

  var title: String {
    switch name {
    case "ascii_mode": "中文 / 英文"
    case "ascii_punct": "中文标点 / 英文标点"
    case "traditionalization": "简体 / 繁体"
    case "emoji": "Emoji 候选"
    case "full_shape": "半角 / 全角"
    case "search_single_char": "辅码查词时单字优先"
    default: name
    }
  }
  var options: [String] {
    switch name {
    case "ascii_mode": ["中文", "英文"]
    case "ascii_punct": ["中文标点", "英文标点"]
    case "traditionalization": ["简体", "繁体"]
    case "emoji", "search_single_char": ["关", "开"]
    case "full_shape": ["半角", "全角"]
    default: states.count == 2 ? states : ["关", "开"]
    }
  }
}

struct FuzzyRule: Identifiable, Hashable {
  let id: String
  let title: String
  let rules: [String]
}

extension SettingsStore {
  static let fuzzyRules: [FuzzyRule] = [
    FuzzyRule(id: "zh", title: "z c s ↔ zh ch sh", rules: ["derive/^([zcs])h/$1/", "derive/^([zcs])([^h])/$1h$2/"]),
    FuzzyRule(id: "nl", title: "n ↔ l", rules: ["derive/^n/l/", "derive/^l/n/"]),
    FuzzyRule(id: "fh", title: "f ↔ h", rules: ["derive/^f/h/", "derive/^h/f/"]),
    FuzzyRule(id: "rl", title: "r ↔ l", rules: ["derive/^r/l/", "derive/^l/r/"]),
    FuzzyRule(id: "gk", title: "g ↔ k", rules: ["derive/^g/k/", "derive/^k/g/"]),
    FuzzyRule(id: "an", title: "an ↔ ang", rules: ["derive/ang$/an/", "derive/an$/ang/"]),
    FuzzyRule(id: "en", title: "en ↔ eng", rules: ["derive/eng$/en/", "derive/en$/eng/"]),
    FuzzyRule(id: "in", title: "in ↔ ing", rules: ["derive/ing$/in/", "derive/in$/ing/"]),
    FuzzyRule(id: "ian", title: "ian ↔ iang", rules: ["derive/iang$/ian/", "derive/ian$/iang/"]),
    FuzzyRule(id: "uan", title: "uan ↔ uang", rules: ["derive/uang$/uan/", "derive/uan$/uang/"]),
  ]

  /// rime-ice's pinyin schemas these settings apply to: 全拼, and the enabled 双拼 ones.
  var iceSchemas: [String] {
    let available = Set(schemas.filter { !$0.bundled }.map(\.id))
    var ids = available.contains("rime_ice") ? ["rime_ice"] : []
    ids += enabledSchemas.filter { $0.hasPrefix("double_pinyin") && available.contains($0) }
    return ids
  }

  var mainIceSchema: String? { iceSchemas.first }

  func switches(of schemaID: String) -> [SchemaSwitch] {
    let items = value(schema(schemaID), "switches")?.listValue ?? []
    return items.enumerated().compactMap { index, item in
      guard let name = item["name"]?.scalar else { return nil }
      return SchemaSwitch(index: index, name: name, states: item["states"]?.listValue?.compactMap(\.scalar) ?? [], reset: item["reset"]?.intValue)
    }
  }

  /// The state each new input field starts with.
  func switchDefault(_ name: String) -> Int {
    guard let schemaID = mainIceSchema else { return 0 }
    return switches(of: schemaID).first { $0.name == name }?.reset ?? 0
  }

  func setSwitchDefault(_ name: String, _ state: Int) {
    for schemaID in iceSchemas {
      let file = schema(schemaID)
      let items = (file.baseValue("switches")?.listValue ?? []).enumerated()
      guard let (index, base) = items.first(where: { $0.element["name"]?.scalar == name }) else { continue }
      // No reset and off keeps the schema's own behavior (the switcher remembers it).
      let keepsBase = base["reset"] == nil && state == 0
      file.set("switches/@\(index)/reset", keepsBase ? nil : .int(state))
    }
    changed()
  }

  func isFuzzy(_ rule: FuzzyRule) -> Bool {
    guard let schemaID = mainIceSchema else { return false }
    let algebra = strings(schema(schemaID), "speller/algebra")
    return rule.rules.allSatisfy(algebra.contains)
  }

  func setFuzzy(_ rule: FuzzyRule, _ enabled: Bool) {
    let wanted = Self.fuzzyRules.filter { $0 == rule ? enabled : isFuzzy($0) }
    let known = Set(Self.fuzzyRules.flatMap(\.rules))
    for schemaID in iceSchemas {
      let file = schema(schemaID)
      let algebra = file.value("speller/algebra")?.listValue?.compactMap(\.scalar) ?? []
      // Spelling rules apply in order: fuzzy ones first, on the full pinyin.
      let rules = wanted.flatMap(\.rules) + algebra.filter { !known.contains($0) }
      file.set("speller/algebra", .strings(rules))
    }
    changed()
  }
}

// MARK: - Apps

struct AppEntry: Identifiable, Hashable {
  let id: String
  let options: [String: Bool]

  var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
  var name: String {
    guard let url else { return id }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
  }
  var icon: NSImage {
    url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application)
  }
}

extension SettingsStore {
  static let appOptions: [Choice] = [
    Choice(value: "ascii_mode", title: "默认英文"),
    Choice(value: "no_inline", title: "不内嵌编码"),
    Choice(value: "vim_mode", title: "Vim 模式"),
  ]

  var apps: [AppEntry] {
    (value(squirrel, "app_options")?.mapValue ?? []).compactMap { entry in
      var options = [String: Bool]()
      for option in entry.value.mapValue ?? [] {
        options[option.key] = option.value.boolValue
      }
      return options.isEmpty ? nil : AppEntry(id: entry.key, options: options)
    }.sorted {
      // Installed apps first: Squirrel lists many that are not.
      ($0.url == nil ? 1 : 0, $0.name.lowercased()) < ($1.url == nil ? 1 : 0, $1.name.lowercased())
    }
  }

  func setAppOption(_ app: String, _ option: String, _ enabled: Bool) {
    let path = "app_options/\(app)/\(option)"
    if !enabled && squirrel.baseValue(path) == nil {
      squirrel.set(path, nil)
      // With every option off, keep the app listed.
      if (squirrel.value("app_options/\(app)")?.mapValue ?? []).isEmpty {
        squirrel.set(path, .bool(false))
      }
    } else {
      squirrel.set(path, .bool(enabled))
    }
    changed()
  }

  func addApp(_ bundleID: String) {
    guard !apps.contains(where: { $0.id == bundleID }) else { return }
    squirrel.set("app_options/\(bundleID)/ascii_mode", .bool(true))
    changed()
  }

  func removeApp(_ bundleID: String) {
    squirrel.removeAll(under: "app_options/\(bundleID)")
    if squirrel.baseValue("app_options/\(bundleID)") != nil {
      squirrel.set("app_options/\(bundleID)", .map([]))
    }
    changed()
  }
}

// MARK: - User data

struct UserDictionary: Identifiable, Hashable {
  let id: String
  let size: Int64
  let modified: Date?

  /// The *.userdb folders: words learned while typing, per dictionary.
  static func all() -> [UserDictionary] {
    let manager = FileManager.default
    let folders = (try? manager.contentsOfDirectory(atPath: RimePaths.userDir.path)) ?? []
    return folders.filter { $0.hasSuffix(".userdb") }.sorted().map { name in
      let url = RimePaths.userDir.appending(component: name)
      var size: Int64 = 0
      for file in (try? manager.contentsOfDirectory(atPath: url.path)) ?? [] {
        size += ((try? manager.attributesOfItem(atPath: url.appending(component: file).path))?[.size] as? Int64) ?? 0
      }
      let modified = (try? manager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
      return UserDictionary(id: String(name.dropLast(".userdb".count)), size: size, modified: modified)
    }
  }
}

extension SettingsStore {
  /// Where 「同步用户数据」 writes this Mac's snapshot.
  var syncFolder: URL {
    _ = revision
    let base = installation.syncDir.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? RimePaths.userDir.appending(component: "sync")
    return installation.installationID.map { base.appending(component: $0) } ?? base
  }

  func setSyncDir(_ path: String?) {
    installation.syncDir = path
    changed()
  }

  /// The user folder, without build output, as a .tar.gz.
  nonisolated static func backUpUserFolder(to destination: URL) throws {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    task.arguments = ["-czf", destination.path, "-C", RimePaths.userDir.deletingLastPathComponent().path,
                      "--exclude", "\(RimePaths.userDir.lastPathComponent)/build", RimePaths.userDir.lastPathComponent]
    try task.run()
    task.waitUntilExit()
    if task.terminationStatus != 0 {
      throw CocoaError(.fileWriteUnknown)
    }
  }
}
