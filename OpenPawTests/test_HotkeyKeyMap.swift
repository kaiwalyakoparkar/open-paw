import OpenPawCore
import Foundation

enum HotkeyKeyMapChecks {
    static func run() {
        let required = HotkeyKeyMap.carbonModifiers(from: ["control", "option"])
        // NSEvent.ModifierFlags: control=1<<18, option=1<<19
        let nsControlOption: UInt = (1 << 18) | (1 << 19)
        assert(HotkeyKeyMap.nsEventModifiersMatch(nsControlOption, requiredCarbon: required))
        assert(!HotkeyKeyMap.nsEventModifiersMatch(1 << 18, requiredCarbon: required))
        assert(!HotkeyKeyMap.nsEventModifiersMatch(0, requiredCarbon: required))

        // Pill shows ⌥ for right_option — left Option (58) must count too.
        assert(HotkeyKeyMap.modifierHoldEventApplies(eventKeyCode: 58, configured: 61))
        assert(HotkeyKeyMap.modifierHoldEventApplies(eventKeyCode: 61, configured: 58))
        assert(HotkeyKeyMap.modifierHoldEventApplies(eventKeyCode: 61, configured: 61))
        assert(!HotkeyKeyMap.modifierHoldEventApplies(eventKeyCode: 63, configured: 61))
        // Window orderFront sends flagsChanged with empty bits while Option still held.
        let optionBit: UInt = 1 << 19
        assert(HotkeyKeyMap.modifierHoldIsDown(keyCode: 61, nsEventFlags: optionBit))
        assert(HotkeyKeyMap.modifierHoldIsDown(keyCode: 58, nsEventFlags: optionBit))
        assert(!HotkeyKeyMap.modifierHoldIsDown(keyCode: 61, nsEventFlags: 0))

        let space = HotkeyKeyMap.holdKeyKind(for: KeyCombo(modifiers: ["control", "option"], key: "space"))
        if case .keyCombo(let mods, let code) = space {
            assert(mods == required)
            assert(code == 49)
        } else {
            assertionFailure("expected keyCombo for control+option+space")
        }
        print("HotkeyKeyMap OK")
    }
}
