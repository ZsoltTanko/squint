import SwiftUI
import AppKit

/// How the panel's chrome should render, distilled from the user's settings
/// into values `PanelView` and `MarkdownResponseView` can apply directly.
///
/// Separated from `SettingsStore.PanelAppearanceMode` because the *setting*
/// is a small enum, whereas the *resolved* appearance is a bag of concrete
/// style values (background kind, explicit text color, forced colorScheme).
/// Keeping them distinct avoids cramming UI concerns into the preferences
/// layer and mirrors the pattern used for `PanelPlacement`.
struct PanelResolvedAppearance: Equatable {
    /// What to fill the panel background with.
    enum BackgroundFill: Equatable {
        /// Translucent `.ultraThinMaterial` — the current macOS default.
        case translucentMaterial
        /// Opaque solid color (light, dark, or user-chosen).
        case solid(Color)
    }

    let backgroundFill: BackgroundFill
    /// When non-nil, overrides `.primary` text color throughout the panel.
    /// `nil` means "follow the system / forced colorScheme".
    let foregroundColor: Color?
    /// When non-nil, the panel forces this colorScheme on its subtree so
    /// system-colored controls (icons, borders) read correctly against the
    /// chosen background.
    let forcedColorScheme: ColorScheme?
}

enum PanelAppearanceResolver {
    static func resolve(
        mode: SettingsStore.PanelAppearanceMode,
        customBackgroundHex: String,
        customTextHex: String
    ) -> PanelResolvedAppearance {
        switch mode {
        case .system:
            return PanelResolvedAppearance(
                backgroundFill: .translucentMaterial,
                foregroundColor: nil,
                forcedColorScheme: nil
            )
        case .light:
            return PanelResolvedAppearance(
                backgroundFill: .solid(Color(NSColor.windowBackgroundColor)),
                foregroundColor: nil,
                forcedColorScheme: .light
            )
        case .dark:
            return PanelResolvedAppearance(
                backgroundFill: .solid(Color(NSColor.windowBackgroundColor)),
                foregroundColor: nil,
                forcedColorScheme: .dark
            )
        case .custom:
            let bgColor  = Color(hexString: customBackgroundHex) ?? .black
            let txtColor = Color(hexString: customTextHex)       ?? .white
            // Pick a colorScheme that matches the chosen background so
            // system-drawn affordances (focus rings, secondary labels,
            // chevrons) remain legible.
            let scheme: ColorScheme =
                HexColor.perceivedLuminance(of: customBackgroundHex) > 0.5
                    ? .light
                    : .dark
            return PanelResolvedAppearance(
                backgroundFill: .solid(bgColor),
                foregroundColor: txtColor,
                forcedColorScheme: scheme
            )
        }
    }
}

/// Hex-string helpers. Namespaced under `HexColor` rather than declaring
/// free functions named `hex`/`color` to avoid name collisions in call
/// sites.
enum HexColor {
    /// Returns true if `candidate` is a syntactically valid `#RGB`, `#RRGGBB`,
    /// or `#RRGGBBAA` string (leading `#` optional).
    static func isValid(_ candidate: String) -> Bool {
        parseComponents(candidate) != nil
    }

    /// Perceived luminance in [0, 1] via the Rec.709 coefficients. Used to
    /// decide whether to force a light or dark `ColorScheme` over a custom
    /// background. Returns 0 for unparseable input.
    static func perceivedLuminance(of hexString: String) -> Double {
        guard let (r, g, b, _) = parseComponents(hexString) else { return 0 }
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Parses `#RGB`, `#RRGGBB`, or `#RRGGBBAA` into (r, g, b, a) in [0, 1].
    fileprivate static func parseComponents(_ hexString: String) -> (Double, Double, Double, Double)? {
        var trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.range(of: "^[0-9A-Fa-f]+$", options: .regularExpression) != nil else {
            return nil
        }

        let expanded: String
        switch trimmed.count {
        case 3:
            // #RGB → #RRGGBB
            expanded = trimmed.map { "\($0)\($0)" }.joined()
        case 6, 8:
            expanded = trimmed
        default:
            return nil
        }

        guard let packed = UInt64(expanded, radix: 16) else { return nil }

        let red, green, blue, alpha: Double
        if expanded.count == 8 {
            red   = Double((packed >> 24) & 0xFF) / 255.0
            green = Double((packed >> 16) & 0xFF) / 255.0
            blue  = Double((packed >>  8) & 0xFF) / 255.0
            alpha = Double( packed        & 0xFF) / 255.0
        } else {
            red   = Double((packed >> 16) & 0xFF) / 255.0
            green = Double((packed >>  8) & 0xFF) / 255.0
            blue  = Double( packed        & 0xFF) / 255.0
            alpha = 1.0
        }
        return (red, green, blue, alpha)
    }
}

extension Color {
    /// Parses `#RGB`, `#RRGGBB`, or `#RRGGBBAA`. Returns `nil` on bad input.
    init?(hexString: String) {
        guard let (r, g, b, a) = HexColor.parseComponents(hexString) else { return nil }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
