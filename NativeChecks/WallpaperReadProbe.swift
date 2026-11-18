import AppKit
@main struct Probe {
    @MainActor static func main() {
        var report: [String:Any] = ["screenRecordingGranted": CGPreflightScreenCaptureAccess(), "pid": ProcessInfo.processInfo.processIdentifier]
        do {
            guard let screen = NSScreen.main else { return }
            let result = try DesktopWallpaperReader.read(screen)
            report["backend"] = result.backend
            if let cg = result.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/launchdock-desktop-probe-result.json")
                    .deletingLastPathComponent().appendingPathComponent("wallpaper-preview.png")
                try png.write(to: output)
                report["previewPath"] = output.path
            }
            if let pixels = WallpaperService.pixelStatistics(result.image) {
                report["peakRGB"] = pixels.peakRGB; report["meanRGB"] = pixels.meanRGB; report["meanAlpha"] = pixels.meanAlpha
                report["hasContent"] = !pixels.isEmpty
            }
        } catch { report["error"] = error.localizedDescription }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/launchdock-desktop-probe-result.json"),options:.atomic)
        }
    }
}
