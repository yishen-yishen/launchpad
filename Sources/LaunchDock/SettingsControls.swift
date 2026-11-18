import AppKit
import SwiftUI
import LaunchDockCore
import Carbon

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var label: String
    var failure: (String) -> Void
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(title: "快捷键：\(label)", target: nil, action: nil)
        button.recorded = { event in
            guard let app = NSApp.delegate as? AppCoordinator else { return }
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
            if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
            if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            guard modifiers & UInt32(optionKey | cmdKey | controlKey) != 0 else { failure("快捷键须包含 Option、Command 或 Control"); return }
            if app.hotkey.register(code: UInt32(event.keyCode), modifiers: modifiers) == noErr {
                UserDefaults.standard.set(Int(event.keyCode), forKey: "hotkeyCode"); UserDefaults.standard.set(Int(modifiers), forKey: "hotkeyModifiers")
                label = event.modifierFlags.symbols + (event.charactersIgnoringModifiers ?? "").uppercased()
                UserDefaults.standard.set(label, forKey: "hotkeyLabel")
            } else { failure("快捷键注册失败，已保留原配置") }
        }
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) { if !button.recording { button.title = "快捷键：\(label)（点击录制）" } }
}
final class RecorderButton: NSButton {
    var recorded: ((NSEvent) -> Void)?
    var recording = false
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { recording = true; title = "请按组合键，Esc 取消"; window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        recording = false
        if event.keyCode != 53 { recorded?(event) }
        title = "点击录制快捷键"; window?.makeFirstResponder(nil)
    }
}
extension NSEvent.ModifierFlags {
    var symbols: String { (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "") + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "") }
}

