import Foundation
public struct CatalogSnapshot: Codable, Sendable {
    public var schemaVersion = 1
    public var records: [AppRecord] = []
    public init() {}
}
public struct ScanResult: Sendable {
    public var records: [AppRecord]
    public var failures: [String]
}
public actor CatalogService {
    private let scanRoots: [URL]
    public init(roots: [URL]? = nil) { self.scanRoots = roots ?? Self.roots }
    public static var roots: [URL] { ["/Applications", NSHomeDirectory() + "/Applications", "/System/Applications"].map { URL(fileURLWithPath: $0) } }
    public static func isExcludedApplicationPath(_ path: String) -> Bool {
        let excluded = "/System/Library/CoreServices/Applications"
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return normalized == excluded || normalized.hasPrefix(excluded + "/")
    }
    public static func isExcludedApplication(_ app: AppRecord) -> Bool {
        isExcludedApplicationPath(app.path) || app.bundleID == "app.launchdock.LaunchDock"
    }
    public func scan(previous: [AppRecord], now: Date = Date()) throws -> ScanResult {
        let previous = previous.filter { !Self.isExcludedApplication($0) }
        let fm = FileManager.default
        let roots = scanRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        var found: [AppRecord] = [], visited = Set<String>(), failures: [String] = []
        func allowed(_ url: URL) -> Bool { roots.contains { url.path == $0.path || url.path.hasPrefix($0.path + "/") } }
        func walk(_ url: URL, group: URL? = nil) throws {
            try Task.checkCancellation()
            let url = url.resolvingSymlinksInPath().standardizedFileURL
            guard !Self.isExcludedApplicationPath(url.path), allowed(url), visited.insert(url.path).inserted else { return }
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey, .fileResourceIdentifierKey, .volumeIdentifierKey])
                guard values.isDirectory == true, values.isHidden != true else { return }
                if url.pathExtension.lowercased() == "app" {
                    guard let bundle = Bundle(url: url), bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
                          (bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? NSNumber)?.boolValue != true,
                          bundle.bundleIdentifier != "app.launchdock.LaunchDock",
                          url != Bundle.main.bundleURL else { return }
                    // Resource identifiers are opaque: only archive supported Foundation values as bytes.
                    var identity: String?
                    if let file = values.fileResourceIdentifier as? NSData, let volume = values.volumeIdentifier as? NSNumber {
                        identity = volume.stringValue + ":" + (file as Data).base64EncodedString()
                    }
                    let name = fm.displayName(atPath: url.path)
                    var record = AppRecord(path: url.path, bundleID: bundle.bundleIdentifier, name: name, bundleName: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "", identity: identity)
                    record.sourceDirectory = group?.path
                    record.sourceDirectoryName = group.map { fm.displayName(atPath: $0.path) }
                    record.alternateNames = [bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, bundle.object(forInfoDictionaryKey: "CFBundleName") as? String].compactMap { $0 }
                    found.append(record)
                    return
                }
                for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) { try walk(child, group: group ?? (child.pathExtension.lowercased() == "app" ? nil : child)) }
            } catch is CancellationError { throw CancellationError() }
            catch { failures.append(url.path) }
        }
        for root in roots where fm.fileExists(atPath: root.path) { try walk(root) }
        var used = Set<UUID>()
        for i in found.indices {
            let candidate = found[i]
            let matches = previous.filter { !used.contains($0.id) && $0.bundleID == candidate.bundleID && (($0.identity != nil && $0.identity == candidate.identity) || $0.path == candidate.path) }
            if matches.count == 1 { found[i].id = matches[0].id; found[i].alternateNames = Array(Set((found[i].alternateNames ?? []) + [matches[0].name])).sorted(); used.insert(matches[0].id) }
        }
        // Only unambiguous moves whose old location has actually vanished.
        for i in found.indices where !used.contains(found[i].id) {
            guard let bid = found[i].bundleID, found.filter({ $0.bundleID == bid }).count == 1 else { continue }
            let matches = previous.filter { !used.contains($0.id) && $0.bundleID == bid && !fm.fileExists(atPath: $0.path) }
            if matches.count == 1 { found[i].id = matches[0].id; found[i].alternateNames = Array(Set((found[i].alternateNames ?? []) + [matches[0].name])).sorted(); used.insert(matches[0].id) }
        }
        for var old in previous where !used.contains(old.id) {
            let blocked = failures.contains { old.path == $0 || old.path.hasPrefix($0 + "/") }
            if blocked { old.inaccessible = true; found.append(old); continue }
            // Keep explicit import placeholders, which have no disk location.
            // All other absent apps were not found in their readable directory:
            // remove immediately, regardless of failures in unrelated folders.
            if old.path.isEmpty { found.append(old) }
        }
        return ScanResult(records: found.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }, failures: failures)
    }
}
