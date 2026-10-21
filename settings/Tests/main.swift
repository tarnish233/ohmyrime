//
//  Model tests: YAML round trips through librime, the patch editor, and the settings on a copy
//  of a Rime user folder. Run with scripts/test-settings.sh.
//

import Foundation

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String, _ detail: @autoclosure () -> String = "") {
  if condition() {
    print("  ✓ \(message)")
  } else {
    print("  ✗ \(message)" + (detail().isEmpty ? "" : "\n      \(detail())"))
    failures += 1
  }
}

var traits = RimeTraits.rimeStructInit()
traits.min_log_level = 3
rime_get_api_stdbool().pointee.setup(&traits)

print("== YAML scalars survive a round trip")
let samples = ["rime_ice", "PingFang SC", "PingFangSC-Medium", "[label][candidate] [comment]", "derive/^([zcs])h/$1/",
               "it's", "a # b", "true", "null", "~", "-1.5", "16", "", "😄", "中文 / 英文", "Control+Shift+grave",
               "{ x }", "- item", "key: value", "0x7FFFFFFF", "…", "%", "@at", "line\nbreak", "tab\there"]
for sample in samples {
  let text = "value: \(YAMLNode.quoted(sample))\n"
  let back = RimeYAML.parse(text)?["value"]?.scalar
  check(back == sample, "\(sample.debugDescription) → \(YAMLNode.quoted(sample))", "read back \(back.debugDescription)")
}

print("== YAML collections survive a round trip")
let bindings = YAMLNode.list([
  .map([YAMLEntry(key: "accept", value: .scalar("comma")), YAMLEntry(key: "send", value: .scalar("Page_Up")), YAMLEntry(key: "when", value: .scalar("has_menu"))]),
  .map([YAMLEntry(key: "schema", value: .scalar("rime_ice"))]),
  .strings(["derive/^n/l/", "xform/(.)ai$/$1Ⓓ/"]),
  .map([YAMLEntry(key: "name", value: .scalar("emoji")), YAMLEntry(key: "states", value: .strings(["💀", "😄"])), YAMLEntry(key: "reset", value: .int(1)),
        YAMLEntry(key: "nested", value: .map([YAMLEntry(key: "a", value: .list([.scalar("x"), .map([YAMLEntry(key: "b", value: .scalar("y"))])]))]))]),
  .map([]), .list([]), .null,
])
let document = YAMLNode.map([YAMLEntry(key: "value", value: bindings)])
let parsed = RimeYAML.parse(document.documentText)
check(parsed?.sameValue(as: document) == true, "lists of maps, nested maps, empty collections", document.documentText)

print("== YAML paths and patches")
var tree = RimeYAML.parse("a:\n  b: 1\n  list: [x, y, z]\n")!
check(tree.value(at: "a/list/@1")?.scalar == "y", "@1 reads a list item")
check(tree.value(at: "a/list/@last")?.scalar == "z", "@last reads the last item")
tree = tree.setting(.scalar("Y"), at: "a/list/@1").setting(.int(2), at: "a/c/d").setting(.strings(["w"]), at: "a/list/+")
check(tree.value(at: "a/list")?.listValue?.compactMap(\.scalar) == ["x", "Y", "z", "w"], "@1 sets, /+ appends")
check(tree.value(at: "a/c/d")?.scalar == "2" && tree.value(at: "a/b")?.scalar == "1", "deeper keys create maps, others stay")

print("== patch editor")
let template = try! String(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]).appending(components: "rime", "squirrel.custom.yaml"), encoding: .utf8)
var patch = PatchDocument(text: template)
let keys = (try? patch.entries().map(\.key)) ?? []
check(keys.count == 39 && keys.first == "style/candidate_list_layout", "reads the template's \(keys.count) entries")
check(patch.value("style/border_width")?.doubleValue == 9.5 && patch.value("style/font_face")?.scalar == "PingFang SC", "reads values")
try! patch.set("style/font_point", .int(18))
try! patch.set("style/new_key", .scalar("a b"))
// The template's actual last entry, so removing it (like setting the new key) stays near the end.
check(keys.last == "app_options/com.apple.Safari/ascii_mode", "the template still ends the way this test expects")
try! patch.remove("app_options/com.apple.Safari/ascii_mode")
let changedLines = zip(template.components(separatedBy: "\n"), patch.text.components(separatedBy: "\n")).filter { $0 != $1 }
check(patch.value("style/font_point")?.intValue == 18 && patch.text.contains("  style/font_point: 18\n"), "replaces a value in place")
check(patch.text.contains("  style/new_key: 'a b'\n") && !patch.text.contains("app_options/com.apple.Safari"), "adds after the last entry, removes")
check(patch.text.contains("# 动效：展开 0.20 s") && changedLines.count <= 2, "comments and other lines stay (\(changedLines.count) changed before the end)")

