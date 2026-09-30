import AppKit
import SwiftUI

enum OnboardingWindow {
    private static var window: NSWindow?

    @MainActor
    static func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(onFinish: {
            SettingsStore.shared.hasCompletedOnboarding = true
            window?.close()
            window = nil
        })
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "Welcome to Squint"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 480, height: 360))
        win.center()
        win.isReleasedWhenClosed = false
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var step: Int = 0

    private let steps: [(title: String, body: String)] = [
        ("Add a model", "Open Settings → Models and add a provider. Squint supports any OpenAI-compatible endpoint (OpenAI, OpenRouter, Ollama, LM Studio, …)."),
        ("Set your hotkey", "In Settings → General, pick a global hotkey. Default is Option+Space."),
        ("Enable Accessibility", "In Settings → Permissions, grant Accessibility access so the hotkey can read selected text. The right-click Services action works without it."),
        ("Try it", "Select text in any app and press the hotkey, or right-click → Services → Ask Squint.")
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome").font(.title2).bold()
            VStack(alignment: .leading, spacing: 6) {
                Text(steps[step].title).font(.headline)
                Text(steps[step].body).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            HStack {
                Button("Skip", action: onFinish)
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                if step < steps.count - 1 {
                    Button("Next") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done", action: onFinish)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
    }
}
