import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let invokePanel = Self("invokePanel", default: .init(.space, modifiers: [.option]))
}

extension PromptPreset {
    /// Global hotkeys the factory seeds ship with, keyed by seed name.
    /// Explain has none of its own: as the default preset it already
    /// answers to `invokePanel` (⌥Space).
    ///
    /// Prompt deliberately avoids ⌃Space: that's code completion in VS Code,
    /// Xcode and JetBrains IDEs, and a global hotkey would swallow it in
    /// every editor.
    static let factorySeedHotkeys: [String: KeyboardShortcuts.Shortcut] = [
        "Ask": .init(.space, modifiers: [.option, .shift]),
        "Prompt": .init(.space, modifiers: [.control, .option])
    ]

    /// Binds a just-installed factory seed to its shipped hotkey. Called
    /// once per install, so a binding the user later changes or clears
    /// stays that way.
    static func bindFactoryHotkey(for seed: PromptPreset) {
        guard let shortcut = factorySeedHotkeys[seed.name] else { return }
        KeyboardShortcuts.setShortcut(shortcut, for: KeyboardShortcuts.Name(seed.hotkeyShortcutKey))
    }
}
