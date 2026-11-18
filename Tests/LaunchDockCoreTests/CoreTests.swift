import Testing
import Foundation
@testable import LaunchDockCore

@Test func movingAndFolderDissolution() throws {
    let records = (0..<6).map { AppRecord(path: "/\($0).app", name: "App \($0)") }
    var engine = LayoutEngine(); try engine.reconcile(records)
    try engine.move(.app(records[0].id), at: 4)
    #expect(engine.document.flattened == [1,2,3,4,0,5].map { records[$0].id })
    try engine.createFolder(source: records[0].id, target: records[2].id)
    #expect(engine.document.folders.first?.apps == [records[2].id,records[0].id])
    try engine.move(.app(records[0].id), at: 0)
    #expect(engine.document.folders.isEmpty)
    try LayoutEngine.validate(engine.document)
    engine.undo(); #expect(engine.document.folders.count == 1)
}
@Test func rejectedTransactionIsAtomic() throws {
    var engine = LayoutEngine(); let before = engine.document
    #expect(throws: (any Error).self) { try engine.createFolder(source: UUID(), target: UUID()) }
    #expect(engine.document == before)
}
@Test func hiddenKeepsLogicalPosition() throws {
    let records = (0..<3).map { AppRecord(path: "/\($0).app", name: "\($0)") }
    var engine = LayoutEngine(); try engine.reconcile(records)
    try engine.createFolder(source: records[0].id, target: records[1].id)
    let root = engine.document.root
    try engine.commit { $0.hidden.insert(records[0].id) }
    #expect(engine.document.folders.count == 1)
    try engine.commit { $0.hidden.remove(records[0].id) }
    #expect(engine.document.root == root)
}
@Test func searchRankingAndWidth() {
    let apps = [AppRecord(path: "/a", name: "Safari Tools"), AppRecord(path: "/b", name: "Safari"), AppRecord(path: "/c", name: "中文")]
    let index = SearchIndex(records: apps)
    #expect(index.search("ＳＡＦＡＲＩ", order: apps.map(\.id)) == [apps[1].id,apps[0].id])
    #expect(index.search("zhongwen", order: apps.map(\.id)) == [apps[2].id])
    #expect(index.search("  ", order: apps.map(\.id)).isEmpty)
}
@Test func randomMovesMaintainInvariants() throws {
    let apps = (0..<100).map { AppRecord(path: "/\($0)", name: "\($0)") }
    var engine = LayoutEngine(); try engine.reconcile(apps)
    var seed: UInt64 = 42
    for _ in 0..<1000 {
        seed = seed &* 6364136223846793005 &+ 1; let source = Int(seed % 100)
        seed = seed &* 6364136223846793005 &+ 1; let target = Int(seed % 100)
        try engine.move(.app(apps[source].id), at: target); try LayoutEngine.validate(engine.document)
        #expect(engine.document.flattened.count == 100)
    }
}
@Test func persistenceRejectsStaleAndRecovers() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let storage = PersistenceService(directory: dir)
    var engine = LayoutEngine(); let app = AppRecord(path: "/a", name: "A"); try engine.reconcile([app])
    let old = engine.document
    try await storage.save(old, catalog: CatalogSnapshot())
    try engine.commit { $0.hidden.insert(app.id) }; try await storage.save(engine.document, catalog: CatalogSnapshot())
    try await storage.save(old, catalog: CatalogSnapshot())
    let loaded = try await storage.load(); #expect(loaded.0.hidden.contains(app.id))
    try Data("broken".utf8).write(to: dir.appendingPathComponent("layout.json"))
    let recovered = try await storage.load(); #expect(recovered.2 != nil); #expect(recovered.0 == old)
}

