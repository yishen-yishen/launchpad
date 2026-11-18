import AppKit
import LaunchDockCore

extension LauncherStore {
    func exportLayout() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "LaunchDock-layout.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(LayoutExport(layout: engine.document, records: records)).write(to: url, options: .atomic) }
        catch { message = "导出失败：\(error.localizedDescription)" }
    }
    func importLayout() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey]); guard (values.fileSize ?? Int.max) <= 5*1024*1024 else { throw LayoutError.invalid("导入文件超过 5 MB") }
            let portable = try LayoutExport.decode(Data(contentsOf: url))
            let (layout, newRecords, missing) = try portable.resolve(current: records, revision: engine.document.revision)
            let alert = NSAlert(); alert.messageText = "导入布局？"; alert.informativeText = "\(portable.applications.count-missing) 个应用已匹配，\(missing) 个作为不可用占位。原布局将备份。"; alert.addButton(withTitle: "备份并导入"); alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                Task {
                    await flush()
                    // A unique pre-import copy also protects against later backup rotation.
                    do {
                        let dir = await persistence.directory
                        let source = dir.appendingPathComponent("layout.json")
                        if FileManager.default.fileExists(atPath: source.path) { try FileManager.default.copyItem(at: source, to: dir.appendingPathComponent("layout.preimport-\(UUID()).json")) }
                        readOnly = false; engine = LayoutEngine(layout); records = newRecords; index = SearchIndex(records: records); page = 0; folder = nil; save()
                    } catch { message = "导入前备份失败：\(error.localizedDescription)" }
                }
            }
        } catch { message = "拒绝导入：\(error.localizedDescription)" }
    }
    func canTrash(_ id: UUID) -> Bool {
        guard let record = records.first(where: { $0.id == id }), record.missingSince == nil else { return false }
        let url = URL(fileURLWithPath: record.path).resolvingSymlinksInPath().standardizedFileURL
        let allowed = ["/Applications/", NSHomeDirectory()+"/Applications/"]
        return allowed.contains { url.path.hasPrefix($0) } && url.pathExtension == "app" && url != Bundle.main.bundleURL && FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path) && FileManager.default.isWritableFile(atPath: url.path)
    }
    func trash(_ id: UUID) {
        guard canTrash(id), let app = records.first(where: { $0.id == id }) else { return }
        let url = URL(fileURLWithPath: app.path).resolvingSymlinksInPath()
        guard !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.resolvingSymlinksInPath() == url }) else { message = "请先自行退出 \(app.name)"; return }
        let alert = NSAlert(); alert.messageText = "将 \(app.name) 移到废纸篓？"; alert.informativeText = url.path; alert.addButton(withTitle: "移到废纸篓"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn, canTrash(id) else { return }
        do { try FileManager.default.trashItem(at: url, resultingItemURL: nil); Task { await scan() } } catch { message = "无法移到废纸篓：\(error.localizedDescription)" }
    }
}