var commented = PatchDocument(text: "# head\npatch:\n  # about a\n  \"a/b\": \"x # y\"  # note\n# column 0 comment\n  list:\n    - 1\n\n    # - 2\n    - 3\n  c: 3\nother: 1\n")
check(commented.value("a/b")?.scalar == "x # y", "quoted key, # inside quotes")
check(commented.value("list")?.listValue?.compactMap(\.scalar) == ["1", "3"], "block list with a blank line and a comment")
try! commented.set("a/b", .scalar("z"))
try! commented.set("list", .strings(["9"]))
try! commented.set("d", .bool(true))
check(commented.text == "# head\npatch:\n  # about a\n  \"a/b\": z  # note\n# column 0 comment\n  list:\n    - 9\n  c: 3\n  d: true\nother: 1\n",
      "keeps key spelling and comment; replaces the block; adds before the next top-level key", commented.text)

var empty = PatchDocument(text: "")
try! empty.set("menu/page_size", .int(7))
check(empty.text == "\npatch:\n  menu/page_size: 7\n" || empty.text == "patch:\n  menu/page_size: 7\n", "creates the patch map", empty.text)
var inline = PatchDocument(text: "patch: {}\n")
try! inline.set("a", .int(1))
check(inline.text == "patch:\n  a: 1\n", "patch: {} becomes a block", inline.text)
check((try? PatchDocument(text: "patch: { a: 1 }\n").entries()) == nil, "refuses an inline patch with entries")
var top = PatchDocument(text: "installation_id: \"x\"\nrime_version: 1.17.0\n", topLevel: true)
try! top.set("sync_dir", .scalar("/Users/me/iCloud Drive/Rime"))
check(top.value("sync_dir")?.scalar == "/Users/me/iCloud Drive/Rime" && top.value("installation_id")?.scalar == "x", "top-level keys")
try! top.remove("sync_dir")
check(top.text == "installation_id: \"x\"\nrime_version: 1.17.0\n", "removes a top-level key")

// MARK: - Settings on a copy of the user folder