@Test func portableImportDoesNotTrustPaths() throws {
    let app = AppRecord(path: "/Applications/Actual.app", bundleID: "test.app", name: "Actual")
    var engine = LayoutEngine(); try engine.reconcile([app])
    let encoded = try JSONEncoder().encode(LayoutExport(layout: engine.document, records: [app]))
    #expect(!String(decoding: encoded, as: UTF8.self).contains("/Applications"))
    let portable = try LayoutExport.decode(encoded)
    let resolved = try portable.resolve(current: [], revision: 9)
    #expect(resolved.2 == 1); #expect(resolved.1[0].path.isEmpty); #expect(resolved.0.revision == 10)
    let matched = try portable.resolve(current: [app], revision: 9)
    #expect(matched.2 == 0); #expect(matched.0.flattened == [app.id])
    #expect(throws: (any Error).self) { try LayoutExport.decode(Data(repeating: 32, count: 5*1024*1024+1)) }
}
@Test func futureSchemaRemainsUntouched() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let bytes = Data("{\"schemaVersion\":999}".utf8)
    let path = dir.appendingPathComponent("layout.json"); try bytes.write(to: path)
    let storage = PersistenceService(directory: dir)
    do { _ = try await storage.load(); Issue.record("Future schema accepted") } catch {}
    #expect(try Data(contentsOf: path) == bytes)
}
@Test func realScanKeepsInstalledCopies() async throws {
    let service = CatalogService()
    let first = try await service.scan(previous: [])
    #expect(Set(first.records.map(\.path)).count == first.records.count)
    let second = try await service.scan(previous: first.records)
    for record in first.records where record.missingSince == nil {
        #expect(second.records.first { $0.path == record.path }?.id == record.id)
    }
}

@Test func duplicateBundlesAndMoveIdentity() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    func bundle(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name+".app")
        let contents = url.appendingPathComponent("Contents"); try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundlePackageType":"APPL", "CFBundleIdentifier":"test.same", "CFBundleName":name], format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist")); return url
    }
    let a = try bundle("First"); _ = try bundle("Second")
    let catalog = CatalogService(roots: [root]); let first = try await catalog.scan(previous: [])
    #expect(first.records.count == 2); #expect(Set(first.records.map(\.id)).count == 2)
    let second = try await catalog.scan(previous: first.records)
    #expect(Set(first.records.map(\.id)) == Set(second.records.map(\.id)))
    // A move with duplicate bundle IDs is allowed only with reliable file identity.
    try FileManager.default.moveItem(at: a, to: root.appendingPathComponent("Moved.app"))
    let moved = try await catalog.scan(previous: second.records)
    #expect(moved.records.filter { $0.missingSince == nil }.count == 2)
    #expect(Set(moved.records.map(\.id)).count == moved.records.count)
}

@Test func mouseWheelAccumulatesBetweenEvents() {
    var pager = PageScroll()
    #expect(pager.update(delta: -1, precise: false, began: false, ended: false, momentum: false, now: 1) == 0)
    #expect(pager.update(delta: -1, precise: false, began: false, ended: false, momentum: false, now: 1.1) == 0)
    #expect(pager.update(delta: -1, precise: false, began: false, ended: false, momentum: false, now: 1.2) == 1)
    #expect(pager.update(delta: -4, precise: false, began: false, ended: false, momentum: false, now: 1.3) == 0)
    #expect(pager.update(delta: 3, precise: false, began: false, ended: false, momentum: false, now: 2) == -1)
}
@Test func trackpadFlipsOnceAndIgnoresMomentum() {
    var pager = PageScroll()
    #expect(pager.update(delta: -40, precise: true, began: true, ended: false, momentum: false, now: 1) == 0)
    #expect(pager.update(delta: -40, precise: true, began: false, ended: false, momentum: false, now: 1.1) == 1)
    #expect(pager.update(delta: -100, precise: true, began: false, ended: false, momentum: false, now: 1.3) == 0)
    #expect(pager.update(delta: -100, precise: true, began: false, ended: true, momentum: true, now: 2) == 0)
    #expect(pager.update(delta: 70, precise: true, began: true, ended: false, momentum: false, now: 3) == -1)
}

