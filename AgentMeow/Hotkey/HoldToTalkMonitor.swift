import AppKit
import ApplicationServices
import Carbon
import AgentMeowCore
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

/// Hold-to-talk: Carbon press/release for key combos (no Accessibility).
/// Modifier-only keys use NSEvent flagsChanged (needs Accessibility).
final class HoldToTalkMonitor {
    private static var instances: [UInt32: (Bool) -> Void] = [:]
    private static let carbonID: UInt32 = 2

    private let kind: HoldKeyKind
    private let onBegin: () -> Void
    private let onEnd: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var holding = false
    private var registered = false

    init(combo: KeyCombo, onBegin: @escaping () -> Void, onEnd: @escaping () -> Void) {
        guard let kind = HotkeyKeyMap.holdKeyKind(for: combo) else {
            fatalError("agent-meow: unknown hold key \(combo.key)")
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
        case .modifierOnly:
            registerNSEvent()
        }
    }

    func unregister() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
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
            NSLog("agent-meow: Carbon hold handler failed (%d)", status)
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
            NSLog("agent-meow: RegisterEventHotKey failed (%d)", hkStatus)
            return
        }
        Self.instances[Self.carbonID] = { [weak self] pressed in
            self?.updateHold(pressed)
        }
        registered = true
    }

    private func registerNSEvent() {
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] in
            self?.handle($0)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        registered = globalMonitor != nil || localMonitor != nil
        if !AXIsProcessTrusted() {
            NSLog("agent-meow: modifier hold key needs Accessibility — System Settings → Privacy")
        }
    }

    private func handle(_ event: NSEvent) {
        switch kind {
        case .modifierOnly(let keyCode):
            guard event.type == .flagsChanged else { return }
            guard HotkeyKeyMap.modifierHoldEventApplies(eventKeyCode: event.keyCode, configured: keyCode) else { return }
            updateHold(HotkeyKeyMap.modifierHoldIsDown(keyCode: keyCode, nsEventFlags: NSEvent.modifierFlags.rawValue))
        case .keyCombo(let mods, let keyCode):
            guard event.keyCode == keyCode, !event.isARepeat else { return }
            switch event.type {
            case .keyDown:
                guard HotkeyKeyMap.nsEventModifiersMatch(event.modifierFlags.rawValue, requiredCarbon: mods) else { return }
                updateHold(true)
            case .keyUp:
                guard holding else { return }
                updateHold(false)
            default:
                break
            }
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