let sandbox = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
RimePaths.userDir = sandbox
RimePaths.backupDir = sandbox.deletingLastPathComponent().appending(component: "backups")
print("== settings in \(sandbox.path)")
MainActor.assumeIsolated {
  let store = SettingsStore()
  store.deploysAfterSaving = false

  check(store.int(store.defaults, "menu/page_size") == 5 && store.enabledSchemas == ["rime_ice"], "reads page size and schemas")
  check(store.look == .liquidGlass && store.fontFamily == "PingFang SC" && store.highlightWeight == "medium", "reads the look and fonts")
  check(store.isPaging(.minusEqual) && !store.isPaging(.commaPeriod), "reads paging keys")

  // Which saves Squirrel applies by reloading only its look, without restarting Rime
  check(!store.onlyLookChanged, "nothing changed: nothing to reload")
  // Whatever the user's copy says now.
  let radius = store.int(store.squirrel, "style/corner_radius") ?? 18
  let pageSize = store.int(store.defaults, "menu/page_size") ?? 5
  let statusIcon = store.bool(store.squirrel, "status_icon/show") ?? true
  store.set(store.squirrel, "style/corner_radius", .int(radius + 3))
  store.set(store.squirrel, "status_icon/show", .bool(!statusIcon))
  check(store.onlyLookChanged && store.squirrel.changedKeys == ["style/corner_radius", "status_icon/show"], "style and the status icon: only the look",
        "\(store.squirrel.changedKeys)")
  store.set(store.squirrel, "app_options/com.example.editor/ascii_mode", .bool(true))
  check(!store.onlyLookChanged, "app options need a deploy (Squirrel applies them to new input sessions)")
  store.set(store.squirrel, "app_options/com.example.editor/ascii_mode", nil)
  store.set(store.defaults, "menu/page_size", .int(pageSize + 4))
  check(!store.onlyLookChanged, "a change in default.custom.yaml needs a deploy")
  store.set(store.defaults, "menu/page_size", .int(pageSize))
  store.set(store.squirrel, "status_icon/show", .bool(statusIcon))
  store.set(store.squirrel, "style/corner_radius", .int(radius))
  check(!store.squirrel.isDirty && !store.defaults.isDirty && store.squirrel.changedKeys.isEmpty, "changed back: nothing to save")
  check(SettingsStore.isLookKey("style/scroll_mode/max_rows") && SettingsStore.isLookKey("preset_color_schemes/mine/name")
        && !SettingsStore.isLookKey("app_options/com.apple.Terminal/ascii_mode") && !SettingsStore.isLookKey("unsafe/report_bundleid"),
        "look keys")

  store.set(store.squirrel, "style/label_font_point", .int(15))
  check(store.squirrel.isPatched("style/label_font_point"), "a value the base does not have is written")
  store.set(store.squirrel, "style/font_point", .int(17))
  store.set(store.squirrel, "style/font_point", .int(16))
  check(store.squirrel.isPatched("style/font_point"), "the user's line stays when it comes back to the base's value (16)")
  store.set(store.squirrel, "style/show_paging", .bool(false))
  check(!store.squirrel.isPatched("style/show_paging"), "a value equal to the base is not written")

  store.setPaging(.commaPeriod, true)
  check(store.isPaging(.commaPeriod) && store.defaults.isPatched("key_binder/bindings"), "turns on , . paging")
  store.setPaging(.commaPeriod, false)
  check(!store.isPaging(.commaPeriod) && !store.defaults.isPatched("key_binder/bindings"), "turning it off again drops the patch")
  store.setPaging(.commaPeriod, true)

  store.set(store.defaults, "menu/page_size", .int(7))
  let pageSizeLine = store.defaults.document.lines.firstIndex { $0.contains("menu/page_size") }
  check(pageSizeLine.map { store.defaults.document.lines[$0 - 1].contains("每页候选数") } == true, "a changed entry stays under its comment")
  store.setEnabledSchemas(["rime_ice", "double_pinyin_flypy"])
  check(store.iceSchemas == ["rime_ice", "double_pinyin_flypy"], "rime-ice schemas include enabled 双拼")

  let zh = SettingsStore.fuzzyRules[0]
  store.setFuzzy(zh, true)
  check(store.isFuzzy(zh) && store.strings(store.schema("double_pinyin_flypy"), "speller/algebra").first == zh.rules[0], "fuzzy rules go first, in both schemas")
  store.setFuzzy(SettingsStore.fuzzyRules[1], true)
  store.setFuzzy(SettingsStore.fuzzyRules[1], false)
  check(store.isFuzzy(zh) && !store.isFuzzy(SettingsStore.fuzzyRules[1]), "others stay as they are")

  check(store.switchDefault("emoji") == 1 && store.switchDefault("traditionalization") == 0, "reads switch defaults")
  store.setSwitchDefault("emoji", 0)
  check(store.switchDefault("emoji") == 0 && store.schema("rime_ice").isPatched("switches/@3/reset"), "sets emoji off by index")
  store.setSwitchDefault("traditionalization", 0)
  check(!store.schema("rime_ice").isPatched("switches/@2/reset"), "off for a switch without reset keeps the schema's behavior")

  // 中文标点下 / 打成「、」：写进 punctuator/half_shape/+，只加这一项，不动别的标点。
  // 真机的 ~/Library/Rime 可能已经打开过，先关掉，从一个确定的起点开始测
  store.setSlashIsIdea(false)
  check(!store.slashIsIdea, "默认 / 还是 /")
  store.setSlashIsIdea(true)
  let mergeText = store.defaults.document.text
  check(store.slashIsIdea && mergeText.contains("punctuator/half_shape/+:") && mergeText.contains("'/': '、'"),
        "打开后写入 punctuator/half_shape/+ 的 '/': '、'", String(mergeText.suffix(80)))
  store.setSlashIsIdea(false)
  check(!store.slashIsIdea && store.defaults.document.entry("punctuator/half_shape/+") == nil,
        "关掉后整项删掉，没留下空映射")
  store.setSlashIsIdea(true)
  // 用户自己写在同一个合并项里的别的标点要留着
  store.defaults.editDocument { try? $0.addMemberLine(to: "punctuator/half_shape/+", "'|': '｜'") }
  store.setSlashIsIdea(false)
  let kept = store.defaults.document.text
  check(!store.slashIsIdea && kept.contains("'|': '｜'") && !store.defaults.document.text.contains("'/'"),
        "删掉 / 那一行，用户自己的 | 留着", String(kept.suffix(60)))
  store.setSlashIsIdea(true)

  // 用户可能把以词定字设成「不使用」，所以先记下当前值再换回去
  let selectKeys = store.selectCharacterKeys
  store.setSelectCharacterKeys(.commaPeriod)
  check(store.selectCharacterKeys == .commaPeriod, "以词定字换成 , 和 .")
  store.setSelectCharacterKeys(selectKeys)
  check(store.selectCharacterKeys == selectKeys, "以词定字换回原来的：\(selectKeys?.title ?? "不使用")")

  store.setSwitchKey(.rightShift, "commit_text")
  store.setHotkey("F4", false)
  check(store.switchKey(.rightShift) == "commit_text" && !store.hotkeys.contains("F4"), "switch keys and hotkeys")

  let appsBefore = store.apps.count
  store.addApp("com.example.Editor")
  store.setAppOption("com.apple.Terminal", "ascii_mode", false)
  check(store.apps.count == appsBefore + 1 && store.apps.first { $0.id == "com.apple.Terminal" }?.options["ascii_mode"] == false, "adds an app, turns an option off")
  store.removeApp("com.apple.dt.Xcode")
  check(!store.apps.contains { $0.id == "com.apple.dt.Xcode" }, "removes an app that Squirrel lists")

  // Squirrel ships presets for many apps nobody has installed; they stay out of the list (and out
  // of squirrel.custom.yaml) until the app is here or the user asks for it.
  check(store.isAppListed("com.github.atom", installed: true), "an installed app is listed, preset or not")
  check(!store.isAppListed("org.gnu.Emacs", installed: false), "an uninstalled preset nobody touched stays off the page")
  check(store.isAppListed("com.example.Editor", installed: false), "an app the user added stays on the page, installed or not")
  store.setAppOption("org.gnu.Emacs", "vim_mode", true)
  check(store.isAppListed("org.gnu.Emacs", installed: false), "a preset the user changed stays too")
  check(store.squirrel.document.text.contains("org.gnu.Emacs"), "it is written to squirrel.custom.yaml")

  store.setLook(.native)
  store.applyRecommendedLook()
  check(store.look == .liquidGlass, "recommended look")

  // An unfinished phrase (added, never filled in) keeps custom_phrase.txt from saving, on purpose;
  // the store should say so (incompletePhrases), not just sit "dirty" forever like a stuck save.
  let draft = Phrase(text: "", code: "")
  store.phrases.add(draft)
  store.changed()
  check(store.incompletePhrases == 1 && store.hasUnsavedChanges, "an unfinished phrase blocks saving and says so")
  store.phrases.remove([draft.id])
  store.changed()
  check(store.incompletePhrases == 0, "removing it clears the block")

  // The toolbar shows whether the changes are on disk. That depends on the views being told
  // about it: hasUnsavedChanges reads `revision`, which only changed() bumps — a save that
  // writes the files out has to bump it too, or the toolbar keeps saying 「保存中…」.
  let revisionBefore = store.revision
  store.set(store.squirrel, "style/glass_style", .scalar("clear"))
  check(store.revision > revisionBefore && store.hasUnsavedChanges, "a change marks the store dirty")
  store.saveNow()
  check(!store.hasUnsavedChanges, "saving writes the files out")
  check(store.revision > revisionBefore + 1, "and tells the views about it", "rev=\(store.revision)")

  let phraseCount = store.phrases.phrases.count
  store.phrases.add(Phrase(text: "测试短语", code: "cshi", weight: "100"))
  store.setSyncDir(sandbox.appending(component: "sync-test").path)
  store.saveNow()
  check(store.saveError == nil && !store.hasUnsavedChanges, "saves", store.saveError ?? "")
  check(PhraseBook(url: sandbox.appending(component: "custom_phrase.txt")).phrases.count == phraseCount + 1, "the phrase is in custom_phrase.txt")
  for name in ["squirrel.custom.yaml", "default.custom.yaml", "rime_ice.custom.yaml", "double_pinyin_flypy.custom.yaml", "installation.yaml"] {
    let text = (try? String(contentsOf: sandbox.appending(component: name), encoding: .utf8)) ?? ""
    check(RimeYAML.isValid(text) && !text.isEmpty, "\(name) is valid YAML")
  }
}

