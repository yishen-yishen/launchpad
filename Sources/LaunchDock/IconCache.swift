import AppKit
import CryptoKit
import ImageIO
import LaunchDockCore

/// Only encoded PNG data crosses executors; AppKit images stay on their owner.
actor IconDiskCache {
    private struct Entry: Codable { let fingerprint: String }
    private struct Index: Codable { var version = 1; var entries: [String: Entry] = [:] }
    private let directory: URL
    private let render: @Sendable (String) -> Data?
    private var index: Index?
    private(set) var extractionCount = 0
    private(set) var lastRenderWasMainThread = false

    init(directory: URL, render: @escaping @Sendable (String) -> Data? = IconDiskCache.renderPNG) {
        self.directory = directory; self.render = render
    }
    private func loadIndex() {
        guard index == nil else { return }
        if let data = try? Data(contentsOf: directory.appendingPathComponent("index-v1.json")), data.count < 4_000_000,
           let saved = try? JSONDecoder().decode(Index.self, from: data), saved.version == 1 {
            index = saved
        } else { index = Index() }
    }
    private func cached(_ id: UUID) -> Data? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(id.uuidString + ".png")), data.count < 2_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 512, height <= 512,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { return nil }
        return data
    }
    func preload(_ ids: [UUID]) -> [UUID: Data] {
        loadIndex()
        return Dictionary(uniqueKeysWithValues: ids.compactMap { id in cached(id).map { (id, $0) } })
    }
    func refresh(_ app: AppRecord, hasImage: Bool) -> Data? {
        loadIndex()
        guard let fingerprint = Self.fingerprint(app.path) else { return nil }
        if index?.entries[app.id.uuidString]?.fingerprint == fingerprint {
            if hasImage { return nil }
            if let old = cached(app.id) { return old }
        }
        extractionCount += 1; lastRenderWasMainThread = Thread.isMainThread
        guard let data = autoreleasepool(invoking: { render(app.path) }), data.count < 2_000_000 else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(app.id.uuidString + ".png"), options: .atomic)
            index?.entries[app.id.uuidString] = Entry(fingerprint: fingerprint)
            try JSONEncoder().encode(index).write(to: directory.appendingPathComponent("index-v1.json"), options: .atomic)
        } catch { /* Cache storage is optional; still publish the loaded image. */ }
        return data
    }
    private nonisolated static func info(_ path: String) -> [String: Any] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")) else { return [:] }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] ?? [:]
    }
    private nonisolated static func resourceIcon(_ path: String, info: [String: Any]) -> URL? {
        guard let name = info["CFBundleIconFile"] as? String, !name.isEmpty else { return nil }
        let root = URL(fileURLWithPath: path).appendingPathComponent("Contents/Resources")
        let file = root.appendingPathComponent(name).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else { return nil }
        return file.pathExtension.isEmpty ? file.appendingPathExtension("icns") : file
    }
    private nonisolated static func fingerprint(_ path: String) -> String? {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        let root = URL(fileURLWithPath: path)
        let metadata = info(path)
        var urls = [root, root.appendingPathComponent("Contents/Info.plist"), root.appendingPathComponent("Contents/Resources"), root.appendingPathComponent("Contents/Resources/Assets.car")]
        if let icon = resourceIcon(path, info: metadata) { urls.append(icon) }
        var parts = [path, String(describing: metadata["CFBundleVersion"] ?? "")]
        for url in urls {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            parts.append(url.path + ":" + String(modified) + ":" + String(describing: attributes?[.size]))
        }
        return SHA256.hash(data: Data(parts.joined(separator: "|").utf8)).map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static func renderPNG(_ path: String) -> Data? {
        let image = resourceIcon(path, info: info(path)).flatMap { NSImage(contentsOf: $0) } ?? NSWorkspace.shared.icon(forFile: path)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}

@MainActor final class AppIconCache {
    let disk: IconDiskCache
    var didChange: (() -> Void)?
    private let images = NSCache<NSUUID, NSImage>()
    private var pngs: [UUID: Data] = [:]
    private var requested = Set<UUID>()
    private var pending: [UUID: Task<Void, Never>] = [:]
    private var queued: [UUID: AppRecord] = [:]
    private var notification: Task<Void, Never>?
    private let placeholder = NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
    init(directory: URL, disk: IconDiskCache? = nil) {
        self.disk = disk ?? IconDiskCache(directory: directory)
        images.totalCostLimit = 64 * 1024 * 1024
    }
    func preload(_ records: [AppRecord]) async {
        let cached = await disk.preload(records.map(\.id))
        // Retain compressed bytes first. Only visible cells need AppKit images.
        for (id, data) in cached { pngs[id] = data }
    }
    func image(for app: AppRecord) -> NSImage {
        if images.object(forKey: app.id as NSUUID) == nil, let data = pngs[app.id], let image = NSImage(data: data) {
            images.setObject(image, forKey: app.id as NSUUID, cost: 256*256*4)
        }
        request(app)
        return images.object(forKey: app.id as NSUUID) ?? placeholder
    }
    func refresh(_ records: [AppRecord]) {
        let ids = Set(records.map(\.id))
        pngs = pngs.filter { ids.contains($0.key) }; requested.formIntersection(ids)
        for record in records { request(record, force: true) }
    }
    private func request(_ app: AppRecord, force: Bool = false) {
        if pending[app.id] != nil {
            if force { queued[app.id] = app }
            return
        }
        guard force || !requested.contains(app.id) || images.object(forKey: app.id as NSUUID) == nil && pngs[app.id] != nil else { return }
        requested.insert(app.id)
        let hasImage = pngs[app.id] != nil
        pending[app.id] = Task(priority: .utility) { [weak self, disk] in
            let data = await disk.refresh(app, hasImage: hasImage)
            guard let self else { return }
            self.pending[app.id] = nil
            if let data { self.publish(data, id: app.id) }
            if let next = self.queued.removeValue(forKey: app.id) { self.request(next, force: true) }
        }
    }
    private func publish(_ data: Data, id: UUID) {
        guard pngs[id] != data || images.object(forKey: id as NSUUID) == nil, let image = NSImage(data: data) else { return }
        pngs[id] = data; images.setObject(image, forKey: id as NSUUID, cost: 256*256*4)
        guard notification == nil else { return }
        notification = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(32))
            guard let self else { return }
            self.notification = nil; self.didChange?()
        }
    }
}
