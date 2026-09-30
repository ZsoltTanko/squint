import SwiftUI
import KeyboardShortcuts

struct GeneralSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @AppStorage(SettingsStore.Keys.autoSendOnInvocation) private var autoSend: Bool = true
    @AppStorage(SettingsStore.Keys.streamResponses) private var streamResponses: Bool = true
    @AppStorage(SettingsStore.Keys.historyEnabled) private var historyEnabled: Bool = false
    @AppStorage(SettingsStore.Keys.queryHistoryLimit) private var queryHistoryLimit: Int = SettingsStore.defaultQueryHistoryLimit
    @AppStorage(SettingsStore.Keys.launchAtLogin) private var launchAtLogin: Bool = false
    @AppStorage(SettingsStore.Keys.panelFontSize) private var panelFontSize: Double = SettingsStore.defaultPanelFontSize
    @AppStorage(SettingsStore.Keys.panelClickOffBehavior) private var clickOffBehaviorRaw: String = SettingsStore.PanelClickOffBehavior.stayOnTop.rawValue
    @AppStorage(SettingsStore.Keys.panelPlacement) private var panelPlacementRaw: String = SettingsStore.PanelPlacement.nearMouse.rawValue
    @AppStorage(SettingsStore.Keys.panelAppearanceMode) private var panelAppearanceModeRaw: String = SettingsStore.PanelAppearanceMode.system.rawValue
    @AppStorage(SettingsStore.Keys.panelCustomBackgroundHex) private var panelCustomBackgroundHex: String = SettingsStore.defaultPanelCustomBackgroundHex
    @AppStorage(SettingsStore.Keys.panelCustomTextHex) private var panelCustomTextHex: String = SettingsStore.defaultPanelCustomTextHex

    var body: some View {
        Form {
            Section("Invocation") {
                KeyboardShortcuts.Recorder("Global hotkey", name: .invokePanel)
                Toggle("Auto-send when invoked with selected text", isOn: $autoSend)
                Text("Per-preset hotkeys are configured in the Prompts tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Response") {
                Toggle("Stream responses", isOn: $streamResponses)
            }

            Section("Appearance") {
                HStack {
                    Text("Panel font size")
                    Slider(
                        value: $panelFontSize,
                        in: SettingsStore.panelFontSizeRange,
                        step: 1
                    )
                    Text("\(Int(panelFontSize)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                Text("Default \(Int(SettingsStore.defaultPanelFontSize)) pt. Affects the response text in the floating panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Panel theme", selection: Binding(
                    get: {
                        SettingsStore.PanelAppearanceMode(rawValue: panelAppearanceModeRaw) ?? .system
                    },
                    set: { newValue in
                        panelAppearanceModeRaw = newValue.rawValue
                    }
                )) {
                    ForEach(SettingsStore.PanelAppearanceMode.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                if (SettingsStore.PanelAppearanceMode(rawValue: panelAppearanceModeRaw) ?? .system) == .custom {
                    customColorsEditor
                }
            }

            Section("Window behaviour") {
                Picker("Panel placement on invocation", selection: Binding(
                    get: {
                        SettingsStore.PanelPlacement(rawValue: panelPlacementRaw) ?? .nearMouse
                    },
                    set: { newValue in
                        panelPlacementRaw = newValue.rawValue
                    }
                )) {
                    ForEach(SettingsStore.PanelPlacement.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                Picker("When clicking outside the panel", selection: Binding(
                    get: {
                        SettingsStore.PanelClickOffBehavior(rawValue: clickOffBehaviorRaw) ?? .stayOnTop
                    },
                    set: { newValue in
                        clickOffBehaviorRaw = newValue.rawValue
                    }
                )) {
                    ForEach(SettingsStore.PanelClickOffBehavior.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Text("Stay on top keeps the panel above other windows until you press Esc or close it. Recede to background behaves like a normal Mac window. Close dismisses the panel on click-off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Stepper(
                    value: $queryHistoryLimit,
                    in: SettingsStore.queryHistoryLimitRange
                ) {
                    HStack {
                        Text("Recent queries per preset")
                        Spacer()
                        Text(queryHistoryLimit == 0 ? "Off" : "\(queryHistoryLimit)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Powers the small clock-icon dropdown next to the captured selection in the panel. Set to 0 to disable. Stored only on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Keep full local history (off by default)", isOn: $historyEnabled)
                Text("Separate from the recent-queries dropdown above. When on, every invocation snapshots the resolved system prompt, user message, and full response to disk. No sync, no analytics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        settings.launchAtLogin = newValue
                    }
                ))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Custom colors editor

    @ViewBuilder
    private var customColorsEditor: some View {
        hexRow(
            label: "Background hex",
            placeholder: SettingsStore.defaultPanelCustomBackgroundHex,
            value: $panelCustomBackgroundHex
        )
        hexRow(
            label: "Text hex",
            placeholder: SettingsStore.defaultPanelCustomTextHex,
            value: $panelCustomTextHex
        )
        Text("Accepts #RGB, #RRGGBB, or #RRGGBBAA. Invalid values fall back to safe defaults.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func hexRow(label: String, placeholder: String, value: Binding<String>) -> some View {
        HStack {
            Text(label)
            TextField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: 140)
            swatch(for: value.wrappedValue)
            if !HexColor.isValid(value.wrappedValue) {
                Text("invalid")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func swatch(for hexString: String) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(hexString: hexString) ?? .gray)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
            .frame(width: 24, height: 16)
    }
}
