import ApplicationServices
import Carbon
import OpenPawCore
import Foundation

private func holdHotKeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }
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
    let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    HoldToTalkMonitor.dispatch(id: hk.id, pressed: pressed)
    return noErr
}

/// Hold-to-talk: Carbon press/release for key combos.
/// Modifier keys poll HID flags — no Accessibility.
final class HoldToTalkMonitor {
    private static var instances: [UInt32: (Bool) -> Void] = [:]
    private static let carbonID: UInt32 = 2

    private let kind: HoldKeyKind
    private let onBegin: () -> Void
    private let onEnd: () -> Void
    private var gate = HoldGate(releaseTicks: 4)
    private var pollTimer: Timer?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var holding = false
    private var registered = false

    init(combo: KeyCombo, onBegin: @escaping () -> Void, onEnd: @escaping () -> Void) {
        guard let kind = HotkeyKeyMap.holdKeyKind(for: combo) else {
            fatalError("open-paw: unknown hold key \(combo.key)")
        }
        self.kind = kind
        self.onBegin = onBegin
        self.onEnd = onEnd
    }

    var isRegistered: Bool { registered }

    static func dispatch(id: UInt32, pressed: Bool) {
        instances[id]?(pressed)
    }

    func register() {
        guard !registered else { return }
        switch kind {
        case .keyCombo(let mods, let keyCode):
            registerCarbon(mods: mods, keyCode: keyCode)
        case .modifierOnly, .modifierChord:
            registerHIDPoll()
        }
    }

    func unregister() {
        pollTimer?.invalidate()
        pollTimer = nil
        gate = HoldGate(releaseTicks: 4)
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        handlerRef = nil
        Self.instances[Self.carbonID] = nil
        holding = false
        registered = false
    }

    private func registerCarbon(mods: UInt32, keyCode: UInt16) {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = specs.withUnsafeMutableBufferPointer { buf -> OSStatus in
            InstallEventHandler(
                GetApplicationEventTarget(),
                holdHotKeyHandler,
                2,
                buf.baseAddress,
                nil,
                &handlerRef
            )
        }
        guard status == noErr else {
            NSLog("open-paw: Carbon hold handler failed (%d)", status)
            return
        }
        let hkID = EventHotKeyID(signature: OSType(0x484F4C44), id: Self.carbonID)
        let hkStatus = RegisterEventHotKey(
            UInt32(keyCode),
            mods,
            hkID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard hkStatus == noErr else {
            NSLog("open-paw: RegisterEventHotKey failed (%d)", hkStatus)
            return
        }
        Self.instances[Self.carbonID] = { [weak self] pressed in
            self?.updateHold(pressed)
        }
        registered = true
    }

    private func registerHIDPoll() {
        // ponytail: 50ms flag poll; CGEvent tap + Accessibility if latency matters.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.pollFlags()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        registered = true
        pollFlags()
    }

    private func pollFlags() {
        // HID system flags, not flagsChanged event bits (orderFront zeros those).
        let flags = UInt(CGEventSource.flagsState(.hidSystemState).rawValue)
        let pressed: Bool
        switch kind {
        case .modifierOnly(let keyCode):
            pressed = HotkeyKeyMap.modifierHoldIsDown(keyCode: keyCode, nsEventFlags: flags)
        case .modifierChord(let mods):
            pressed = HotkeyKeyMap.nsEventModifiersMatch(flags, requiredCarbon: mods)
        case .keyCombo:
            return
        }
        switch gate.sample(pressed) {
        case true: updateHold(true)
        case false: updateHold(false)
        case nil: break
        }
    }

    private func updateHold(_ down: Bool) {
        if down, !holding {
            holding = true
            onBegin()
        } else if !down, holding {
            holding = false
            onEnd()
        }
    }

    deinit { unregister() }
}
