import Foundation

public struct AppRecord: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var path: String
    public var bundleID: String?
    public var name: String
    public var bundleName: String
    public var identity: String?
    public var sourceDirectory: String?
    public var sourceDirectoryName: String?
    public var alternateNames: [String]?
    public var missingSince: Date?
    public var label: String {
        guard !path.isEmpty, URL(fileURLWithPath: path).pathExtension.lowercased() == "app" else { return name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
    /// System-owned locations distinguish built-in apps from separately installed
    /// Apple software such as Xcode, Pages or Numbers.
    public var isSystemProvided: Bool {
        let location = URL(fileURLWithPath: path).standardizedFileURL.path
        return location.hasPrefix("/System/Applications/") ||
            location.hasPrefix("/System/Volumes/Preboot/Cryptexes/App/System/Applications/") ||
            (location == "/Applications/Safari.app" && bundleID?.lowercased() == "com.apple.safari")
    }
    public var staysOnInitialRoot: Bool {
        let common = Set(["com.apple.systempreferences", "com.apple.terminal", "com.apple.appstore", "com.apple.safari", "com.apple.preview"])
        return bundleID.map { common.contains($0.lowercased()) } ?? false
    }
    public var inaccessible: Bool = false
    public init(id: UUID = UUID(), path: String, bundleID: String? = nil, name: String, bundleName: String = "", identity: String? = nil) {
        self.id = id; self.path = path; self.bundleID = bundleID; self.name = name; self.bundleName = bundleName; self.identity = identity
    }
}
public enum Item: Codable, Hashable, Sendable {
    case app(UUID), folder(UUID)
    public var id: UUID { switch self { case .app(let id), .folder(let id): id } }
}
public struct Folder: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var apps: [UUID]
    public var sourceDirectory: String?
}
public struct Layout: Codable, Sendable, Equatable {
    public var schemaVersion = 1
    public var revision: UInt64 = 0
    public var root: [Item] = []
    public var folders: [Folder] = []
    public var hidden: Set<UUID> = []
    public var systemAppGroupingVersion: Int?
    public var directoryGroupingVersion: Int?
    public init() {}
    public var flattened: [UUID] { root.flatMap { item in switch item { case .app(let id): [id]; case .folder(let id): folders.first { $0.id == id }?.apps ?? [] } } }
}
public enum LayoutError: Error { case invalid(String) }
public struct LayoutEngine: Sendable {
    public private(set) var document: Layout
    private var undoStack: [Layout] = []
    public init(_ document: Layout = Layout()) { self.document = document }
    public static func validate(_ d: Layout) throws {
        guard d.schemaVersion == 1 else { throw LayoutError.invalid("不支持的布局版本") }
        let ids = d.flattened
        guard ids.count <= 10000, Set(ids).count == ids.count, Set(d.root.map(\.id)).count == d.root.count,
              Set(d.folders.map(\.id)).count == d.folders.count,
              Set(d.root.compactMap { if case .folder(let id) = $0 { return id }; return nil }) == Set(d.folders.map(\.id)),
              d.folders.allSatisfy({ $0.apps.count >= 2 && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 40 }) else { throw LayoutError.invalid("布局引用重复或文件夹无效") }
    }
    public mutating func commit(_ change: (inout Layout) throws -> Void) throws {
        var next = document; try change(&next); Self.normalize(&next); try Self.validate(next)
        guard next != document else { return }
        undoStack.append(document); if undoStack.count > 20 { undoStack.removeFirst() }
        next.revision = document.revision + 1; document = next
    }
    public mutating func reconcile(_ records: [AppRecord]) throws {
        let initializeSystemApps = document.systemAppGroupingVersion == nil && document.root.isEmpty && document.folders.isEmpty
        let ids = Set(records.map(\.id)); var next = document
        next.root.removeAll { if case .app(let id) = $0 { return !ids.contains(id) }; return false }
        for i in next.folders.indices { next.folders[i].apps.removeAll { !ids.contains($0) } }
        Self.normalize(&next)
        let known = Set(next.flattened)
        let added = records.filter { !known.contains($0.id) }
        next.root += added.map { .app($0.id) }
        if initializeSystemApps {
            let members = records.filter { $0.isSystemProvided && !$0.staysOnInitialRoot }.map(\.id)
            if members.count >= 2 {
                let memberIDs = Set(members)
                let index = next.root.firstIndex { memberIDs.contains($0.id) }!
                let folder = Folder(name: "系统工具", apps: members)
                next.root[index] = .folder(folder.id)
                next.root.removeAll { if case .app(let id) = $0 { return memberIDs.contains(id) }; return false }
                next.folders.append(folder)
            }
        }
        if !records.isEmpty { next.systemAppGroupingVersion = 1 }
        let initialGrouping = next.directoryGroupingVersion == nil
        let eligible = Set(initialGrouping ? next.root.compactMap { if case .app(let id) = $0 { return id }; return nil } : added.map(\.id))
        let grouped = Dictionary(grouping: records.filter { eligible.contains($0.id) && $0.sourceDirectory != nil }, by: { $0.sourceDirectory! })
        for directory in grouped.keys.sorted() {
            let members = grouped[directory]!
            let memberIDs = Set(members.map(\.id))
            if let f = next.folders.firstIndex(where: { $0.sourceDirectory == directory }) {
                let ordered = next.root.compactMap { item -> UUID? in if case .app(let id) = item, memberIDs.contains(id) { return id }; return nil }
                next.folders[f].apps += ordered
                next.root.removeAll { if case .app(let id) = $0 { return memberIDs.contains(id) }; return false }
            } else if members.count >= 2, let index = next.root.firstIndex(where: { if case .app(let id) = $0 { return memberIDs.contains(id) }; return false }) {
                let ordered = next.root.compactMap { item -> UUID? in if case .app(let id) = item, memberIDs.contains(id) { return id }; return nil }
                let rawName = (members.first?.sourceDirectoryName ?? URL(fileURLWithPath: directory).lastPathComponent).trimmingCharacters(in: .whitespacesAndNewlines)
                let folder = Folder(name: rawName.isEmpty ? "文件夹" : String(rawName.prefix(40)), apps: ordered, sourceDirectory: directory)
                next.root[index] = .folder(folder.id)
                next.root.removeAll { if case .app(let id) = $0 { return memberIDs.contains(id) }; return false }
                next.folders.append(folder)
            }
        }
        if records.contains(where: { $0.sourceDirectory != nil }) { next.directoryGroupingVersion = 1 }
        next.hidden.formIntersection(ids)
        try Self.validate(next)
        if next != document { next.revision = document.revision + 1; document = next }
    }
    public mutating func undo() { guard var last = undoStack.popLast() else { return }; last.revision = document.revision + 1; document = last }
    public static func remove(_ id: UUID, from d: inout Layout) {
        d.root.removeAll { $0.id == id }
        for i in d.folders.indices { d.folders[i].apps.removeAll { $0 == id } }
    }
    public mutating func move(_ item: Item, into folder: UUID? = nil, at index: Int) throws {
        try commit { d in
            guard d.root.contains(item) || d.flattened.contains(item.id) else { throw LayoutError.invalid("项目不存在") }
            if case .folder = item, folder != nil { throw LayoutError.invalid("不支持嵌套文件夹") }
            Self.remove(item.id, from: &d)
            if let folder {
                guard let f = d.folders.firstIndex(where: { $0.id == folder }) else { throw LayoutError.invalid("文件夹不存在") }
                d.folders[f].apps.insert(item.id, at: min(max(0, index), d.folders[f].apps.count))
            } else { d.root.insert(item, at: min(max(0, index), d.root.count)) }
        }
    }
    public mutating func createFolder(source: UUID, target: UUID) throws {
        try commit { d in
            guard source != target, d.flattened.contains(source), let index = d.root.firstIndex(of: .app(target)) else { throw LayoutError.invalid("建文件夹目标无效") }
            let names = Set(d.folders.map(\.name)); var name = "文件夹"; var suffix = 2
            while names.contains(name) { name = "文件夹 \(suffix)"; suffix += 1 }
            let folder = Folder(name: name, apps: [target, source])
            d.root[index] = .folder(folder.id); Self.remove(source, from: &d); d.folders.append(folder)
        }
    }
    public mutating func rename(_ id: UUID, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { throw LayoutError.invalid("名称须为 1–40 个字符") }
        try commit { d in if let i = d.folders.firstIndex(where: { $0.id == id }) { d.folders[i].name = trimmed } }
    }
    private static func normalize(_ d: inout Layout) {
        for f in d.folders where f.apps.count < 2 {
            if let i = d.root.firstIndex(of: .folder(f.id)) { if let app = f.apps.first { d.root[i] = .app(app) } else { d.root.remove(at: i) } }
        }
        d.folders.removeAll { $0.apps.count < 2 }
    }
}
public struct GridGeometry: Sendable {
    public let columns: Int
    public let rows: Int
    public var capacity: Int { columns * rows }
    public init(width: Double, height: Double, cellWidth: Double = 136, cellHeight: Double = 112, maxRows: Int = 5) {
        columns = max(1, min(7, Int(width / cellWidth)))
        rows = max(1, min(maxRows, Int(height / cellHeight)))
    }
}

/// A folder grows by rows before paging. Row height can compress from 216 to
/// 180 points near the screen limit; the collection uses the same row count.
public struct FolderGridGeometry: Sendable {
    public let columns: Int
    public let rows: Int
    public let height: Double
    public var capacity: Int { columns * rows }
    public init(width: Double, maxHeight: Double, itemCount: Int) {
        columns = max(1, min(7, Int(max(1, width) / 160)))
        let available = max(1, maxHeight)
        let neededRows = max(1, (max(0, itemCount) + columns - 1) / columns)
        rows = min(neededRows, max(1, Int(available / 180)))
        height = min(available, Double(rows) * 216)
    }
}
