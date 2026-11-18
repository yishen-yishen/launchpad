import Foundation
public actor PersistenceService {
    public let directory: URL
    private var savedRevision: UInt64?
    public init(directory: URL) { self.directory = directory }
    private func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    private func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
    public func load() throws -> (Layout, CatalogSnapshot, String?) {
        let fm = FileManager.default; try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let catalogURL = directory.appendingPathComponent("catalog.json")
        var catalog = (try? decoder().decode(CatalogSnapshot.self, from: Data(contentsOf: catalogURL))) ?? CatalogSnapshot()
        let url = directory.appendingPathComponent("layout.json")
        guard fm.fileExists(atPath: url.path) else { return (Layout(), catalog, nil) }
        let data = try Data(contentsOf: url)
        if let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let version = raw["schemaVersion"] as? Int, version > 1 { throw LayoutError.invalid("布局来自更新版本；禁止覆盖，请升级应用") }
        do { let d = try decoder().decode(Layout.self, from: data); try LayoutEngine.validate(d)
            let known = Set(catalog.records.map(\.id))
            for id in d.flattened where !known.contains(id) { var placeholder = AppRecord(id: id, path: "", name: "应用不可用"); placeholder.missingSince = Date(); catalog.records.append(placeholder) }
            return (d, catalog, nil) }
        catch {
            for n in 1...3 {
                if let bytes = try? Data(contentsOf: directory.appendingPathComponent("layout.backup\(n).json")), let d = try? decoder().decode(Layout.self, from: bytes), (try? LayoutEngine.validate(d)) != nil {
                    try data.write(to: directory.appendingPathComponent("layout.corrupt-\(UUID()).json"), options: .atomic)
                    return (d, catalog, "已从备份恢复布局，损坏原件已保留")
                }
            }
            throw LayoutError.invalid("布局损坏且无有效备份。原文件已保留；请恢复备份或导入布局。")
        }
    }
    public func save(_ layout: Layout, catalog: CatalogSnapshot) throws {
        guard savedRevision == nil || layout.revision >= savedRevision! else { return }
        try LayoutEngine.validate(layout)
        let fm = FileManager.default; try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("layout.json")
        if let data = try? Data(contentsOf: target), let old = try? decoder().decode(Layout.self, from: data), (try? LayoutEngine.validate(old)) != nil, old.revision != layout.revision {
            for n in stride(from: 3, through: 2, by: -1) {
                if let previous = try? Data(contentsOf: directory.appendingPathComponent("layout.backup\(n-1).json")) { try previous.write(to: directory.appendingPathComponent("layout.backup\(n).json"), options: .atomic) }
            }
            try data.write(to: directory.appendingPathComponent("layout.backup1.json"), options: .atomic)
        }
        try encoder().encode(catalog).write(to: directory.appendingPathComponent("catalog.json"), options: .atomic)
        try encoder().encode(layout).write(to: target, options: .atomic)
        savedRevision = layout.revision
    }
}
