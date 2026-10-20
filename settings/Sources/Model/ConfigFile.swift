//
//  ConfigFile.swift
//  鼠须管设置
//
//  One Rime config as the settings app edits it: its base file (such as squirrel.yaml) and the
//  patch in its *.custom.yaml file.
//

import Foundation

enum RimePaths {
  /// ~/Library/Rime, or the directory given with --user-dir (tests).
  nonisolated(unsafe) static var userDir: URL = FileManager.default.homeDirectoryForCurrentUser.appending(components: "Library", "Rime")

  static var squirrelApp: URL {
    let system = URL(fileURLWithPath: "/Library/Input Methods/Squirrel.app")
    let user = FileManager.default.homeDirectoryForCurrentUser.appending(components: "Library", "Input Methods", "Squirrel.app")
    return FileManager.default.fileExists(atPath: system.path) || !FileManager.default.fileExists(atPath: user.path) ? system : user
  }
  static var sharedDir: URL { squirrelApp.appending(components: "Contents", "SharedSupport") }
  static var buildDir: URL { userDir.appending(component: "build") }
  /// Squirrel's log directory (glog files).
  static var logDir: URL { FileManager.default.temporaryDirectory.appending(component: "rime.squirrel") }
  /// The app's own folder: backups, and what install.sh installed last (installed.json).
  nonisolated(unsafe) static var supportDir: URL = FileManager.default.homeDirectoryForCurrentUser
    .appending(components: "Library", "Application Support", "鼠须管设置")
  /// Where the files are copied before the first change in each session.
  nonisolated(unsafe) static var backupDir: URL = supportDir.appending(component: "Backups")

  /// The user's copy of a file if there is one, the one shipped with Squirrel otherwise.
  static func base(_ name: String) -> URL? {
    [userDir, sharedDir].map { $0.appending(component: name) }.first { FileManager.default.fileExists(atPath: $0.path) }
  }
}

enum SettingsError: LocalizedError {
  case invalidYAML(String)

  var errorDescription: String? {
    switch self {
    case .invalidYAML(let file): "生成的 \(file) 不是有效的 YAML，没有写入"
    }
  }
}

final class ConfigFile {
  /// "squirrel", "default", or "<schema>.schema".
  let id: String
  let customURL: URL
  private(set) var base: YAMLNode = .map([])
  private(set) var document = PatchDocument(text: "")
  private(set) var savedText = ""
  /// Why the custom file cannot be edited, if it cannot.
  private(set) var problem: String?
  private var effectiveCache: YAMLNode?
  private var loadedDate: Date?
  /// The base file as it was read: it may change, or become the user's copy (installing
  /// rime-ice puts its own default.yaml in the user folder).
  private var loadedBase: (url: URL?, date: Date?) = (nil, nil)
  /// Entries that were in the file when it was read: updated in place even when they come to say
  /// what the base says, so that lines the user wrote, and their comments, stay.
  private var writtenKeys = Set<String>()

  init(id: String) {
    self.id = id
    let customName = id.hasSuffix(".schema") ? String(id.dropLast(".schema".count)) : id
    customURL = RimePaths.userDir.appending(component: "\(customName).custom.yaml")
    reload()
  }

  var baseURL: URL? { RimePaths.base("\(id).yaml") }
  var isDirty: Bool { document.text != savedText }
  var fileName: String { customURL.lastPathComponent }

