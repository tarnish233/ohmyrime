//
//  SettingsStore.swift
//  鼠须管设置
//
//  What the views edit: Squirrel's, the default and the schemas' configs, custom phrases and
//  installation.yaml. Changes are saved shortly after the last one, then Squirrel deploys.
//

import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class SettingsStore {
  let squirrel: ConfigFile
  let defaults: ConfigFile
  let phrases: PhraseBook
  let installation: InstallationFile
  let deployer = Deployer()
  private(set) var schemas: [SchemaInfo] = []
  /// Bumped on every change, so that views reading settings refresh.
  private(set) var revision = 0
  private(set) var saveError: String?
  /// Off in tests: save without asking Squirrel to deploy.
  var deploysAfterSaving = true
  @ObservationIgnored private var schemaFiles: [String: ConfigFile] = [:]
  @ObservationIgnored private var saveTask: Task<Void, Never>?
  @ObservationIgnored private let backupStamp: String

  init() {
    squirrel = ConfigFile(id: "squirrel")
    defaults = ConfigFile(id: "default")
    phrases = PhraseBook(url: RimePaths.userDir.appending(component: "custom_phrase.txt"))
    installation = InstallationFile()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    backupStamp = formatter.string(from: Date())
    schemas = SchemaInfo.discover()
  }

  func schema(_ id: String) -> ConfigFile {
    if let file = schemaFiles[id] {
      return file
    }
    let file = ConfigFile(id: "\(id).schema")
    schemaFiles[id] = file
    return file
  }

  private var allFiles: [ConfigFile] { [squirrel, defaults] + schemaFiles.values }

  /// Problems that keep a file from being edited.
  var problems: [String] {
    _ = revision
    return allFiles.compactMap(\.problem)
  }

  // MARK: Reading

  func value(_ file: ConfigFile, _ path: String) -> YAMLNode? {
    _ = revision
    return file.value(path)
  }

  func bool(_ file: ConfigFile, _ path: String) -> Bool? { value(file, path)?.boolValue }
  func double(_ file: ConfigFile, _ path: String) -> Double? { value(file, path)?.doubleValue }
  func int(_ file: ConfigFile, _ path: String) -> Int? { value(file, path)?.intValue }
  func string(_ file: ConfigFile, _ path: String) -> String? { value(file, path)?.scalar }
  func strings(_ file: ConfigFile, _ path: String) -> [String] { value(file, path)?.listValue?.compactMap(\.scalar) ?? [] }

  // MARK: Writing

  func set(_ file: ConfigFile, _ path: String, _ value: YAMLNode?) {
    file.set(path, value)
    changed()
  }

  /// A list whose order does not matter (key bindings, hotkeys): back to the default entry when
  /// it holds the same items as the base.
  func setUnordered(_ file: ConfigFile, _ path: String, _ items: [YAMLNode]) {
    let base = file.baseValue(path)?.listValue ?? []
    if base.map(\.flowText).sorted() == items.map(\.flowText).sorted() && !file.wasWritten(path) {
      file.set(path, nil)
    } else {
      file.set(path, .list(items))
    }
    changed()
  }

  func changed() {
    revision += 1
    scheduleSave()
  }

  func binding(_ file: ConfigFile, _ path: String, default fallback: Bool) -> Binding<Bool> {
    Binding(get: { self.bool(file, path) ?? fallback }, set: { self.set(file, path, .bool($0)) })
  }

  func binding(_ file: ConfigFile, _ path: String, default fallback: Double) -> Binding<Double> {
    Binding(get: { self.double(file, path) ?? fallback }, set: { self.set(file, path, .number($0)) })
  }

  func binding(_ file: ConfigFile, _ path: String, default fallback: Int) -> Binding<Int> {
    Binding(get: { self.int(file, path) ?? fallback }, set: { self.set(file, path, .int($0)) })
  }

  func binding(_ file: ConfigFile, _ path: String, default fallback: String) -> Binding<String> {
    Binding(get: { self.string(file, path) ?? fallback }, set: { self.set(file, path, .scalar($0)) })
  }

  // MARK: Saving

  func scheduleSave() {
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(700))
      guard !Task.isCancelled else { return }
      self?.saveNow()
    }
  }

  /// Saves what changed and asks Squirrel to deploy; waits for a running deploy first, and for the
  /// next second after the last one (see Deployer.nextSafeSave), unless `immediately` (quitting).
  func saveNow(immediately: Bool = false) {
    saveTask?.cancel()
    saveTask = nil
    if !immediately && deploysAfterSaving && (deployer.state == .deploying || deployer.nextSafeSave != nil) {
      let wait = max(0.25, deployer.nextSafeSave?.timeIntervalSinceNow ?? 0)
      saveTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(wait))
        guard !Task.isCancelled else { return }
        self?.saveNow()
      }
      return
    }
    var saved = [URL]()
    do {
      for file in allFiles where try file.save(backupStamp: backupStamp) {
        saved.append(file.customURL)
      }
      if try phrases.save(backupStamp: backupStamp) {
        saved.append(phrases.url)
      }
      if try installation.save(backupStamp: backupStamp) {
        saved.append(installation.url)
      }
      saveError = nil
    } catch {
      saveError = error.localizedDescription
    }
    if !saved.isEmpty && deploysAfterSaving {
      deployer.deploy(saved: saved)
    }
  }

  var hasUnsavedChanges: Bool {
    _ = revision
    return allFiles.contains(where: \.isDirty) || phrases.isDirty || installation.isDirty
  }

  func redeploy() {
    if hasUnsavedChanges {
      saveNow()
    } else {
      deployer.deploy()
    }
  }

  /// Picks up edits made elsewhere (in a text editor) when the app comes back to the front.
  func reloadChangedFiles() {
    var reloaded = false
    for file in allFiles where !file.isDirty && file.changedOnDisk {
      file.reload()
      reloaded = true
    }
    if !phrases.isDirty && phrases.changedOnDisk {
      phrases.reload()
      reloaded = true
    }
    if !installation.isDirty && installation.changedOnDisk {
      installation.reload()
      reloaded = true
    }
    schemas = SchemaInfo.discover()
    if reloaded {
      revision += 1
    }
  }
}