@Test func hotCornerImmediateLatchAndModifiers() {
    var trigger = CornerTrigger()
    let cornerResult1 = trigger.update(corner: 0, enabledMask: 1, modifierOK: true, mouseDown: false, now: 1)
    #expect(cornerResult1)
    let cornerResult2 = trigger.update(corner: 0, enabledMask: 1, modifierOK: true, mouseDown: false, now: 1.2)
    #expect(!cornerResult2)
    let cornerResult3 = trigger.update(corner: 0, enabledMask: 1, modifierOK: true, mouseDown: false, now: 1.4)
    #expect(!cornerResult3)
    let cornerResult4 = trigger.update(corner: 0, enabledMask: 1, modifierOK: true, mouseDown: false, now: 5)
    #expect(!cornerResult4)
    let cornerResult5 = trigger.update(corner: nil, enabledMask: 1, modifierOK: true, mouseDown: false, now: 6)
    #expect(!cornerResult5)
    let cornerResult6 = trigger.update(corner: 0, enabledMask: 1, modifierOK: false, mouseDown: false, now: 7)
    #expect(!cornerResult6)
    #expect(!trigger.isWaiting)
    let cornerResult7 = trigger.update(corner: 0, enabledMask: 1, modifierOK: true, mouseDown: true, now: 8)
    #expect(!cornerResult7)
    #expect(!trigger.isWaiting)
    let cornerResult8 = trigger.update(corner: 1, enabledMask: 1, modifierOK: true, mouseDown: false, now: 9)
    #expect(!cornerResult8)
    let cornerResult9 = trigger.update(corner: 0, enabledMask: 1, modifierOK: true, mouseDown: false, now: 10)
    #expect(cornerResult9)
    let cornerResult10 = trigger.update(corner: 0, enabledMask: 1, modifierOK: true, mouseDown: false, now: 10.4)
    #expect(!cornerResult10)
}

@Test func backgroundDragBeatsClickDismissal() {
    var click = BackgroundDrag(x: 100,y: 100)
    #expect(click.end(x: 102,y: 101) == .click)
    var left = BackgroundDrag(x: 100,y: 100)
    #expect(left.end(x: 10,y: 105) == .page(1))
    var right = BackgroundDrag(x: 100,y: 100)
    #expect(right.end(x: 190,y: 100) == .page(-1))
    var returned = BackgroundDrag(x: 100,y: 100)
    returned.update(x: 160,y: 100)
    #expect(returned.end(x: 100,y: 100) == .cancel)
    var vertical = BackgroundDrag(x: 100,y: 100)
    #expect(vertical.end(x: 104,y: 240) == .cancel)
}
@Test func directoryGroupingPreservesUserEdits() throws {
    var apps = (0..<4).map { AppRecord(path: "/Apps/Utilities/\($0).app", name: "App \($0)") }
    for i in apps.indices { apps[i].sourceDirectory = "/Apps/Utilities"; apps[i].sourceDirectoryName = "Utilities" }
    var engine = LayoutEngine(); try engine.reconcile(apps)
    let folder = try #require(engine.document.folders.first)
    #expect(folder.name == "Utilities" && folder.apps == apps.map(\.id))
    #expect(engine.document.root == [.folder(folder.id)])
    try engine.move(.app(apps[0].id), at: 1)
    try engine.rename(folder.id, name: "My Tools")
    try engine.reconcile(apps)
    #expect(engine.document.root.contains(.app(apps[0].id)))
    #expect(engine.document.folders.first?.name == "My Tools")
    var installed = AppRecord(path: "/Apps/Utilities/New.app", name: "New")
    installed.sourceDirectory = "/Apps/Utilities"; installed.sourceDirectoryName = "Utilities"
    try engine.reconcile(apps+[installed])
    #expect(engine.document.folders.first?.apps.last == installed.id)
    let exported = try JSONEncoder().encode(LayoutExport(layout: engine.document, records: apps+[installed]))
    #expect(!String(decoding: exported, as: UTF8.self).contains("/Apps/Utilities"))
    try LayoutEngine.validate(engine.document)
}
@Test func scanUsesFinderNamesAndPhysicalDirectories() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["One", "Two"] {
        let contents = root.appendingPathComponent("Utilities/\(name).app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let bytes = try PropertyListSerialization.data(fromPropertyList: ["CFBundlePackageType":"APPL","CFBundleIdentifier":"test."+name,"CFBundleName":name,"CFBundleDisplayName":"中文"+name], format: .xml, options: 0)
        try bytes.write(to: contents.appendingPathComponent("Info.plist"))
    }
    let result = try await CatalogService(roots: [root]).scan(previous: [])
    #expect(result.records.count == 2)
    for app in result.records {
        #expect(app.name == FileManager.default.displayName(atPath: app.path))
        let directory = try #require(app.sourceDirectory)
        let actual = try FileManager.default.attributesOfItem(atPath: directory)
        let expected = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("Utilities").path)
        #expect(actual[.systemFileNumber] as? NSNumber == expected[.systemFileNumber] as? NSNumber)
        #expect(directory.hasSuffix("/Utilities"))
        #expect(app.sourceDirectoryName == "Utilities")
        #expect(app.alternateNames?.contains(where: { $0.hasPrefix("中文") }) == true)
    }
    var engine = LayoutEngine(); try engine.reconcile(result.records)
    #expect(engine.document.root.count == 1 && engine.document.folders.count == 1)
    #expect(SearchIndex(records: result.records).search("中文", order: engine.document.flattened).count == 2)
}

