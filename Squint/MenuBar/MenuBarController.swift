import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let presetStore: PromptPresetStore
    private let onAsk: () -> Void
    private let onAskWithPreset: (PromptPreset) -> Void
    private let onSettings: () -> Void
    private let onPermissions: () -> Void
    private let onQuit: () -> Void

    init(
        presetStore: PromptPresetStore,
        onAsk: @escaping () -> Void,
        onAskWithPreset: @escaping (PromptPreset) -> Void,
        onSettings: @escaping () -> Void,
        onPermissions: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.presetStore = presetStore
        self.onAsk = onAsk
        self.onAskWithPreset = onAskWithPreset
        self.onSettings = onSettings
        self.onPermissions = onPermissions
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            // A half-closed eye — a squint. That symbol ships with macOS 26;
            // earlier systems fall back to the plain eye.
            let image = NSImage(systemSymbolName: "eye.half.closed", accessibilityDescription: "Squint")
                ?? NSImage(systemSymbolName: "eye", accessibilityDescription: "Squint")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Squint"
        }

        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let askItem = NSMenuItem(title: "Ask Squint", action: #selector(handleAsk), keyEquivalent: "")
        askItem.target = self
        menu.addItem(askItem)

        let presetSubmenu = NSMenu(title: "Prompt presets")
        let presets = presetStore.sortedPresets
        if presets.isEmpty {
            let none = NSMenuItem(title: "No presets", action: nil, keyEquivalent: "")
            none.isEnabled = false
            presetSubmenu.addItem(none)
        } else {
            for preset in presets {
                let item = NSMenuItem(title: preset.name, action: #selector(handlePreset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset
                if presetStore.defaultPresetID == preset.id {
                    item.state = .on
                }
                presetSubmenu.addItem(item)
            }
        }
        let presetParent = NSMenuItem(title: "Ask with preset", action: nil, keyEquivalent: "")
        presetParent.submenu = presetSubmenu
        menu.addItem(presetParent)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(handleSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let permsItem = NSMenuItem(title: "Check Permissions", action: #selector(handlePermissions), keyEquivalent: "")
        permsItem.target = self
        menu.addItem(permsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func handleAsk() { onAsk() }
    @objc private func handleSettings() { onSettings() }
    @objc private func handlePermissions() { onPermissions() }
    @objc private func handleQuit() { onQuit() }
    @objc private func handlePreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? PromptPreset else { return }
        onAskWithPreset(preset)
    }
}
