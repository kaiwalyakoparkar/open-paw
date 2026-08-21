import Foundation

public enum HoldKeyKind: Equatable {
    case modifierOnly(keyCode: UInt16)
    case modifierChord(carbonModifiers: UInt32)
    case keyCombo(carbonModifiers: UInt32, keyCode: UInt16)
}

/// Maps config key names to Carbon virtual key codes.
/// ponytail: ~10-key map only; extend when users ask for exotic bindings.
public enum HotkeyKeyMap {
    public static func holdKeyKind(for combo: KeyCombo) -> HoldKeyKind? {
        switch combo.key.lowercased() {
        case "right_option", "rightoption":
            return .modifierOnly(keyCode: 61)
        case "left_option", "leftoption":
            return .modifierOnly(keyCode: 58)
        case "fn", "function", "globe":
            return .modifierOnly(keyCode: 63)
        case "", "option", "alt":
            var names = combo.modifiers
            if combo.key.lowercased() == "option" || combo.key.lowercased() == "alt" {
                names.append("option")
            }
            let mods = carbonModifiers(from: names)
            return mods == 0 ? nil : .modifierChord(carbonModifiers: mods)
        default:
            guard let vk = virtualKeyCode(for: combo.key) else { return nil }
            return .keyCombo(carbonModifiers: carbonModifiers(from: combo.modifiers), keyCode: UInt16(vk))
        }
    }

    public static func displayLabel(for combo: KeyCombo) -> String {
        switch combo.key.lowercased() {
        case "right_option", "rightoption", "left_option", "leftoption":
            return "⌥"
        case "fn", "function", "globe":
            return "fn"
        default:
            var parts: [String] = []
            for m in combo.modifiers {
                switch m.lowercased() {
                case "control", "ctrl": parts.append("⌃")
                case "option", "alt": parts.append("⌥")
                case "shift": parts.append("⇧")
                case "command", "cmd": parts.append("⌘")
                default: break
                }
            }
            switch combo.key.lowercased() {
            case "option", "alt":
                if !parts.contains("⌥") { parts.append("⌥") }
            case "":
                break
            default:
                parts.append(combo.key.uppercased())
            }
            return parts.joined()
        }
    }

    /// NSEvent.ModifierFlags bits: shift=17, control=18, option=19, command=20.
    /// Carbon bits: cmd=8, shift=9, option=11, control=12. Never compare them raw.
    public static func nsEventModifiersMatch(_ nsEventRaw: UInt, requiredCarbon: UInt32) -> Bool {
        var bits: UInt32 = 0
        if nsEventRaw & (1 << 18) != 0 { bits |= 1 << 12 }
        if nsEventRaw & (1 << 19) != 0 { bits |= 1 << 11 }
        if nsEventRaw & (1 << 17) != 0 { bits |= 1 << 9 }
        if nsEventRaw & (1 << 20) != 0 { bits |= 1 << 8 }
        let mask: UInt32 = (1 << 8) | (1 << 9) | (1 << 11) | (1 << 12)
        return (bits & mask & requiredCarbon) == (requiredCarbon & mask)
    }

    /// Left Option (58) and right Option (61) both set the Option flag.
    /// Pill label is ⌥ — either key must start hold.
    public static func modifierHoldEventApplies(eventKeyCode: UInt16, configured: UInt16) -> Bool {
        let option: Set<UInt16> = [58, 61]
        if option.contains(configured) { return option.contains(eventKeyCode) }
        return eventKeyCode == configured
    }

    /// Use live NSEvent.modifierFlags, not the event's bits — orderFront
    /// sends flagsChanged with empty bits while the key is still down.
    public static func modifierHoldIsDown(keyCode: UInt16, nsEventFlags: UInt) -> Bool {
        switch keyCode {
        case 58, 61: return nsEventFlags & (1 << 19) != 0
        case 63: return nsEventFlags & (1 << 23) != 0
        default: return false
        }
    }

    public static func virtualKeyCode(for name: String) -> UInt32? {
        switch name.lowercased() {
        case "space": return 49
        case "a": return 0
        case "s": return 1
        case "d": return 2
        case "f": return 3
        case "q": return 12
        case "w": return 13
        case "e": return 14
        case "r": return 15
        case "f1": return 122
        case "f2": return 120
        case "f3": return 99
        case "f4": return 118
        default: return nil
        }
    }

    public static func carbonModifiers(from names: [String]) -> UInt32 {
        var bits: UInt32 = 0
        for name in names {
            switch name.lowercased() {
            case "control", "ctrl": bits |= 1 << 12 // controlKey
            case "option", "alt": bits |= 1 << 11 // optionKey
            case "shift": bits |= 1 << 9 // shiftKey
            case "command", "cmd": bits |= 1 << 8 // cmdKey
            default: break
            }
        }
        return bits
    }
}

/// Nested `.bundle` in Contents/MacOS makes `codesign` fail ("bundle format unrecognized").
public enum AppBundleLayout {
    public static func macOSAllows(_ name: String) -> Bool {
        !name.hasSuffix(".bundle")
    }
}

/// Debounce modifier-hold release so a 0-flag sample (orderFront) does not end PTT.
public struct HoldGate {
    public private(set) var down = false
    private var offStreak = 0
    private let releaseTicks: Int

    public init(releaseTicks: Int = 4) {
        self.releaseTicks = max(releaseTicks, 1)
    }

    /// `true` on press, `false` on release, `nil` if unchanged.
    public mutating func sample(_ pressed: Bool) -> Bool? {
        if pressed {
            offStreak = 0
            guard !down else { return nil }
            down = true
            return true
        }
        guard down else { return nil }
        offStreak += 1
        guard offStreak >= releaseTicks else { return nil }
        down = false
        offStreak = 0
        return false
    }
}
