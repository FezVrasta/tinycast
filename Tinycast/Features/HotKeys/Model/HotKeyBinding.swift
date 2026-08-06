import Foundation

/// What an action is bound to: two kinds, two engines. See docs/hotkeys.md.
enum HotKeyBinding: Hashable, Sendable {
    case combo(KeyShortcut)
    case doubleTap(DoubleTapModifier)

    /// One string per keycap, so every display site renders both kinds through the same path.
    @MainActor var keycaps: [String] {
        switch self {
        case .combo(let shortcut): shortcut.keycaps
        case .doubleTap(let modifier): modifier.keycaps
        }
    }

    var shortcut: KeyShortcut? {
        if case .combo(let shortcut) = self { return shortcut }
        return nil
    }

    var doubleTapModifier: DoubleTapModifier? {
        if case .doubleTap(let modifier) = self { return modifier }
        return nil
    }
}

// The compatibility seam for both shapes. See docs/hotkeys.md#persistence.
extension HotKeyBinding: Codable {
    private enum CodingKeys: String, CodingKey {
        case doubleTapModifier
    }

    init(from decoder: Decoder) throws {
        if let shortcut = try? KeyShortcut(from: decoder) {
            self = .combo(shortcut)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .doubleTap(try container.decode(DoubleTapModifier.self, forKey: .doubleTapModifier))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .combo(let shortcut):
            try shortcut.encode(to: encoder)
        case .doubleTap(let modifier):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(modifier, forKey: .doubleTapModifier)
        }
    }
}