  func reload() {
    let baseURL = self.baseURL
    loadedBase = (baseURL, baseURL.flatMap(Self.modificationDate(of:)))
    base = baseURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }.flatMap(RimeYAML.parse) ?? .map([])
    // As this app would write it (a missing final newline is no change).
    document = PatchDocument(text: (try? String(contentsOf: customURL, encoding: .utf8)) ?? "")
    savedText = document.text
    loadedDate = modificationDate
    effectiveCache = nil
    do {
      writtenKeys = Set(try document.entries().map(\.key))
      problem = nil
    } catch {
      problem = "\(fileName)：\(error)"
    }
  }

  private var modificationDate: Date? {
    Self.modificationDate(of: customURL)
  }

  private static func modificationDate(of url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
  }

  /// Whether the custom file, or the base file, was changed by someone else since it was read.
  var changedOnDisk: Bool {
    let baseURL = self.baseURL
    return modificationDate != loadedDate || baseURL != loadedBase.url || baseURL.flatMap(Self.modificationDate(of:)) != loadedBase.date
  }

  /// The config as Rime will read it: the base with every patch entry applied, in Rime's order.
  var effective: YAMLNode {
    if let effectiveCache {
      return effectiveCache
    }
    let result = effective(of: document)
    effectiveCache = result
    return result
  }

  private func effective(of document: PatchDocument) -> YAMLNode {
    let entries = document.values().sorted { Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8)) }
    return entries.reduce(base) { $0.setting($1.value, at: $1.key) }
  }

  func value(_ path: String) -> YAMLNode? {
    effective.value(at: path)
  }

  func baseValue(_ path: String) -> YAMLNode? {
    base.value(at: path)
  }

  func isPatched(_ key: String) -> Bool {
    document.entry(key) != nil
  }

  func wasWritten(_ key: String) -> Bool {
    writtenKeys.contains(key)
  }

  /// Patch entries added, changed or removed since the file was read or saved.
  var changedKeys: Set<String> {
    func values(_ document: PatchDocument) -> [String: String] {
      Dictionary(document.values().map { ($0.key, $0.value.flowText) }, uniquingKeysWith: { first, _ in first })
    }
    let before = values(PatchDocument(text: savedText))
    let after = values(document)
    return Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
  }

  /// Sets a value. A new entry is added only when Rime would not read that value anyway, and goes
  /// again when it comes back to it; entries that were in the file stay. nil removes the entry
  /// (back to the default).
  /// Why the last direct edit failed, for the page to show.
  func reportProblem(_ text: String) {
    problem = text
  }

  /// Edits the patch document's text directly, for entries librime cannot read back (a map keyed
  /// by "/"), then forgets the cached effective config.
  func editDocument(_ body: (inout PatchDocument) throws -> Void) rethrows {
    try body(&document)
    effectiveCache = nil
  }

  func set(_ path: String, _ value: YAMLNode?) {
    guard problem == nil else { return }
    var without = document
    try? without.remove(path)
    let fallback = effective(of: without).value(at: path)
    if let value, !(fallback.map { $0.sameValue(as: value) } ?? false) || writtenKeys.contains(path) {
      if document.lines.isEmpty {
        document = PatchDocument(text: Self.header(for: self))
      }
      // In place when the entry is there, so that it stays next to its comment.
      try? document.set(path, value)
    } else {
      document = without
    }
    effectiveCache = nil
  }

  /// Removes every entry under a key, such as all of one app's options.
  func removeAll(under prefix: String) {
    guard problem == nil else { return }
    try? document.removeAll { $0 == prefix || $0.hasPrefix(prefix + "/") }
    effectiveCache = nil
  }

  /// Writes the custom file when it changed. Returns whether it wrote.
  @discardableResult
  func save(backupStamp: String) throws -> Bool {
    guard isDirty, problem == nil else { return false }
    let text = document.text
    guard RimeYAML.isValid(text) else { throw SettingsError.invalidYAML(fileName) }
    Self.backUp(customURL, stamp: backupStamp)
    try FileManager.default.createDirectory(at: customURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: customURL, atomically: true, encoding: .utf8)
    savedText = text
    loadedDate = modificationDate
    return true
  }

  static func header(for file: ConfigFile) -> String {
    let base = "\(file.id).yaml"
    return """
      # 由「鼠须管设置」写入，也可以手动编辑。
      # 这里的每一项按 Rime 的 patch 规则覆盖 \(base) 中的同名设置。
      patch:

      """
  }

  /// Copies a file into this session's backup folder once.
  static func backUp(_ url: URL, stamp: String) {
    let manager = FileManager.default
    guard manager.fileExists(atPath: url.path) else { return }
    let folder = RimePaths.backupDir.appending(component: stamp)
    let target = folder.appending(component: url.lastPathComponent)
    guard !manager.fileExists(atPath: target.path) else { return }
    try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
    try? manager.copyItem(at: url, to: target)
    pruneBackups(keeping: 20)
  }

  /// Backups of the whole user folder (Rime-*.tar.gz, before installing rime-ice) are big, about
  /// 16 MB with rime-ice's dictionaries: only the last few stay.
  static func pruneFolderBackups(keeping count: Int) {
    let manager = FileManager.default
    let root = RimePaths.backupDir
    func archives(in folder: String) -> [String] {
      ((try? manager.contentsOfDirectory(atPath: root.appending(component: folder).path)) ?? [])
        .filter { $0.hasPrefix("Rime-") && $0.hasSuffix(".tar.gz") }
    }
    let folders = ((try? manager.contentsOfDirectory(atPath: root.path)) ?? []).sorted().filter { !archives(in: $0).isEmpty }
    for folder in folders.dropLast(count) {
      for archive in archives(in: folder) {
        try? manager.removeItem(at: root.appending(components: folder, archive))
      }
      if ((try? manager.contentsOfDirectory(atPath: root.appending(component: folder).path)) ?? []).isEmpty {
        try? manager.removeItem(at: root.appending(component: folder))
      }
    }
  }

  static func pruneBackups(keeping count: Int) {
    let manager = FileManager.default
    guard let folders = try? manager.contentsOfDirectory(atPath: RimePaths.backupDir.path) else { return }
    for old in folders.sorted().dropLast(count) {
      try? manager.removeItem(at: RimePaths.backupDir.appending(component: old))
    }
  }
}

extension YAMLNode {
  /// Equal as Rime reads them: numbers by value, booleans in any case.
  func sameValue(as other: YAMLNode) -> Bool {
    switch (self, other) {
    case (.scalar(let a), .scalar(let b)):
      if a == b { return true }
      if let x = Double(a), let y = Double(b) { return x == y }
      return a.lowercased() == b.lowercased() && ["true", "false"].contains(a.lowercased())
    case (.list(let a), .list(let b)):
      return a.count == b.count && zip(a, b).allSatisfy { $0.sameValue(as: $1) }
    case (.map(let a), .map(let b)):
      // Maps have no order (librime sorts them).
      return a.count == b.count && a.allSatisfy { entry in b.first { $0.key == entry.key }.map { $0.value.sameValue(as: entry.value) } ?? false }
    case (.null, .null):
      return true
    default:
      return false
    }
  }
}