// MARK: - Installing rime-ice

print("== installer output")
check(abs((RimeIceInstaller.progress(in: "################                                   42.3%") ?? -1) - 0.423) < 1e-9, "reads curl's bar")
check(RimeIceInstaller.progress(in: "                                                                0.0%") == 0, "reads curl's empty bar")
check(RimeIceInstaller.progress(in: "#=#=#                ") == nil && RimeIceInstaller.progress(in: "下载：x 5%") == nil, "not a bar")
check(RimeIceInstaller.explain(status: 7, log: ["下载：x", "curl: (7) Failed to connect to github.com port 443"]).hasPrefix("连不上 GitHub"), "explains a connection failure")
check(RimeIceInstaller.explain(status: 22, log: ["curl: (22) The requested URL returned error: 404"]).hasPrefix("下载失败"), "explains a server error")
check(RimeIceInstaller.explain(status: 1, log: ["解压：x", "压缩包里没有 rime_ice.schema.yaml，内容不对"]) == "安装没有完成：压缩包里没有 rime_ice.schema.yaml，内容不对", "explains a script error")

/// Set when an async test is done; the run loop turns meanwhile.
final class Flag: @unchecked Sendable {
  var value = false
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iceZip = root.appending(components: ".cache", "rime-ice", "full.zip")
if FileManager.default.fileExists(atPath: iceZip.path) {
  let manager = FileManager.default
  let work = sandbox.deletingLastPathComponent().appending(component: "ice")
  let folder = work.appending(component: "Rime")
  print("== installing rime-ice into \(folder.path)")
  try? manager.removeItem(at: work)
  try! manager.createDirectory(at: folder, withIntermediateDirectories: true)
  try! manager.createDirectory(at: work.appending(component: "cache"), withIntermediateDirectories: true)
  try! manager.copyItem(at: iceZip, to: work.appending(components: "cache", "full.zip"))
  let defaultsURL = folder.appending(component: "default.custom.yaml")
  let phrasesURL = folder.appending(component: "custom_phrase.txt")
  let phrases = "# 我的短语\n测试安装\tcsaz\t1\n"
  try! "patch:\n  schema_list:\n    - schema: rime_ice\n  menu/page_size: 6\n".write(to: defaultsURL, atomically: true, encoding: .utf8)
  try! phrases.write(to: phrasesURL, atomically: true, encoding: .utf8)
  RimePaths.userDir = folder
  RimePaths.backupDir = work.appending(component: "backups")
  RimeIceInstaller.script = root.appending(components: "scripts", "rime-ice.sh")
  RimeIceInstaller.templates = root.appending(component: "rime")
  RimeIceInstaller.cacheDir = work.appending(component: "cache")
  MainActor.assumeIsolated {
    let store = SettingsStore()
    store.deploysAfterSaving = false
    check(!store.iceInstalled && store.missingSchemas == ["rime_ice"] && store.typesOnlyEnglish, "rime_ice enabled but not there: English only")
    try! "patch:\n  schema_list:\n    - schema: luna_pinyin\n  menu/page_size: 6\n".write(to: defaultsURL, atomically: true, encoding: .utf8)
    store.reloadChangedFiles()
    check(store.enabledSchemas == ["luna_pinyin"] && store.missingSchemas.isEmpty && !store.typesOnlyEnglish, "picks up a schema list edited elsewhere")
    let sharedBase = store.defaults.baseURL

    let done = Flag()
    Task { @MainActor in
      await store.installRimeIce(from: .cache)
      done.value = true
    }
    let start = Date()
    while !done.value && Date().timeIntervalSince(start) < 120 {
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    check(store.iceInstaller.phase == .finished, "installs (\(String(format: "%.1f", Date().timeIntervalSince(start))) s)",
          "\(store.iceInstaller.phase) " + store.iceInstaller.log.suffix(4).joined(separator: " | "))
    check(store.iceInstalled && store.iceVersion != nil && store.mainIceSchema == "rime_ice", "rime-ice is there, version \(store.iceVersion ?? "?")")
    check(store.iceInstaller.summary?.hasPrefix("已安装雾凇拼音") == true, "says so: \(store.iceInstaller.summary ?? "")")
    check(store.enabledSchemas == ["rime_ice", "luna_pinyin"], "rime_ice becomes the default, luna_pinyin stays", "\(store.enabledSchemas)")
    check(store.defaults.baseURL?.deletingLastPathComponent().path == folder.path && store.defaults.baseURL != sharedBase,
          "default.custom.yaml now patches rime-ice's default.yaml", store.defaults.baseURL?.path ?? "nil")
    check(store.int(store.defaults, "menu/page_size") == 6, "the user's page size stays")
    check((try? String(contentsOf: phrasesURL, encoding: .utf8)) == phrases, "the user's custom_phrase.txt stays")
    for name in ["squirrel.yaml", "weasel.yaml", "LICENSE"] {
      check(!manager.fileExists(atPath: folder.appending(component: name).path), "rime-ice's \(name) is not installed")
    }
    check(manager.fileExists(atPath: folder.appending(component: "squirrel.custom.yaml").path), "the ohmyrime template fills in squirrel.custom.yaml")
    // ohmyrime only ships two 默认英文 presets (Squirrel's own list has many more, for apps most
    // people do not have); its own bug workarounds (not about default typing mode) are untouched.
    check(store.bool(store.squirrel, "app_options/com.apple.Safari/ascii_mode") == true, "adds a Safari preset")
    check(store.bool(store.squirrel, "app_options/com.apple.Terminal/ascii_mode") == true
          && store.bool(store.squirrel, "app_options/com.apple.Terminal/no_inline") == true, "keeps Squirrel's own Terminal preset")
    check(!store.apps.contains { $0.id == "com.github.atom" } && !store.apps.contains { $0.id == "org.gnu.Emacs" },
          "turns off the other default-ascii presets")
    check(store.bool(store.squirrel, "app_options/com.google.Chrome/inline") == true, "a bug workaround, not a preference, stays")
    let backups = (try? manager.subpathsOfDirectory(atPath: RimePaths.backupDir.path)) ?? []
    check(backups.contains { $0.hasSuffix(".tar.gz") }, "backs the folder up first", backups.joined(separator: ", "))
    check(!manager.fileExists(atPath: work.appending(components: "cache", "full").path)
          && manager.fileExists(atPath: work.appending(components: "cache", "full.zip").path), "keeps the download, not what was unpacked")
    check(!store.hasUnsavedChanges && RimeYAML.isValid((try? String(contentsOf: defaultsURL, encoding: .utf8)) ?? ""), "saved, valid YAML")

    // Old backups of the whole folder go, the newest three stay; file backups are not touched.
    let backupRoot = RimePaths.backupDir
    for (index, folder) in ["20260101-000001", "20260101-000002", "20260101-000003", "20260101-000004"].enumerated() {
      try? manager.createDirectory(at: backupRoot.appending(component: folder), withIntermediateDirectories: true)
      try? Data().write(to: backupRoot.appending(components: folder, "Rime-\(index).tar.gz"))
    }
    try? Data().write(to: backupRoot.appending(components: "20260101-000001", "squirrel.custom.yaml"))
    ConfigFile.pruneFolderBackups(keeping: 3)
    let left = ((try? manager.contentsOfDirectory(atPath: backupRoot.path)) ?? []).sorted()
    let archives = left.flatMap { folder in
      ((try? manager.contentsOfDirectory(atPath: backupRoot.appending(component: folder).path)) ?? []).filter { $0.hasSuffix(".tar.gz") }
    }
    check(archives.count == 3 && !archives.contains("Rime-0.tar.gz") && !archives.contains("Rime-1.tar.gz"),
          "keeps the newest three folder backups", archives.joined(separator: ", "))
    check(manager.fileExists(atPath: backupRoot.appending(components: "20260101-000001", "squirrel.custom.yaml").path)
          && !manager.fileExists(atPath: backupRoot.appending(component: "20260101-000002").path),
          "a folder with other backups stays, an empty one goes", left.joined(separator: ", "))
  }
} else {
  print("== installing rime-ice: skipped (no .cache/rime-ice/full.zip yet: run scripts/rime-ice.sh once)")
}

// MARK: - Installing ohmyrime

print("== installing ohmyrime")
let carried = "aaa"
check(SquirrelStatus.of(installedHash: nil, carriedHash: carried, marker: nil, version: "0.2.0") == .missing, "not installed")
check(SquirrelStatus.of(installedHash: "aaa", carriedHash: carried, marker: nil, version: "0.2.0") == .current, "the one the app carries")
check(SquirrelStatus.of(installedHash: "bbb", carriedHash: carried, marker: nil, version: "0.2.0") == .other, "another build: installing replaces it")
check(SquirrelStatus.of(installedHash: "bbb", carriedHash: carried, marker: InstallMarker(version: "0.10.0", squirrelHash: "bbb"), version: "0.9.0") == .newer,
      "installed by a newer ohmyrime (0.10.0 > 0.9.0): left alone")
check(SquirrelStatus.of(installedHash: "bbb", carriedHash: carried, marker: InstallMarker(version: "0.1.0", squirrelHash: "bbb"), version: "0.2.0") == .other,
      "installed by an older one: an update")
check(SquirrelStatus.of(installedHash: "ccc", carriedHash: carried, marker: InstallMarker(version: "0.3.0", squirrelHash: "bbb"), version: "0.2.0") == .other,
      "replaced since (the official Squirrel, say): the record does not count")
check(SquirrelStatus.of(installedHash: "bbb", carriedHash: nil, marker: nil, version: "0.2.0") == .current, "built without the payload: nothing to offer")
let weType: [String: Any] = ["Bundle ID": "com.tencent.inputmethod.wetype", "InputSourceKind": "Keyboard Input Method"]
let squirrelMode: [String: Any] = ["Bundle ID": "im.rime.inputmethod.Squirrel", "Input Mode": "im.rime.inputmethod.Squirrel.Hans", "InputSourceKind": "Input Mode"]
check(InputSourceRecord.hasSquirrel([weType, squirrelMode]) == true, "finds Squirrel among the added input sources")
check(InputSourceRecord.hasSquirrel([weType]) == false && InputSourceRecord.hasSquirrel(nil) == nil, "not there; no list at all")
check(ScriptRunner.explain(status: 1, log: ["==> 安装鼠须管", "0:157: execution error: 用户已取消。 (-128)"]) == "没有输入管理员密码，已取消。",
      "explains a password dialog cancelled")
check(ScriptRunner.explain(status: 1, log: ["==> 安装鼠须管", "未找到鼠须管"]) == "未找到鼠须管", "or says the last line")
let markerFile = sandbox.deletingLastPathComponent().appending(component: "installed.json")
// As install.sh writes it.
try? #"{"version": "0.2.0", "squirrelHash": "abc", "date": "2026-10-20T08:00:00Z"}"#.write(to: markerFile, atomically: true, encoding: .utf8)
check(InstallMarker.read(markerFile) == InstallMarker(version: "0.2.0", squirrelHash: "abc", date: "2026-10-20T08:00:00Z"), "reads install.sh's record")

let script = sandbox.deletingLastPathComponent().appending(component: "steps.sh")
try? "echo '==> 第一步'\necho 细节\necho '==> 第二步' >&2\nprintf 'no line end'\nexit 3\n".write(to: script, atomically: true, encoding: .utf8)
MainActor.assumeIsolated {
  let runner = ScriptRunner()
  let done = Flag()
  Task { @MainActor in
    _ = await runner.run(script)
    done.value = true
  }
  let start = Date()
  while !done.value && Date().timeIntervalSince(start) < 20 {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
  }
  check(runner.steps == ["第一步", "第二步"] && runner.log == ["==> 第一步", "细节", "==> 第二步", "no line end"], "runs a script: steps from both streams, the last line too",
        "\(runner.steps) \(runner.log)")
  check(runner.failure == "no line end", "fails with its exit status, says why", runner.failure ?? "nil")
}

// MARK: - Update check

print("== update check")
check(UpdateCheck.isNewer("v0.10.0", than: "0.9.9") == true, "0.10.0 比 0.9.9 新（按数字比，不按字符串）")
check(UpdateCheck.isNewer("0.2.0", than: "v0.2.0") == false, "补上 v 之后一样新")
check(UpdateCheck.isNewer("0.2.0-beta.3", than: "0.2.0") == false, "1.2.0-beta 和 1.2.0 一样")
check(UpdateCheck.isNewer("0.1.9", than: "0.2") == false, "0.1.9 比 0.2 旧")
check(UpdateCheck.isNewer("abc", than: "0.2.0") == nil, "读不出来的版本号返回 nil")
check(UpdateCheck.versionsMatch("0.2", "0.2.0") && !UpdateCheck.versionsMatch("0.2.1", "0.2.0"), "0.2 和 0.2.0 是同一版")
check(UpdateCheck.stripPrefix(" v0.2.0 ") == "0.2.0", "去掉 v 和空格")
let redirected = URL(string: "https://github.com/tarnish233/ohmyrime/releases/tag/v0.2.0")!
let release = UpdateCheck.release(fromRedirect: redirected)
check(release?.version == "v0.2.0" && release?.shortVersion == "0.2.0", "从最新发布的重定向里读出 v0.2.0")
check(UpdateCheck.release(fromRedirect: URL(string: "https://github.com/someone/else/releases/tag/v9.9.9")!) == nil,
      "别的仓库的重定向不认")
check(UpdateCheck.release(fromRedirect: URL(string: "http://github.com/tarnish233/ohmyrime/releases/tag/v0.3.0")!) == nil,
      "不是 https 的不认")
check(UpdateCheck.release(fromRedirect: URL(string: "https://github.com/tarnish233/ohmyrime/releases/tag/nightly")!) == nil,
      "不是版本号的标签不认")
check(UpdateCheck.assetURL("ohmyrime.zip")?.absoluteString == "https://github.com/tarnish233/ohmyrime/releases/latest/download/ohmyrime.zip",
      "发布包地址用 latest/download，文件名不带版本号")
check(UpdateCheck.parseChecksum("711658b5a0b7414b92bf4e720b59a42e02900b5fb65a4c2641a9589c36434fba  ohmyrime.zip\n")
        == "711658b5a0b7414b92bf4e720b59a42e02900b5fb65a4c2641a9589c36434fba", "读 shasum 的输出")
check(UpdateCheck.parseChecksum("不是校验值") == nil, "不是校验值就不认")
check(UpdateCheck.describe(URLError(.notConnectedToInternet)) == "没有网络"
        && UpdateCheck.describe(URLError(.timedOut)) == "连接 GitHub 超时", "网络错误的说明")

// MARK: - The fallback save

print("== the fallback save")
MainActor.assumeIsolated {
  let store = SettingsStore()
  store.deploysAfterSaving = false
  // A change that does not get written out on its own: the app is suspended, or the wait for
  // Squirrel's answer never ends. The fallback writes it out anyway, so the toolbar cannot say
  // 「保存中…」 forever.
  SettingsStore.fallbackDelay = 0.2
  let url = RimePaths.userDir.appending(component: "squirrel.custom.yaml")
  let before = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
  store.set(store.squirrel, "style/glass_style", .scalar("clear"))
  check(store.hasUnsavedChanges, "the change is not on disk yet")
  let deadline = Date().addingTimeInterval(3)
  while store.hasUnsavedChanges && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
  }
  check(!store.hasUnsavedChanges, "the fallback wrote it out")
  let after = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
  check(after != before && after.contains("glass_style"), "and the file really changed", String(after.suffix(40)))
  SettingsStore.fallbackDelay = 10
}

// MARK: - The deploy status

print("== deploy status")
MainActor.assumeIsolated {
  let deployer = Deployer()
  check(deployer.state == .idle && !deployer.isSlow, "nothing deployed yet")
  // The slow marker is what the toolbar shows after a while, so the user gets 「重新部署」
  // instead of waiting for the 45 s timeout. The test only starts the timer: asking the real
  // Squirrel to deploy would really deploy the user's configuration.
  Deployer.slowThreshold = 0.2
  deployer.startSlowTimer()
  check(!deployer.isSlow, "not slow yet")
  let deadline = Date().addingTimeInterval(3)
  while !deployer.isSlow && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
  }
  check(deployer.isSlow, "taking longer than usual: the toolbar says so")
  Deployer.slowThreshold = 8
}

print("")
print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
