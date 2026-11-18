import Foundation
import LaunchDockCore

func movingAndFolderDissolution() throws {
    let records = (0..<6).map { AppRecord(path: "/\($0).app", name: "App \($0)") }
    var engine = LayoutEngine(); try engine.reconcile(records)
    try engine.move(.app(records[0].id), at: 4)
    check(engine.document.flattened == [1,2,3,4,0,5].map { records[$0].id })
    try engine.createFolder(source: records[0].id, target: records[2].id)
    check(engine.document.folders.first?.apps == [records[2].id,records[0].id])
    try engine.move(.app(records[0].id), at: 0)
    check(engine.document.folders.isEmpty)
    try LayoutEngine.validate(engine.document)
    engine.undo(); check(engine.document.folders.count == 1)
}
func rejectedTransactionIsAtomic() throws {
    var engine = LayoutEngine(); let before = engine.document
    do { try engine.createFolder(source: UUID(), target: UUID()); fatalError("Invalid transaction accepted") } catch {}
    check(engine.document == before)
}
func hiddenKeepsLogicalPosition() throws {
    let records = (0..<3).map { AppRecord(path: "/\($0).app", name: "\($0)") }
    var engine = LayoutEngine(); try engine.reconcile(records)
    try engine.createFolder(source: records[0].id, target: records[1].id)
    let root = engine.document.root
    try engine.commit { $0.hidden.insert(records[0].id) }
    check(engine.document.folders.count == 1)
    try engine.commit { $0.hidden.remove(records[0].id) }
    check(engine.document.root == root)
}
func searchRankingAndWidth() {
    let apps = [AppRecord(path: "/a", name: "Safari Tools"), AppRecord(path: "/b", name: "Safari"), AppRecord(path: "/c", name: "中文")]
    let index = SearchIndex(records: apps)
    check(index.search("ＳＡＦＡＲＩ", order: apps.map(\.id)) == [apps[1].id,apps[0].id])
    check(index.search("zhongwen", order: apps.map(\.id)) == [apps[2].id])
    check(index.search("  ", order: apps.map(\.id)).isEmpty)
}
func randomMovesMaintainInvariants() throws {
    let apps = (0..<100).map { AppRecord(path: "/\($0)", name: "\($0)") }
    var engine = LayoutEngine(); try engine.reconcile(apps)
    var seed: UInt64 = 42
    for _ in 0..<1000 {
        seed = seed &* 6364136223846793005 &+ 1; let source = Int(seed % 100)
        seed = seed &* 6364136223846793005 &+ 1; let target = Int(seed % 100)
        try engine.move(.app(apps[source].id), at: target); try LayoutEngine.validate(engine.document)
        check(engine.document.flattened.count == 100)
    }
}
func persistenceRejectsStaleAndRecovers() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let storage = PersistenceService(directory: dir)
    var engine = LayoutEngine(); let app = AppRecord(path: "/a", name: "A"); try engine.reconcile([app])
    let old = engine.document
    try await storage.save(old, catalog: CatalogSnapshot())
    try engine.commit { $0.hidden.insert(app.id) }; try await storage.save(engine.document, catalog: CatalogSnapshot())
    try await storage.save(old, catalog: CatalogSnapshot())
    let loaded = try await storage.load(); check(loaded.0.hidden.contains(app.id))
    try Data("broken".utf8).write(to: dir.appendingPathComponent("layout.json"))
    let recovered = try await storage.load(); check(recovered.2 != nil); check(recovered.0 == old)
}

func check(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    precondition(condition(), "Core check failed at \(file):\(line)")
}
@main struct CoreChecks {
    static func main() async throws {
        try movingAndFolderDissolution(); try rejectedTransactionIsAtomic(); try hiddenKeepsLogicalPosition()
        searchRankingAndWidth(); try randomMovesMaintainInvariants(); try await persistenceRejectsStaleAndRecovers()
        print("PASS: 6 core scenarios, including 1000 deterministic layout operations")
    }
}
