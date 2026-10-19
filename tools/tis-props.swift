// Lists input sources (TIS) whose ID contains one of the arguments, with their state. Read-only.
//   swiftc tools/tis-props.swift -o build/tis-props && build/tis-props rime
import Carbon
import Foundation

let patterns = CommandLine.arguments.dropFirst().map { $0.lowercased() }
func prop<T>(_ source: TISInputSource, _ key: CFString) -> T? {
  guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
  return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? T
}
func flag(_ source: TISInputSource, _ key: CFString) -> String {
  (prop(source, key) as Bool?).map { $0 ? "Y" : "n" } ?? "-"
}
for includeAll in [false, true] {
  let list = TISCreateInputSourceList(nil, includeAll).takeRetainedValue() as! [TISInputSource]
  print(includeAll ? "== all installed (includeAllInstalled = true)" : "== enabled (includeAllInstalled = false)")
  for source in list {
    let id: String = prop(source, kTISPropertyInputSourceID) ?? "?"
    guard patterns.isEmpty || patterns.contains(where: { id.lowercased().contains($0) }) else { continue }
    let name: String = prop(source, kTISPropertyLocalizedName) ?? "?"
    let type: String = prop(source, kTISPropertyInputSourceType) ?? "?"
    let bundle: String = prop(source, kTISPropertyBundleID) ?? "-"
    print("\(id)  name=\(name)  type=\(type.replacingOccurrences(of: "TISType", with: ""))  bundle=\(bundle)  enableCapable=\(flag(source, kTISPropertyInputSourceIsEnableCapable)) selectCapable=\(flag(source, kTISPropertyInputSourceIsSelectCapable)) enabled=\(flag(source, kTISPropertyInputSourceIsEnabled)) selected=\(flag(source, kTISPropertyInputSourceIsSelected))")
  }
}
