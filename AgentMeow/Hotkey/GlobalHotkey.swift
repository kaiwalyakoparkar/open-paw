import Carbon
import Foundation
import AgentMeowCore

private func agentMeowHotKeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hk = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hk
    )
    GlobalHotkey.dispatch(id: hk.id)
    return noErr
}

final class GlobalHotkey {
    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let combo: KeyCombo
    private let callback: () -> Void
    private static var instances: [UInt32: () -> Void] = [:]
    private let id: UInt32 = 1

    init(combo: KeyCombo, callback: @escaping () -> Void) {
        self.combo = combo
        self.callback = callback
    }

    static func dispatch(id: UInt32) {
        instances[id]?()
    }

    func register() {
        guard let key = HotkeyKeyMap.virtualKeyCode(for: combo.key) else {
            NSLog("agent-meow: unknown hotkey key %@", combo.key)
            return
        }
        let mods = HotkeyKeyMap.carbonModifiers(from: combo.modifiers)
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), agentMeowHotKeyHandler, 1, &spec, nil, &handler)

        let hkID = EventHotKeyID(signature: OSType(0x41474E54), id: id)
        RegisterEventHotKey(key, mods, hkID, GetApplicationEventTarget(), 0, &hotKeyRef)
        GlobalHotkey.instances[id] = callback
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        GlobalHotkey.instances[id] = nil
    }
}
