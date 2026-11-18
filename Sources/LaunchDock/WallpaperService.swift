import AppKit
import ImageIO
import OSLog

/// Supplies a frozen wallpaper image without changing any other application's windows.
@MainActor final class WallpaperService {
    struct Snapshot {
        let image: NSImage?
        let description: String
    }
    private let logger = Logger(subsystem: "app.launchdock.LaunchDock", category: "wallpaper")
    private(set) var lastCaptureStatistics: PixelStatistics?
    private(set) var strategy = "wallpaper-file"
    var source: (NSScreen) -> URL? = { NSWorkspace.shared.desktopImageURL(for: $0) }
    var capture: @MainActor (NSScreen) async throws -> NSImage = { screen in try DesktopWallpaperReader.read(screen).image }

    func snapshot(for screen: NSScreen) async -> Snapshot {
        lastCaptureStatistics = nil
        strategy = "wallpaper-file"
        let url = source(screen)
        let imageSource = url.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
        // A default/proxy resource is valid, but may be a poster instead of the
        // current dynamic frame. Try the desktop-background surface first for it.
        let prefersDesktop = imageSource == nil || url?.lastPathComponent == "DefaultDesktop.heic" ||
            ["heic", "heif"].contains(url?.pathExtension.lowercased() ?? "") ||
            imageSource.map { CGImageSourceGetCount($0) > 1 } == true
        if !prefersDesktop, let imageSource { return fileSnapshot(imageSource, screen: screen, note: nil) }
        do {
            let image = try await capture(screen)
            try Task.checkCancellation()
            let statistics = Self.pixelStatistics(image)
            lastCaptureStatistics = statistics
            guard let statistics, !statistics.isEmpty else { throw CaptureError.emptyImage }
            strategy = "desktop-window-no-recording"
            return reported(Snapshot(image: image, description: "当前桌面壁纸：本次打开时读取，显示期间固定"))
        } catch is CancellationError { return Snapshot(image: nil, description: "已取消壁纸刷新") }
        catch {
            logger.notice("Desktop background unavailable: \(error.localizedDescription, privacy: .public)")
            return fileSnapshot(imageSource, screen: screen, note: error.localizedDescription)
        }
    }
    private func reported(_ snapshot: Snapshot) -> Snapshot {
        logger.info("Wallpaper result: \(snapshot.description, privacy: .public)")
        #if DEBUG
        var result: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
            "requiresScreenRecording": false, "hasImage": snapshot.image != nil,
            "status": snapshot.description, "time": Date().timeIntervalSince1970,
            "captureStrategy": strategy]
        if let statistics = lastCaptureStatistics {
            result["capturePixelStatistics"] = ["peakRGB": statistics.peakRGB, "meanRGB": statistics.meanRGB, "meanAlpha": statistics.meanAlpha]
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/launchdock-wallpaper-\(ProcessInfo.processInfo.processIdentifier).json"), options: .atomic)
        }
        #endif
        return snapshot
    }
    private func fileSnapshot(_ source: CGImageSource?, screen: NSScreen, note: String?) -> Snapshot {
        strategy = "wallpaper-file"
        guard let source,
              let cg = CGImageSourceCreateThumbnailAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2560] as CFDictionary) else {
            return reported(Snapshot(image: nil, description: (note ?? "无法读取当前壁纸") + "；使用纯色背景"))
        }
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        let size = screen.frame.size
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        let result = NSImage(size: size)
        result.lockFocus()
        (options[.fillColor] as? NSColor ?? .black).setFill()
        NSRect(origin: .zero, size: size).fill()
        let scaling = (options[.imageScaling] as? NSNumber).flatMap { NSImageScaling(rawValue: $0.uintValue) } ?? .scaleProportionallyUpOrDown
        var drawn = image.size
        if scaling == .scaleAxesIndependently { drawn = size }
        else if scaling != .scaleNone {
            let clip = options[.allowClipping] as? Bool ?? true
            let scale = clip ? max(size.width/drawn.width, size.height/drawn.height) : min(size.width/drawn.width, size.height/drawn.height)
            let factor = scaling == .scaleProportionallyDown ? min(1, scale) : scale
            drawn = NSSize(width: drawn.width*factor, height: drawn.height*factor)
        }
        image.draw(in: NSRect(x: (size.width-drawn.width)/2, y: (size.height-drawn.height)/2, width: drawn.width, height: drawn.height))
        result.unlockFocus()
        return reported(Snapshot(image: result, description: note.map { "壁纸文件静态画面（\($0)）" } ?? "当前屏幕壁纸文件"))
    }
    struct PixelStatistics {
        let peakRGB: Double
        let meanRGB: Double
        let meanAlpha: Double
        var isEmpty: Bool { meanAlpha < 0.01 || peakRGB <= 2.0/255.0 }
    }
    static func pixelStatistics(_ image: NSImage) -> PixelStatistics? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 32
        var bytes = [UInt8](repeating: 0, count: side*side*4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side*4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var peak = 0, total = 0, alpha = 0
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            for component in 0..<3 { peak = max(peak, Int(bytes[pixel+component])); total += Int(bytes[pixel+component]) }
            alpha += Int(bytes[pixel+3])
        }
        return PixelStatistics(peakRGB: Double(peak)/255, meanRGB: Double(total)/Double(side*side*3*255), meanAlpha: Double(alpha)/Double(side*side*255))
    }
    enum CaptureError: LocalizedError {
        case emptyImage
        var errorDescription: String? {
            switch self {
            case .emptyImage: "桌面背景图像仅含黑色或透明像素，未能确认壁纸内容"
            }
        }
    }
}
