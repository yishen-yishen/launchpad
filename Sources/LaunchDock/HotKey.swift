import Carbon
import AppKit
@MainActor final class HotKeyService {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    func register(code: UInt32 = 49, modifiers: UInt32 = UInt32(optionKey)) -> OSStatus {
        var newRef: EventHotKeyRef?
        let result = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: 0x4c444f43, id: 1), GetApplicationEventTarget(), 0, &newRef)
        guard result == noErr else { return result }
        if let reference { UnregisterEventHotKey(reference) }; reference = newRef
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
                guard let data else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated { Unmanaged<HotKeyService>.fromOpaque(data).takeUnretainedValue().action?() }; return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        return result
    }
    func stop() { if let reference { UnregisterEventHotKey(reference) }; if let handler { RemoveEventHandler(handler) }; reference = nil; handler = nil }
}
