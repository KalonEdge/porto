import AppKit
import Carbon.HIToolbox

/// The global ⌃⌥⌘P shortcut, through Carbon's hot key API: the only public way
/// to register a system-wide shortcut without Accessibility access.
@MainActor
final class HotKey {
    static let shared = HotKey()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    private func register() {
        guard hotKeyRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    Usage.record(.shortcut)
                    StatusItemOpener.open()
                }
            }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x504F_5254), id: 1) // "PORT"
        RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
