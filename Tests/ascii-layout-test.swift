import AppKit
import Carbon.HIToolbox
import SwiftUI

/// `UCKeyTranslate` answers a named key's keycode with a control character the ASCII test admits.
@main
@MainActor
struct ASCIILayoutTests {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ ok: Bool) {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)")
        }
    }

    /// What `UCKeyTranslate` hands back for each keycode under ⌘, against SwiftUI's own spelling.
    static let namedKeys: [(name: String, key: KeyEquivalent, translated: Character)] = [
        ("↑", .upArrow, "\u{1e}"),
        ("↓", .downArrow, "\u{1f}"),
        ("←", .leftArrow, "\u{1c}"),
        ("→", .rightArrow, "\u{1d}"),
        ("⌦", .deleteForward, "\u{7f}"),
        ("⇞", .pageUp, "\u{b}"),
        ("⇟", .pageDown, "\u{c}"),
        ("↖", .home, "\u{1}"),
        ("↘", .end, "\u{4}")
    ]

    /// These four agree with SwiftUI already, and must keep resolving once the arrows are excluded.
    static let controlKeys: [(name: String, key: KeyEquivalent, translated: Character)] = [
        ("↩", .return, "\u{d}"),
        ("⌫", .delete, "\u{8}"),
        ("⇥", .tab, "\u{9}"),
        ("⎋", .escape, "\u{1b}")
    ]

    /// ⌘ plus a keycode, the shape `ExtensionShortcutKeys` hands the recovery every key press.
    static func chord(_ keyCode: Int, _ flags: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
            keyCode: UInt16(keyCode))
    }

    /// The caller path, so a regression between the guard and `recovered` cannot hide behind it.
    static func callerPath() {
        print("\n# the whole recovery, over a synthesized chord")
        guard let translated = ASCIIKeyboardLayout.character(
            for: kVK_UpArrow, modifiers: UInt32(cmdKey >> 8))?.first
        else {
            check("this Mac's layout translates ⌘↑ at all, or the cases below prove nothing", false)
            return
        }
        let isASCIIControl = translated.unicodeScalars.allSatisfy {
            $0.isASCII && $0.properties.generalCategory == .control
        }
        check("the layout answers ⌘↑ with a control character, which is the trap", isASCIIControl)

        guard let up = chord(kVK_UpArrow, [.command]),
            let left = chord(kVK_LeftArrow, [.control]),
            let plain = chord(kVK_UpArrow, [.option])
        else {
            check("AppKit builds a synthetic key event", false)
            return
        }
        check(
            "⌘↑ reaches the action as ↑",
            ASCIIKeyboardLayout.keyEquivalent(fallingBackTo: .upArrow, event: up) == .upArrow)
        check(
            "⌃← reaches the action as ←",
            ASCIIKeyboardLayout.keyEquivalent(fallingBackTo: .leftArrow, event: left) == .leftArrow)
        check(
            "⌥↑ never consulted the layout, and still does not",
            ASCIIKeyboardLayout.keyEquivalent(fallingBackTo: .upArrow, event: plain) == .upArrow)
    }

    static func main() {
        print("# a named key is never recovered from the layout")
        for entry in namedKeys {
            check(
                "\(entry.name) keeps SwiftUI's key",
                ASCIIKeyboardLayout.recovered(entry.key, layoutCharacter: entry.translated)
                    == entry.key)
        }

        print("\n# a key whose control character is already SwiftUI's still resolves")
        for entry in controlKeys {
            check(
                "\(entry.name) resolves to itself",
                ASCIIKeyboardLayout.recovered(entry.key, layoutCharacter: entry.translated)
                    == entry.key)
        }

        print("\n# the recovery still does its job")
        check(
            "a non-QWERTY layout recovers the logical key",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("t"), layoutCharacter: "k")
                == KeyEquivalent("k"))
        check(
            "a non-ASCII layout character falls back to SwiftUI's key",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("k"), layoutCharacter: "ц")
                == KeyEquivalent("k"))
        check(
            "no layout character falls back to SwiftUI's key",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("k"), layoutCharacter: nil)
                == KeyEquivalent("k"))
        check(
            "a shifted letter is still spelled lower case",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("C"), layoutCharacter: nil)
                == KeyEquivalent("c"))

        callerPath()

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
