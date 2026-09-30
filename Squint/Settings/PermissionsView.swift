import SwiftUI
import AppKit

struct PermissionsView: View {
    @State private var trusted: Bool = AccessibilityCapture.isTrusted

    var body: some View {
        Form {
            Section("Accessibility") {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? "Granted" : "Not granted")
                    Spacer()
                    Button("Recheck") { trusted = AccessibilityCapture.isTrusted }
                    Button("Open System Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }
                }
                Text("To read selected text when you use the hotkey, Squint needs Accessibility permission. You can still use the right-click Services action without it in apps that support Services.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Network") {
                Text("API calls go directly from this Mac to your configured LLM provider. No backend, no telemetry.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}
