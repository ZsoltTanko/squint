import SwiftUI

struct CaptureSettingsView: View {
    @AppStorage(SettingsStore.Keys.clipboardFallbackEnabled) private var clipboardFallback: Bool = false
    @AppStorage(SettingsStore.Keys.restoreClipboardAfterCapture) private var restoreClipboard: Bool = true

    var body: some View {
        Form {
            Section("Accessibility") {
                HStack {
                    Image(systemName: AccessibilityCapture.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(AccessibilityCapture.isTrusted ? .green : .orange)
                    Text(AccessibilityCapture.isTrusted ? "Accessibility access granted" : "Accessibility access not granted")
                    Spacer()
                    if !AccessibilityCapture.isTrusted {
                        Button("Request") { AccessibilityCapture.requestTrust() }
                    }
                }
                Text("Required for the global hotkey to read selected text. The right-click Services action does not require this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Clipboard fallback") {
                Toggle("Enable clipboard fallback (simulates Cmd+C)", isOn: $clipboardFallback)
                Toggle("Restore previous clipboard after capture", isOn: $restoreClipboard)
                    .disabled(!clipboardFallback)
                Text("Off by default. When on, the app temporarily takes the system clipboard when the hotkey can't read selected text directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Context") {
                Text("Frontmost app and window title are available to prompt presets via the {{app}} and {{windowTitle}} variables. Add them to a preset's system prompt where useful.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
