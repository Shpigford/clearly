import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let newScratchpad = Self("newScratchpad", default: .init(.n, modifiers: [.control, .option, .command]))
}

@MainActor
private func swiftUIShortcut(for name: KeyboardShortcuts.Name) -> (KeyEquivalent, EventModifiers)? {
    guard let shortcut = KeyboardShortcuts.getShortcut(for: name),
          let keyStr = shortcut.nsMenuItemKeyEquivalent,
          let char = keyStr.first else { return nil }
    var mods: EventModifiers = []
    let flags = shortcut.modifiers
    if flags.contains(.command) { mods.insert(.command) }
    if flags.contains(.option) { mods.insert(.option) }
    if flags.contains(.control) { mods.insert(.control) }
    if flags.contains(.shift) { mods.insert(.shift) }
    return (KeyEquivalent(char), mods)
}

extension View {
    @ViewBuilder
    func keyboardShortcut(for name: KeyboardShortcuts.Name) -> some View {
        if let (key, mods) = swiftUIShortcut(for: name) {
            self.keyboardShortcut(key, modifiers: mods)
        } else {
            self
        }
    }
}
