import AppKit
import SwiftUI
import LaunchDockCore
import OSLog

@MainActor final class LauncherStore: ObservableObject {
    @Published var engine = LayoutEngine()
    @Published var records: [AppRecord] = []
    @Published var query = ""
    @Published var wallpaper: NSImage?
    @Published var wallpaperStatus = "显示时读取当前屏幕壁纸"
    @Published var page = 0
    @Published var folder: UUID? {
        didSet {
            if oldValue != folder, folder != nil {
                if oldValue == nil { rootPage = page; rootCapacity = capacity }
                capacity = folderCapacity; page = 0
            }
            if oldValue != nil, folder == nil { folderCapacity = capacity; capacity = rootCapacity; page = min(rootPage, pages-1) }
        }
    }
    private(set) var rootPage = 0
    var rootCapacity = 35
    private var folderCapacity = 7
    @Published var scanning = false
    @Published var message: String?
    @Published var selected: UUID?
    @Published var capacity = 35
    var hide: (() -> Void)?
    var hideAfterLaunch: (() -> Void)?
    var showSettings: (() -> Void)?
    var restartApplication: (() -> Void)?
    var quitApplication: (() -> Void)?

    func finderURL(for item: Item) -> URL? {
        let path: String?
        switch item {
        case .app(let id): path = records.first { $0.id == id }?.path
        case .folder(let id): path = engine.document.folders.first { $0.id == id }?.sourceDirectory
        }
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
    var pendingLaunch = Set<UUID>()
    var readOnly = false
    let catalog = CatalogService()
    let persistence: PersistenceService
    let iconCache: AppIconCache
    var launchFeedback: ((UUID) -> Void)?
    var showLaunchFailure: (() -> Void)?
    var openApplication: @Sendable (URL, @escaping @Sendable (String?) -> Void) -> Void = { url, completion in
        Task.detached(priority: .userInitiated) {
            let config = NSWorkspace.OpenConfiguration(); config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in completion(error?.localizedDescription) }
        }
    }
    init(dataDirectory: URL? = nil) {
        let cacheDirectory = dataDirectory?.appendingPathComponent("Icons-v1") ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("app.launchdock.LaunchDock/Icons-v1")
        iconCache = AppIconCache(directory: cacheDirectory)
        persistence = PersistenceService(directory: dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("app.launchdock.LaunchDock"))
        iconCache.didChange = { [weak self] in self?.objectWillChange.send() }
    }
    let logger = Logger(subsystem: "app.launchdock.LaunchDock", category: "layout")
    var index = SearchIndex(records: [])
    private var saveTask: Task<Void, Never>?
    private(set) var hasRestoredSnapshot = false
    var lastScan = Date.distantPast
    private var dragging = false
    private var scanQueued = false
    func beginDrag() { dragging = true }
    func endDrag() { dragging = false; if scanQueued { scanQueued = false; Task { await scan() } } }