@Test func appLabelsHideOnlyTheBundleSuffix() {
    #expect(AppRecord(path: "/Applications/Visual Studio Code.app", name: "Code").label == "Visual Studio Code")
    #expect(AppRecord(path: "/Something.APP", name: "Other").label == "Something")
    #expect(AppRecord(path: "/my.app.editor.app", name: "Other").label == "my.app.editor")
    #expect(AppRecord(path: "/终端.app", name: "Other").label == "终端")
}

@Test func filenameStrategyRanksVisibleNameAndRetainsLocalizedSearch() {
    let terminal = AppRecord(path: "/System/Applications/Utilities/Terminal.app", name: "终端", bundleName: "Terminal")
    let tools = AppRecord(path: "/Applications/Terminal Tools.app", name: "工具")
    let index = SearchIndex(records: [tools,terminal])
    #expect(terminal.label == "Terminal")
    #expect(index.search("Terminal", order: [tools.id,terminal.id]) == [terminal.id,tools.id])
    #expect(index.search("终端", order: [tools.id,terminal.id]) == [terminal.id])
}

@Test func menuBarApplicationsAreLaunchableCatalogEntries() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("AgentApps-\(UUID())")
    defer { try? fm.removeItem(at: root) }
    func make(_ name: String, id: String, background: Bool = false) throws {
        let contents = root.appendingPathComponent(name+".app/Contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String:Any] = ["CFBundlePackageType":"APPL", "CFBundleIdentifier":id,
            "CFBundleName":name, "LSUIElement":true, "LSBackgroundOnly":background]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    }
    try make("Raycast", id: "com.raycast.macos")
    try make("iRightMouse Pro", id: "cn.better365.iRightMousePro")
    try make("Background", id: "test.background", background: true)
    try make("LaunchDock copy", id: "app.launchdock.LaunchDock")
    let result = try await CatalogService(roots: [root]).scan(previous: [])
    #expect(Set(result.records.compactMap(\.bundleID)) == ["com.raycast.macos", "cn.better365.iRightMousePro"])
    #expect(SearchIndex(records: result.records).search("Raycast", order: result.records.map(\.id)).count == 1)
}

