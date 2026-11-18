import Foundation
public struct LayoutExport: Codable, Sendable {
    public var schemaVersion = 1
    public var layout: Layout
    public var applications: [AppHint]
    public struct AppHint: Codable, Sendable {
        public var id: UUID
        public var bundleID: String?
        public var name: String
    }
    public init(layout: Layout, records: [AppRecord]) {
        self.layout = layout
        for i in self.layout.folders.indices { self.layout.folders[i].sourceDirectory = nil }
        applications = records.filter { layout.flattened.contains($0.id) }.map { AppHint(id: $0.id, bundleID: $0.bundleID, name: $0.name) }
    }
    public static func decode(_ data: Data) throws -> LayoutExport {
        guard data.count <= 5 * 1024 * 1024 else { throw LayoutError.invalid("导入文件超过 5 MB") }
        let export = try JSONDecoder().decode(Self.self, from: data)
        guard export.schemaVersion == 1, export.applications.count <= 10000, Set(export.applications.map(\.id)).count == export.applications.count else { throw LayoutError.invalid("导入版本或应用引用无效") }
        try LayoutEngine.validate(export.layout)
        guard Set(export.layout.flattened).isSubset(of: Set(export.applications.map(\.id))) else { throw LayoutError.invalid("导入缺少应用身份提示") }
        return export
    }
    public func resolve(current: [AppRecord], revision: UInt64) throws -> (Layout, [AppRecord], Int) {
        var mapping: [UUID: UUID] = [:], records = current, used = Set<UUID>(), missing = 0
        for hint in applications {
            let candidates = current.filter { !used.contains($0.id) && $0.bundleID == hint.bundleID && $0.name == hint.name && hint.bundleID != nil }
            if candidates.count == 1 { mapping[hint.id] = candidates[0].id; used.insert(candidates[0].id) }
            else {
                let id = UUID(); mapping[hint.id] = id; var placeholder = AppRecord(id: id, path: "", bundleID: hint.bundleID, name: hint.name); placeholder.missingSince = Date(); records.append(placeholder); missing += 1
            }
        }
        var result = layout
        result.root = layout.root.map { if case .app(let id) = $0 { return .app(mapping[id]!) }; return $0 }
        for i in result.folders.indices { result.folders[i].apps = layout.folders[i].apps.map { mapping[$0]! } }
        result.hidden = Set(layout.hidden.compactMap { mapping[$0] }); result.revision = revision + 1
        let contained = Set(result.flattened)
        result.root += current.filter { !contained.contains($0.id) }.map { .app($0.id) }
        try LayoutEngine.validate(result); return (result, records, missing)
    }
}