// MARK: - Schemas

struct SchemaInfo: Identifiable, Hashable {
  let id: String
  let name: String
  let dependencies: [String]
  /// Shipped with Squirrel rather than in the user folder.
  let bundled: Bool

  /// The schemas in the user folder and in Squirrel; the user's copy wins.
  static func discover() -> [SchemaInfo] {
    var found = [String: SchemaInfo]()
    for (folder, bundled) in [(RimePaths.sharedDir, true), (RimePaths.userDir, false)] {
      let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
      for file in files where file.hasSuffix(".schema.yaml") {
        guard let text = try? String(contentsOf: folder.appending(component: file), encoding: .utf8),
              let schema = schemaSection(text) else { continue }
        let id = schema["schema_id"]?.scalar ?? String(file.dropLast(".schema.yaml".count))
        found[id] = SchemaInfo(id: id, name: schema["name"]?.scalar ?? id,
                               dependencies: schema["dependencies"]?.listValue?.compactMap(\.scalar) ?? [], bundled: bundled)
      }
    }
    return found.values.sorted { ($0.bundled ? 1 : 0, $0.id) < ($1.bundled ? 1 : 0, $1.id) }
  }

  /// Only the `schema:` block, which is quick to parse.
  private static func schemaSection(_ text: String) -> YAMLNode? {
    let lines = text.components(separatedBy: "\n")
    guard let start = lines.firstIndex(where: { $0.hasPrefix("schema:") }) else { return nil }
    var end = start + 1
    while end < lines.count {
      if let first = lines[end].first, first != " ", first != "\t", first != "#" {
        break
      }
      end += 1
    }
    return RimeYAML.parse(lines[start..<end].joined(separator: "\n"))?["schema"]
  }
}

// MARK: - installation.yaml

/// librime's installation.yaml, for sync_dir.
final class InstallationFile {
  let url = RimePaths.userDir.appending(component: "installation.yaml")
  private(set) var document = PatchDocument(text: "", topLevel: true)
  private var savedText = ""
  private var loadedDate: Date?

  init() {
    reload()
  }

  func reload() {
    document = PatchDocument(text: (try? String(contentsOf: url, encoding: .utf8)) ?? "", topLevel: true)
    savedText = document.text
    loadedDate = modificationDate
  }

  private var modificationDate: Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
  }

  var changedOnDisk: Bool { modificationDate != loadedDate }
  var isDirty: Bool { document.text != savedText }

  var installationID: String? { document.value("installation_id")?.scalar }

  /// Where 「同步用户数据」 writes; the sync folder in the user folder unless set.
  var syncDir: String? {
    get { document.value("sync_dir")?.scalar }
    set {
      if let newValue, !newValue.isEmpty {
        try? document.set("sync_dir", .scalar(newValue))
      } else {
        try? document.remove("sync_dir")
      }
    }
  }

  @discardableResult
  func save(backupStamp: String) throws -> Bool {
    guard isDirty else { return false }
    let text = document.text
    guard RimeYAML.isValid(text) else { throw SettingsError.invalidYAML(url.lastPathComponent) }
    ConfigFile.backUp(url, stamp: backupStamp)
    try text.write(to: url, atomically: true, encoding: .utf8)
    savedText = text
    loadedDate = modificationDate
    return true
  }
}
