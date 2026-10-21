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
  let iceInstaller = RimeIceInstaller()
  private(set) var schemas: [SchemaInfo] = []
  /// Bumped on every change, so that views reading settings refresh.
  private(set) var revision = 0
  private(set) var saveError: String?
  /// Off in tests: save without asking Squirrel to deploy.
  var deploysAfterSaving = true
  /// How many seconds the fallback waits before writing the changes out whatever the state is.
  /// Short in the tests, which cannot wait ten of them.
  nonisolated(unsafe) static var fallbackDelay: Double = 10
  @ObservationIgnored private var schemaFiles: [String: ConfigFile] = [:]
  @ObservationIgnored private var saveTask: Task<Void, Never>?
  @ObservationIgnored private var installingIce = false
  @ObservationIgnored private let backupStamp: String

  init() {
    squirrel = ConfigFile(id: "squirrel")
    defaults = ConfigFile(id: "default")
    phrases = PhraseBook(url: RimePaths.userDir.appending(component: "custom_phrase.txt"))
    installation = InstallationFile()
    backupStamp = Self.stamp()
    schemas = SchemaInfo.discover()
  }

  /// A backup folder's name: "20261019-232404".
  static func stamp(_ date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
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
    diagnose("changed")
  }

  /// Tells the views that the state changed, without scheduling another save: after a save, the
  /// files are no longer dirty, and the toolbar has to show that. Without this, the views would
  /// keep the 「保存中…」 they drew when the change was made — the settings were saved and in
  /// effect, but the toolbar went on spinning.
  private func stateChanged() {
    revision += 1
  }

  /// The state that matters for saving, appended to a log: to find out why the toolbar says
  /// 「保存中」 forever. It always goes to the app's support folder; SQUIRREL_SETTINGS_DIAG=<file>
  /// changes where, and turns the copy in the system log on.
  private func diagnose(_ what: String) {
    let path = ProcessInfo.processInfo.environment["SQUIRREL_SETTINGS_DIAG"]
      ?? RimePaths.supportDir.appending(component: "diagnostics.log").path
    let dirty = allFiles.filter(\.isDirty).map { $0.fileName }
    let problems = allFiles.compactMap { $0.problem }
    var line = "\(Date().formatted(date: .omitted, time: .standard)) \(what)"
    line += " rev=\(revision) dirty=\(dirty.isEmpty ? "-" : dirty.joined(separator: ","))"
    line += " phrases=\(phrases.isDirty) install=\(installation.isDirty)"
    line += " deploy=\(deployer.state) slow=\(deployer.isSlow) lastFinish=\(deployer.lastFinish.map { $0.formatted(date: .omitted, time: .standard) } ?? "-")"
    line += " nextSafe=\(deployer.nextSafeSave.map { String(format: "%.2f", $0.timeIntervalSinceNow) } ?? "-")"
    line += " iceRunning=\(iceInstaller.isRunning)"
    line += " err=\(saveError ?? "-")"
    if !problems.isEmpty { line += " problem=\(problems.joined(separator: ";"))" }
    line += "\n"
    if ProcessInfo.processInfo.environment["SQUIRREL_SETTINGS_DIAG"] != nil {
      NSLog("OHMYRIME-DIAG %@", line)
    }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let handle = FileHandle(forWritingAtPath: path) {
      handle.seekToEndOfFile()
      handle.write(Data(line.utf8))
      try? handle.close()
    } else {
      try? Data(line.utf8).write(to: url)
    }
    // Keep it small: the last few hundred lines are enough to see what happened.
    if let text = try? String(contentsOf: url, encoding: .utf8), text.count > 200_000 {
      try? Data(text.suffix(100_000).utf8).write(to: url)
    }
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

  /// macOS suspends an app that is in the background for a while: its timers and tasks stop until
  /// it comes back. A pending save must not wait for that, or the toolbar would say 「保存中…」
  /// for as long as the app stays in the background. (The same for the wait for Squirrel's answer:
  /// see Deployer.)
  private var saveActivity: NSObjectProtocol?

  private func beginSaveActivity() {
    guard saveActivity == nil else { return }
    saveActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                        reason: "等设置保存")
  }

  private func endSaveActivity() {
    guard let saveActivity else { return }
    ProcessInfo.processInfo.endActivity(saveActivity)
    self.saveActivity = nil
  }

  func scheduleSave() {
    saveTask?.cancel()
    beginSaveActivity()
    saveTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(700))
      guard !Task.isCancelled else { return }
      self?.saveNow()
    }
    // A last resort: if the changes are still not on disk ten seconds later, something went wrong
    // (the app was suspended, the wait for Squirrel never ended…). Write them out now, whatever
    // the state is — the toolbar saying 「保存中…」 forever is worse than one extra write.
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.fallbackDelay))
      guard let self, self.hasUnsavedChanges else { return }
      self.diagnose("兜底：十秒后还没存上，直接写盘")
      let saved = self.writeChanges()
      self.stateChanged()
      if !saved.isEmpty && self.deploysAfterSaving {
        self.deployer.deploy(saved: saved, styleOnly: false)
      }
      self.endSaveActivity()
    }
  }

  /// Saves what changed and asks Squirrel to deploy; waits for a running deploy first, and for the
  /// next second after the last one (see Deployer.nextSafeSave), unless `immediately` (quitting).
  func saveNow(immediately: Bool = false) {
    diagnose("saveNow(enter)")
    saveTask?.cancel()
    saveTask = nil
    // Not while rime-ice is copied in either: Squirrel would deploy a half-copied folder.
    if !immediately && deploysAfterSaving && (deployer.state == .deploying || deployer.nextSafeSave != nil || iceInstaller.isRunning) {
      let wait = max(0.25, deployer.nextSafeSave?.timeIntervalSinceNow ?? 0)
      // The app must not be suspended while it waits (see beginSaveActivity).
      beginSaveActivity()
      saveTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(wait))
        guard !Task.isCancelled else { return }
        self?.saveNow()
      }
      return
    }
    let lookOnly = onlyLookChanged
    let saved = writeChanges()
    // The files are on disk now: the views have to hear it, or the toolbar keeps saying
    // 「保存中…」 (see stateChanged).
    stateChanged()
    diagnose("saveNow(wrote \(saved.count))")
    if !saved.isEmpty && deploysAfterSaving {
      deployer.deploy(saved: saved, styleOnly: lookOnly && saved == [squirrel.customURL])
    }
    endSaveActivity()
    diagnose("saveNow(leave)")
  }

  /// Whether the only unsaved changes are to Squirrel's look: then Squirrel reloads it without
  /// restarting Rime. App options are not: Squirrel applies them when it opens an input session.
  var onlyLookChanged: Bool {
    guard squirrel.isDirty, !defaults.isDirty, !schemaFiles.values.contains(where: \.isDirty),
          !phrases.isDirty, !installation.isDirty else { return false }
    let keys = squirrel.changedKeys
    return !keys.isEmpty && keys.allSatisfy(Self.isLookKey)
  }

  /// squirrel.yaml keys Squirrel reads again when it reloads its look.
  nonisolated static func isLookKey(_ key: String) -> Bool {
    let root = key.split(separator: "/").first.map(String.init) ?? key
    return ["style", "status_icon", "show_notifications_when", "preset_color_schemes"].contains(root.trimmingCharacters(in: CharacterSet(charactersIn: "+")))
  }

  /// Writes the files that changed; returns them.
  private func writeChanges() -> [URL] {
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
    return saved
  }

  /// Until a running deploy ends (at most a minute), and the second after the last one.
  private func waitUntilSavingIsSafe() async {
    guard deploysAfterSaving else { return }
    let start = Date()
    while deployer.state == .deploying && Date().timeIntervalSince(start) < 60 {
      try? await Task.sleep(for: .milliseconds(200))
    }
    if let wait = deployer.nextSafeSave?.timeIntervalSinceNow, wait > 0 {
      try? await Task.sleep(for: .seconds(wait))
    }
  }

  /// Saves what changed and deploys now, waiting for a running deploy and for the second after the
  /// last one first (see Deployer.nextSafeSave); Squirrel gets `timeout` seconds.
  func deployNow(timeout: Double = 45) async {
    saveTask?.cancel()
    saveTask = nil
    await waitUntilSavingIsSafe()
    let saved = writeChanges()
    stateChanged()
    if deploysAfterSaving {
      deployer.deploy(saved: saved, timeout: timeout)
    }
  }

  var hasUnsavedChanges: Bool {
    _ = revision
    return allFiles.contains(where: \.isDirty) || phrases.isDirty || installation.isDirty
  }

  /// A phrase added (or edited) but not finished (missing text or code): custom_phrase.txt is
  /// left dirty until it is completed or removed, on purpose, so nothing half-typed is written.
  /// The toolbar should say so instead of spinning forever as if a save were stuck.
  var incompletePhrases: Int {
    _ = revision
    return phrases.phrases.filter { $0.problem != nil }.count
  }

  /// Which files are not on disk yet, for the toolbar's explanation.
  var unsavedFileNames: [String] {
    _ = revision
    var names = allFiles.filter(\.isDirty).map(\.fileName)
    if phrases.isDirty { names.append("custom_phrase.txt") }
    if installation.isDirty { names.append("installation.yaml") }
    return names
  }

  /// Drops the changes not saved yet: uninstalling deletes the user folder, and saving them when
  /// the app quits would bring it back.
  func discardUnsavedChanges() {
    saveTask?.cancel()
    saveTask = nil
    endSaveActivity()
    for file in allFiles where file.isDirty {
      file.reload()
    }
    if phrases.isDirty {
      phrases.reload()
    }
    if installation.isDirty {
      installation.reload()
    }
    revision += 1
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

  // MARK: rime-ice

  /// Whether rime-ice is in the user folder.
  var iceInstalled: Bool {
    schemas.contains { $0.id == "rime_ice" && !$0.bundled }
  }

  /// rime-ice's version (its schema's), when it is installed.
  var iceVersion: String? {
    schemas.first { $0.id == "rime_ice" && !$0.bundled }?.version
  }

  /// Enabled schemas without a schema file: Rime cannot load them.
  var missingSchemas: [String] {
    let known = Set(schemas.map(\.id))
    return enabledSchemas.filter { !known.contains($0) }
  }

  /// No enabled schema can be loaded, so Squirrel passes the keys through: English only.
  var typesOnlyEnglish: Bool {
    let enabled = enabledSchemas
    return !enabled.isEmpty && missingSchemas.count == enabled.count
  }

  /// Schemas that come with rime-ice.
  nonisolated static func isIceSchema(_ id: String) -> Bool {
    ["rime_ice", "t9", "melt_eng", "radical_pinyin"].contains(id) || id.hasPrefix("double_pinyin")
  }

  /// Installs rime-ice, or updates it, with the bundled scripts/rime-ice.sh; then makes it the
  /// default schema if it was not enabled, and deploys (the first deploy builds its dictionaries).
  func installRimeIce(from source: RimeIceInstaller.Source = .download) async {
    guard !installingIce else { return }
    installingIce = true
    defer { installingIce = false }
    let wasInstalled = iceInstalled
    let before = iceVersion
    iceInstaller.willRun()
    // Edits still waiting for the save delay go in first, so that the backup and the deploy take
    // them; not in the second of the last deploy, or Rime would take the file for unchanged.
    saveTask?.cancel()
    saveTask = nil
    await waitUntilSavingIsSafe()
    let written = writeChanges()
    let installed = await iceInstaller.run(from: source, backupDir: RimePaths.backupDir.appending(component: Self.stamp()))
    ConfigFile.pruneFolderBackups(keeping: 3)
    ConfigFile.pruneBackups(keeping: 20)
    reloadChangedFiles()
    guard installed, iceInstalled else {
      if !written.isEmpty && deploysAfterSaving {
        deployer.deploy(saved: written)
      }
      return
    }
    if !enabledSchemas.contains("rime_ice") {
      setEnabledSchemas(["rime_ice"] + enabledSchemas)
    }
    let version = iceVersion.map { "（\($0)）" } ?? ""
    if !wasInstalled {
      iceInstaller.summary = "已安装雾凇拼音\(version)"
    } else if let before, let after = iceVersion, before != after {
      iceInstaller.summary = "已更新雾凇拼音：\(before) → \(after)"
    } else if source == .download {
      iceInstaller.summary = "已更新到最新发布版\(version)"
    } else {
      iceInstaller.summary = "已重新安装\(version)"
    }
    await deployNow(timeout: 120)
  }
}

// MARK: - Schemas

struct SchemaInfo: Identifiable, Hashable {
  let id: String
  let name: String
  let dependencies: [String]
  /// Shipped with Squirrel rather than in the user folder.
  let bundled: Bool
  var version: String?
  /// Enabled, but there is no schema file for it.
  var missing = false

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
                               dependencies: schema["dependencies"]?.listValue?.compactMap(\.scalar) ?? [], bundled: bundled,
                               version: schema["version"]?.scalar)
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