@Test func uninstalledApplicationRemovedDespiteUnrelatedReadFailure() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("Uninstall-\(UUID())")
    let protected = root.appendingPathComponent("Protected")
    defer {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: protected.path)
        try? fm.removeItem(at: root)
    }
    func make(_ path: URL, id: String) throws {
        let contents = path.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundlePackageType":"APPL", "CFBundleIdentifier":id]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    }
    let removed = root.appendingPathComponent("Removed.app")
    try make(removed, id: "test.removed")
    try make(protected.appendingPathComponent("Kept.app"), id: "test.kept")
    let catalog = CatalogService(roots: [root])
    let first = try await catalog.scan(previous: [])
    #expect(first.records.count == 2)
    try fm.removeItem(at: removed)
    try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: protected.path)
    let second = try await catalog.scan(previous: first.records)
    #expect(!second.failures.isEmpty)
    #expect(!second.records.contains { $0.bundleID == "test.removed" })
    #expect(second.records.contains { $0.bundleID == "test.kept" && $0.inaccessible })
    var engine = LayoutEngine(); try engine.reconcile(first.records); try engine.reconcile(second.records)
    #expect(engine.document.flattened == second.records.map(\.id))
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: protected.path)
    let restored = try await catalog.scan(previous: second.records)
    #expect(restored.records.count == 1 && restored.records[0].inaccessible == false)
}

@Test func initialSystemGroupingPreservesCommonAppsAndExistingLayouts() throws {
    var terminal = AppRecord(path: "/System/Applications/Utilities/Terminal.app", bundleID: "com.apple.Terminal", name: "Terminal")
    terminal.sourceDirectory = "/System/Applications/Utilities"
    var monitor = AppRecord(path: "/System/Applications/Utilities/Activity Monitor.app", bundleID: "com.apple.ActivityMonitor", name: "Activity Monitor")
    monitor.sourceDirectory = terminal.sourceDirectory
    let common = [terminal,
        AppRecord(path: "/System/Applications/System Settings.app", bundleID: "com.apple.systempreferences", name: "Settings"),
        AppRecord(path: "/System/Applications/App Store.app", bundleID: "com.apple.AppStore", name: "App Store"),
        AppRecord(path: "/Applications/Safari.app", bundleID: "com.apple.Safari", name: "Safari"),
        AppRecord(path: "/System/Applications/Preview.app", bundleID: "com.apple.Preview", name: "Preview")]
    let tools = [monitor, AppRecord(path: "/System/Applications/Chess.app", bundleID: "com.apple.Chess", name: "Chess"),
        AppRecord(path: "/System/Applications/Calendar.app", bundleID: "com.apple.iCal", name: "Calendar")]
    let xcode = AppRecord(path: "/Applications/Xcode.app", bundleID: "com.apple.dt.Xcode", name: "Xcode")
    #expect(!xcode.isSystemProvided)
    let records = common + tools + [xcode]
    var engine = LayoutEngine(); try engine.reconcile(records)
    #expect(engine.document.folders.first { $0.name == "系统工具" }?.apps == tools.map(\.id))
    #expect((common + [xcode]).allSatisfy { engine.document.root.contains(.app($0.id)) })
    try engine.move(.app(monitor.id), at: 0); try engine.reconcile(records)
    #expect(engine.document.root.contains(.app(monitor.id)))
    var existing = Layout(); existing.directoryGroupingVersion = 1; existing.root = records.map { .app($0.id) }
    var preserved = LayoutEngine(existing); try preserved.reconcile(records)
    #expect(preserved.document.root == existing.root && preserved.document.folders.isEmpty)
}

@Test func folderUsesHeightBeforeCreatingMorePages() {
    let small = FolderGridGeometry(width: 1120, maxHeight: 840, itemCount: 2)
    let medium = FolderGridGeometry(width: 1120, maxHeight: 840, itemCount: 21)
    let large = FolderGridGeometry(width: 1120, maxHeight: 840, itemCount: 70)
    #expect(small.height < medium.height && medium.height < large.height)
    #expect(large.rows == 4 && large.height == 840 && large.capacity == 28)
    let tall = FolderGridGeometry(width: 1120, maxHeight: 1200, itemCount: 70)
    #expect(tall.rows == 6 && tall.height == 1200 && tall.capacity == 42)
    for panel in [small, medium, large, tall] {
        #expect(GridGeometry(width: 1120, height: panel.height, cellWidth: 160, cellHeight: 180, maxRows: panel.rows).capacity == panel.capacity)
    }
}
