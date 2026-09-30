import Foundation
import Combine
import SwiftUI

/// Single source of truth for user preferences. Backed by `UserDefaults` so
/// SwiftUI views can also bind directly via `@AppStorage(SettingsStore.Keys.*)`.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    enum Keys {
        static let autoSendOnInvocation = "settings.autoSendOnInvocation"
        static let streamResponses = "settings.streamResponses"
        static let clipboardFallbackEnabled = "settings.clipboardFallbackEnabled"
        static let restoreClipboardAfterCapture = "settings.restoreClipboardAfterCapture"
        static let historyEnabled = "settings.historyEnabled"
        static let launchAtLogin = "settings.launchAtLogin"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let showMenuBarIcon = "settings.showMenuBarIcon"
        static let panelFontSize = "settings.panelFontSize"
        static let panelClickOffBehavior = "settings.panelClickOffBehavior"
        static let panelPlacement = "settings.panelPlacement"
        static let panelAppearanceMode = "settings.panelAppearanceMode"
        static let panelCustomBackgroundHex = "settings.panelCustomBackgroundHex"
        static let panelCustomTextHex = "settings.panelCustomTextHex"
        static let queryHistoryLimit = "settings.queryHistoryLimit"
    }

    /// Default cap for the per-preset query history dropdown shown in the
    /// panel. Small enough to keep the menu glanceable; users can raise it
    /// up to `queryHistoryLimitRange.upperBound` or set 0 to disable.
    static let defaultQueryHistoryLimit: Int = 10
    static let queryHistoryLimitRange: ClosedRange<Int> = 0...50

    /// Fallback hex values for the custom-colors mode.
    static let defaultPanelCustomBackgroundHex = "#1E1E1E"
    static let defaultPanelCustomTextHex = "#F5F5F5"

    /// How the floating panel's background and text are rendered.
    ///
    /// Named `PanelAppearanceMode` (not just `Appearance`) to avoid colliding
    /// with `SwiftUI.ColorScheme` / `NSAppearance` in autocomplete at call
    /// sites — this type controls *our* panel specifically.
    enum PanelAppearanceMode: String, CaseIterable, Identifiable {
        /// Translucent ultra-thin material — the current macOS "liquid
        /// glass" look that tracks system light/dark.
        case system
        /// Solid light background + dark text, regardless of system theme.
        case light
        /// Solid dark background + light text, regardless of system theme.
        case dark
        /// User-supplied hex values for background and text.
        case custom

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "System (translucent)"
            case .light:  return "Light (opaque)"
            case .dark:   return "Dark (opaque)"
            case .custom: return "Custom colors"
            }
        }
    }

    /// Where the floating panel appears on invocation.
    enum PanelPlacement: String, CaseIterable, Identifiable {
        /// Anchored just below+right of the mouse cursor (current default).
        case nearMouse
        /// Centered on the mouse cursor.
        case centeredOnCursor
        /// Centered on the active screen.
        case centeredOnScreen

        var id: String { rawValue }

        var label: String {
            switch self {
            case .nearMouse:         return "Near cursor (default)"
            case .centeredOnCursor:  return "Centered on cursor"
            case .centeredOnScreen:  return "Centered on screen"
            }
        }
    }

    /// How the floating panel reacts when the user clicks outside it.
    enum PanelClickOffBehavior: String, CaseIterable, Identifiable {
        /// Panel remains `.floating` above other windows until explicitly dismissed.
        case stayOnTop
        /// Panel drops to `.normal` window level and recedes behind the newly
        /// active app, matching typical Mac window behaviour.
        case sendToBack
        /// Panel dismisses itself on click-off.
        case closePanel

        var id: String { rawValue }

        var label: String {
            switch self {
            case .stayOnTop:  return "Stay on top"
            case .sendToBack: return "Recede to background"
            case .closePanel: return "Close"
            }
        }
    }

    /// Default body font size for the response area. Tuned for power-user
    /// glanceability — small enough to fit a paragraph at a glance, large
    /// enough to stay readable. User-overridable in Settings → General.
    static let defaultPanelFontSize: Double = 13
    static let panelFontSizeRange: ClosedRange<Double> = 11...18

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.autoSendOnInvocation: true,
            Keys.streamResponses: true,
            Keys.clipboardFallbackEnabled: true,
            Keys.restoreClipboardAfterCapture: true,
            Keys.historyEnabled: false,
            Keys.launchAtLogin: false,
            Keys.hasCompletedOnboarding: false,
            Keys.showMenuBarIcon: true,
            Keys.panelFontSize: SettingsStore.defaultPanelFontSize,
            Keys.panelClickOffBehavior: PanelClickOffBehavior.stayOnTop.rawValue,
            Keys.panelPlacement: PanelPlacement.nearMouse.rawValue,
            Keys.panelAppearanceMode: PanelAppearanceMode.system.rawValue,
            Keys.panelCustomBackgroundHex: SettingsStore.defaultPanelCustomBackgroundHex,
            Keys.panelCustomTextHex: SettingsStore.defaultPanelCustomTextHex,
            Keys.queryHistoryLimit: SettingsStore.defaultQueryHistoryLimit
        ])
    }

    // MARK: - Typed accessors

    var autoSendOnInvocation: Bool {
        get { defaults.bool(forKey: Keys.autoSendOnInvocation) }
        set { defaults.set(newValue, forKey: Keys.autoSendOnInvocation); objectWillChange.send() }
    }

    var streamResponses: Bool {
        get { defaults.bool(forKey: Keys.streamResponses) }
        set { defaults.set(newValue, forKey: Keys.streamResponses); objectWillChange.send() }
    }

    var clipboardFallbackEnabled: Bool {
        get { defaults.bool(forKey: Keys.clipboardFallbackEnabled) }
        set { defaults.set(newValue, forKey: Keys.clipboardFallbackEnabled); objectWillChange.send() }
    }

    var restoreClipboardAfterCapture: Bool {
        get { defaults.bool(forKey: Keys.restoreClipboardAfterCapture) }
        set { defaults.set(newValue, forKey: Keys.restoreClipboardAfterCapture); objectWillChange.send() }
    }

    var historyEnabled: Bool {
        get { defaults.bool(forKey: Keys.historyEnabled) }
        set { defaults.set(newValue, forKey: Keys.historyEnabled); objectWillChange.send() }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set {
            defaults.set(newValue, forKey: Keys.launchAtLogin)
            LaunchAtLogin.set(enabled: newValue)
            objectWillChange.send()
        }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding); objectWillChange.send() }
    }

    var showMenuBarIcon: Bool {
        get { defaults.bool(forKey: Keys.showMenuBarIcon) }
        set { defaults.set(newValue, forKey: Keys.showMenuBarIcon); objectWillChange.send() }
    }

    var panelFontSize: Double {
        get {
            let v = defaults.double(forKey: Keys.panelFontSize)
            return v == 0 ? SettingsStore.defaultPanelFontSize : v
        }
        set { defaults.set(newValue, forKey: Keys.panelFontSize); objectWillChange.send() }
    }

    var panelPlacement: PanelPlacement {
        get {
            let raw = defaults.string(forKey: Keys.panelPlacement) ?? ""
            return PanelPlacement(rawValue: raw) ?? .nearMouse
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.panelPlacement)
            objectWillChange.send()
        }
    }

    var panelAppearanceMode: PanelAppearanceMode {
        get {
            let raw = defaults.string(forKey: Keys.panelAppearanceMode) ?? ""
            return PanelAppearanceMode(rawValue: raw) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.panelAppearanceMode)
            objectWillChange.send()
        }
    }

    var panelCustomBackgroundHex: String {
        get { defaults.string(forKey: Keys.panelCustomBackgroundHex) ?? SettingsStore.defaultPanelCustomBackgroundHex }
        set { defaults.set(newValue, forKey: Keys.panelCustomBackgroundHex); objectWillChange.send() }
    }

    var panelCustomTextHex: String {
        get { defaults.string(forKey: Keys.panelCustomTextHex) ?? SettingsStore.defaultPanelCustomTextHex }
        set { defaults.set(newValue, forKey: Keys.panelCustomTextHex); objectWillChange.send() }
    }

    var queryHistoryLimit: Int {
        get {
            let raw = defaults.integer(forKey: Keys.queryHistoryLimit)
            // `integer(forKey:)` returns 0 for both "absent" and "explicitly 0".
            // The registered default disambiguates absent → default; explicit
            // 0 means the user disabled history.
            if defaults.object(forKey: Keys.queryHistoryLimit) == nil {
                return SettingsStore.defaultQueryHistoryLimit
            }
            return min(max(raw, SettingsStore.queryHistoryLimitRange.lowerBound),
                       SettingsStore.queryHistoryLimitRange.upperBound)
        }
        set {
            defaults.set(newValue, forKey: Keys.queryHistoryLimit)
            objectWillChange.send()
        }
    }

    var panelClickOffBehavior: PanelClickOffBehavior {
        get {
            let raw = defaults.string(forKey: Keys.panelClickOffBehavior) ?? ""
            return PanelClickOffBehavior(rawValue: raw) ?? .stayOnTop
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.panelClickOffBehavior)
            objectWillChange.send()
        }
    }
}
