import Foundation
import KeyboardShortcuts

/// Owns the global hotkey bindings:
///
/// - The "ask" hotkey (`KeyboardShortcuts.Name.invokePanel`) opens the panel
///   with the user's default preset.
/// - Every preset additionally gets its own dynamically-registered hotkey
///   (`prompt.preset.<uuid>`); when set, pressing it presents the panel
///   pre-bound to that preset (respecting its `autoSend` flag).
///
/// IMPORTANT: `KeyboardShortcuts.onKeyDown(for:)` is additive — calling it
/// twice for the same `Name` installs two handlers, and the library has no
/// public per-name removal API. The manager therefore keeps its own handler
/// bookkeeping and uses `removeAllHandlers()` to clear the slate before
/// every full re-registration. Any caller that wants to change bindings
/// must go through `syncPresetHotkeys(...)`.
final class HotkeyManager {
    private let onInvoke: () -> Void
    private let onInvokePreset: (PromptPreset) -> Void

    private var registeredPresetNames: Set<String> = []

    init(onInvoke: @escaping () -> Void, onInvokePreset: @escaping (PromptPreset) -> Void) {
        self.onInvoke = onInvoke
        self.onInvokePreset = onInvokePreset
    }

    /// Installs the global "ask" hotkey. Per-preset bindings are added later
    /// via `syncPresetHotkeys(...)` once the preset catalog is known.
    func start() {
        KeyboardShortcuts.onKeyDown(for: .invokePanel) { [weak self] in
            self?.onInvoke()
        }
    }

    func stop() {
        KeyboardShortcuts.removeAllHandlers()
        registeredPresetNames.removeAll()
    }

    /// Re-binds global + per-preset hotkeys to match the supplied catalog.
    /// Safe to call repeatedly — all existing handlers are torn down first,
    /// so we never accumulate duplicate callbacks for the same shortcut.
    /// Bindings whose preset was deleted are dropped; new presets gain a
    /// callback. The underlying shortcut *value* is persisted by the
    /// KeyboardShortcuts library in UserDefaults under the preset's stable
    /// name, so it survives renames and relaunches.
    func syncPresetHotkeys(presets: [PromptPreset], invoke: @escaping (PromptPreset) -> Void) {
        // Full reset. Slightly wasteful (we also re-install the global
        // handler below) but avoids a whole class of accumulation bugs.
        KeyboardShortcuts.removeAllHandlers()

        // Re-install the global hotkey callback.
        KeyboardShortcuts.onKeyDown(for: .invokePanel) { [weak self] in
            self?.onInvoke()
        }

        // Install one callback per preset. Captured `preset` is a value
        // type; `invoke` is the escaping closure the caller supplied.
        for preset in presets {
            let name = KeyboardShortcuts.Name(preset.hotkeyShortcutKey)
            KeyboardShortcuts.onKeyDown(for: name) { [preset, invoke] in
                invoke(preset)
            }
        }
        registeredPresetNames = Set(presets.map { $0.hotkeyShortcutKey })
    }
}