    var visible: [Item] {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return index.search(query, order: engine.document.flattened.filter { !engine.document.hidden.contains($0) }).map(Item.app) }
        if let folder { return engine.document.folders.first { $0.id == folder }?.apps.filter { !engine.document.hidden.contains($0) }.map(Item.app) ?? [] }
        return engine.document.root.filter { item in
            switch item { case .app(let id): !engine.document.hidden.contains(id)
            case .folder(let id): engine.document.folders.first { $0.id == id }?.apps.contains { !engine.document.hidden.contains($0) } ?? false }
        }
    }
    var rootVisible: [Item] {
        engine.document.root.filter { item in
            switch item {
            case .app(let id): !engine.document.hidden.contains(id)
            case .folder(let id): engine.document.folders.first { $0.id == id }?.apps.contains { !engine.document.hidden.contains($0) } ?? false
            }
        }
    }
    var rootDisplayed: [Item] {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return visible }
        let current = folder == nil ? page : rootPage
        return Array(rootVisible.dropFirst(current*rootCapacity).prefix(rootCapacity))
    }
    var pages: Int { max(1, (visible.count + capacity - 1) / capacity) }
    var displayed: [Item] { query.isEmpty ? Array(visible.dropFirst(min(page, pages-1)*capacity).prefix(capacity)) : visible }
    func name(_ item: Item) -> String { switch item { case .app(let id): records.first { $0.id == id }?.label ?? "应用不可用"; case .folder(let id): engine.document.folders.first { $0.id == id }?.name ?? "文件夹" } }
    func icon(_ item: Item) -> NSImage {
        if case .folder(let id) = item, let folder = engine.document.folders.first(where: { $0.id == id }) {
            let image = NSImage(size: NSSize(width: 128, height: 128))
            image.lockFocus()
            NSColor.white.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: NSRect(x: 12, y: 12, width: 104, height: 104), xRadius: 22, yRadius: 22).fill()
            for (i, app) in folder.apps.filter({ !engine.document.hidden.contains($0) }).prefix(9).enumerated() {
                icon(.app(app)).draw(in: NSRect(x: 28+(i%3)*27, y: 82-(i/3)*27, width: 18, height: 18))
            }
            image.unlockFocus(); return image
        }
        guard case .app(let id) = item, let app = records.first(where: { $0.id == id }) else { return NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "文件夹")! }
        return iconCache.image(for: app)
    }
    func start() async {
        do {
            let (layout, snapshot, recovery) = try await persistence.load()
            let retained = snapshot.records.filter { !CatalogService.isExcludedApplication($0) }
            var loadedEngine = LayoutEngine(layout)
            if retained.count != snapshot.records.count { try loadedEngine.reconcile(retained) }
            await iconCache.preload(retained)
            engine = loadedEngine; records = retained
            index = SearchIndex(records: retained); message = recovery
        }
        catch { readOnly = true; message = error.localizedDescription }
        hasRestoredSnapshot = true
        scanQueued = false
        await scan()
    }
    func scan() async {
        guard hasRestoredSnapshot, !dragging, !scanning else { scanQueued = true; return }
        scanning = true
        defer {
            scanning = false
            if scanQueued && !dragging {
                scanQueued = false
                Task { await scan() }
            }
        }
        do {
            let anchor = displayed.first?.id
            let result = try await catalog.scan(previous: records)
            if dragging { scanQueued = true; return }
            records = result.records; index = SearchIndex(records: records)
            iconCache.refresh(records)
            if !readOnly { try engine.reconcile(records); repairContentContext(); save() }
            if let anchor, let index = visible.firstIndex(where: { $0.id == anchor }) { page = index / capacity } else { page = min(page,pages-1) }
            lastScan = Date()
            if !result.failures.isEmpty { message = "部分目录读取失败，旧条目已保留（\(result.failures.count) 处）" }
        } catch { message = "扫描失败：\(error.localizedDescription)" }
    }
    func change(_ body: (inout LayoutEngine) throws -> Void) {
        guard !readOnly else { message = "布局处于只读恢复状态"; return }
        do { try body(&engine); repairContentContext(); page = min(page, pages-1); save() } catch { message = "整理失败：\(error.localizedDescription)" }
    }
    private func repairContentContext() {
        if let folder, !engine.document.folders.contains(where: { $0.id == folder }) { self.folder = nil }
    }
    @discardableResult func moveAppOutOfFolder(_ id: UUID) -> Bool {
        guard let folder, let current = engine.document.folders.first(where: { $0.id == folder }), current.apps.contains(id),
              let index = engine.document.root.firstIndex(of: .folder(folder)) else { return false }
        let revision = engine.document.revision
        change { try $0.move(.app(id), at: index+1) }
        guard engine.document.revision != revision else { return false }
        self.folder = nil; selected = id
        return true
    }
    func save() {
        saveTask?.cancel()
        let layout = engine.document; var snapshot = CatalogSnapshot(); snapshot.records = records
        saveTask = Task { do { try await Task.sleep(for: .milliseconds(300)); try await persistence.save(layout, catalog: snapshot) } catch is CancellationError {} catch { message = "未保存：\(error.localizedDescription)"; logger.error("Layout save failed: \(error.localizedDescription, privacy: .private)") } }
    }
    func flush() async { saveTask?.cancel(); guard !readOnly else { return }; var snapshot = CatalogSnapshot(); snapshot.records = records; do { try await persistence.save(engine.document, catalog: snapshot) } catch { message = "未保存：\(error.localizedDescription)" } }
    func activate(_ item: Item) {
        if case .folder(let id) = item { folder = id; return }
        guard let app = records.first(where: { $0.id == item.id }), !pendingLaunch.contains(app.id) else { return }
        guard app.missingSince == nil, FileManager.default.fileExists(atPath: app.path) else { message = "\(name(item)) 不可用，请重新扫描或在访达中定位"; return }
        pendingLaunch.insert(app.id)
        launchFeedback?(app.id)
        Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
            guard let self else { return }
            // Dismiss based on the click, never on the target app's startup time.
            (self.hideAfterLaunch ?? self.hide)?()
            self.openApplication(URL(fileURLWithPath: app.path)) { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    self.pendingLaunch.remove(app.id)
                    if let error {
                        self.message = "无法启动 \(app.label)：\(error)"
                        self.showLaunchFailure?()
                    }
                }
            }
        }
    }

    func escape() {
        if !query.isEmpty { query = "" } else if folder != nil { folder = nil } else { hide?() }
    }
    func move(_ item: Item, offset: Int) {
        let list = visible; guard let i = list.firstIndex(of: item) else { return }
        change { try $0.move(item, into: folder, at: max(0, i+offset)) }
    }
}
