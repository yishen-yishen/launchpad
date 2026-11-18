import Foundation
let paths = CommandLine.arguments.count > 1 ? Array(CommandLine.arguments.dropFirst()) : [
    "/System/Applications/Utilities/Terminal.app",
    "/Applications/Visual Studio Code.app",
    "/Applications/WeChat.app",
    "/Applications/ChatGPT.app"
]
let fm = FileManager.default
let rows: [[String: String]] = paths.compactMap { path in
    let url = URL(fileURLWithPath: path)
    guard let bundle = Bundle(url: url) else { return nil }
    let finder = fm.displayName(atPath: path)
    func label(_ s: String) -> String { s.lowercased().hasSuffix(".app") ? String(s.dropLast(4)) : s }
    func value(_ source: [String: Any]?, _ key: String) -> String { source?[key] as? String ?? "—" }
    var chinese: [String: Any] = [:]
    for locale in ["zh-Hans", "zh_CN", "zh-Hans_CN"] {
        let file = bundle.bundleURL.appendingPathComponent("Contents/Resources/\(locale).lproj/InfoPlist.strings")
        if let bytes = try? Data(contentsOf: file), let strings = (try? PropertyListSerialization.propertyList(from: bytes, format: nil)) as? [String: Any] { chinese = strings; break }
    }
    if chinese.isEmpty {
        let file = bundle.bundleURL.appendingPathComponent("Contents/Resources/InfoPlist.loctable")
        if let bytes = try? Data(contentsOf: file), let table = (try? PropertyListSerialization.propertyList(from: bytes, format: nil)) as? [String: Any] {
            chinese = table["zh_CN"] as? [String: Any] ?? table["zh-Hans"] as? [String: Any] ?? [:]
        }
    }
    return [
        "path": path,
        "filename": url.lastPathComponent,
        "filenameWithoutApp": url.deletingPathExtension().lastPathComponent,
        "finderDisplayWithoutApp": label(finder),
        "resourceLocalizedName": (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName ?? "—",
        "raw.CFBundleDisplayName": value(bundle.infoDictionary, "CFBundleDisplayName"),
        "localized.CFBundleDisplayName": value(bundle.localizedInfoDictionary, "CFBundleDisplayName"),
        "effective.CFBundleDisplayName": bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "—",
        "raw.CFBundleName": value(bundle.infoDictionary, "CFBundleName"),
        "localized.CFBundleName": value(bundle.localizedInfoDictionary, "CFBundleName"),
        "effective.CFBundleName": bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "—",
        "zh.CFBundleDisplayName": value(chinese, "CFBundleDisplayName"),
        "zh.CFBundleName": value(chinese, "CFBundleName"),
        "CFBundleExecutable": value(bundle.infoDictionary, "CFBundleExecutable"),
        "CFBundleIdentifier": bundle.bundleIdentifier ?? "—"
    ]
}
let bytes = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
print(String(decoding: bytes, as: UTF8.self))
