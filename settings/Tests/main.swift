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
check(keys.count == 23 && keys.first == "style/candidate_list_layout", "reads the template's \(keys.count) entries")
check(patch.value("style/border_width")?.doubleValue == 9.5 && patch.value("style/font_face")?.scalar == "PingFang SC", "reads values")
try! patch.set("style/font_point", .int(18))
try! patch.set("style/new_key", .scalar("a b"))
try! patch.remove("style/motion")
let changedLines = zip(template.components(separatedBy: "\n"), patch.text.components(separatedBy: "\n")).filter { $0 != $1 }
check(patch.value("style/font_point")?.intValue == 18 && patch.text.contains("  style/font_point: 18\n"), "replaces a value in place")
check(patch.text.contains("  style/new_key: 'a b'\n") && !patch.text.contains("style/motion:"), "adds after the last entry, removes")
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

  store.setSelectCharacterKeys(.commaPeriod)
  store.setSelectCharacterKeys(.brackets)
  check(store.selectCharacterKeys == .brackets && !store.defaults.isPatched("key_binder/select_first_character"), "以词定字 back to [ ] drops the patch")

  store.setSwitchKey(.rightShift, "commit_text")
  store.setHotkey("F4", false)
  check(store.switchKey(.rightShift) == "commit_text" && !store.hotkeys.contains("F4"), "switch keys and hotkeys")

  let appsBefore = store.apps.count
  store.addApp("com.example.Editor")
  store.setAppOption("com.apple.Terminal", "ascii_mode", false)
  check(store.apps.count == appsBefore + 1 && store.apps.first { $0.id == "com.apple.Terminal" }?.options["ascii_mode"] == false, "adds an app, turns an option off")
  store.removeApp("com.apple.dt.Xcode")
  check(!store.apps.contains { $0.id == "com.apple.dt.Xcode" }, "removes an app that Squirrel lists")

  store.setLook(.native)
  store.applyRecommendedLook()
  check(store.look == .liquidGlass, "recommended look")

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

print("")
print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
