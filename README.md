# Squint

A native macOS menu-bar utility that turns selected text anywhere on screen into a lightweight, configurable, inline LLM interaction without opening a browser or full chat app.

## What it does

Select text in any app → trigger via global hotkey *or* right-click Services menu → see a small floating panel near your context with the LLM's answer streaming in. Read it, hit Esc to dismiss — that's the whole loop.

The panel is a chromeless, borderless surface: no title bar, no traffic-light buttons. The response is the primary element; configuration (preset chip, model chip, gear) sits in a slim strip at the top and stays out of the way. The follow-up bar is hidden by default and revealed only on demand.

The product is positioned as **an inline semantic lens**, closer to Spotlight / PopClip / Apple Dictionary lookup than to a full chat app. Optimized for low interaction friction, frequent invocation, and minimal visual disruption — specifically for power users who want a precisely configured LLM inline in fast workflows.

## Quick start (users)

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) once: `brew install xcodegen`.
2. Generate the Xcode project: `xcodegen generate`.
3. `open Squint.xcodeproj`, hit Cmd+R.
4. The app appears in the menu bar (no Dock icon — it's an `LSUIElement` agent).
5. Click the menu-bar icon → **Settings…** → **Models** → **+ Add Model** to configure your provider (OpenAI, OpenRouter, Ollama, LM Studio, etc.). API keys are stored in the macOS Keychain.
6. Click **Settings… → Permissions** to grant Accessibility access (only required for the global-hotkey path).
7. Select text in any app and either:
   - Press **Option+Space** (configurable in Settings → General), or
   - Right-click → **Services → Ask Squint**.

Three prompt presets ship seeded on first launch, covering the app's three input modalities:

- **Explain** — auto-sends with the captured selection. Pure "lens over selected text" mode.
- **Ask** — captures the selection *and* requires a user instruction (appended via `{{userInput}}` to the system prompt). Selection plus question.
- **Prompt** — skips selection capture entirely and is a direct chat-style wrapper: type a question, hit ⌘↵, get an answer. The user-input field becomes the LLM's user message.

All three are editable in **Settings → Prompts**. The mode is controlled by two per-preset toggles in the editor — *Capture selected text on invocation* and *Requires user input* — so any combination is reachable, not just the seeded three. New factory seeds shipped in a future release are added on next launch *only when no preset with the same name already exists* and *only the first time the seed is offered* (so a seed you delete stays gone). The user-input field grows vertically with content (up to ~30 lines, then the panel scrolls) so multi-paragraph prompts work cleanly.

**Panel keyboard shortcuts:**

| Key | Action |
| --- | --- |
| `Esc` | Close panel (or collapse follow-up if open) — works the moment the panel opens; no need to click into a field first. Closing the panel also cancels any in-flight LLM stream. |
| `⌘↵` | Send / Ask |
| `↵` | Send (when the preset's user-input field is focused; `Shift+↵` inserts a newline) |
| `⌘C` | Copy *selected* text from the response, or the whole response if nothing is selected |
| `⌘+` / `⌘=` | Increase response font size (clamped to the 11–18 pt range) |
| `⌘-` | Decrease response font size |
| `⌘L` | Open follow-up bar |
| `⌘,` | Open Settings (panel stays open behind the Settings window) |

**Settings → General → Window behaviour** controls where the panel appears and what happens when you click outside it:

- **Panel placement on invocation**: *Near cursor* (default) · *Centered on cursor* · *Centered on screen*. All three clamp to the active screen's visible frame.
- **When clicking outside the panel**: *Stay on top* (default, floating level until dismissed) · *Recede to background* (drops to normal window level, behaves like any Mac window) · *Close* (dismisses on click-off). Clicking into Settings (or any other of the app's own windows) never triggers the click-off behaviour.
- For *Stay on top* and *Recede to background*, the app temporarily promotes itself to a regular activation policy while the panel is alive, so it appears in **Cmd+Tab** and you can always bring it back to the foreground. *Close* keeps the lighter agent (`LSUIElement`) policy since the panel dismisses itself anyway.
- Click-off only changes window level/focus — it never cancels an in-flight LLM stream. The stream is cancelled only when you actually close the panel (Esc / ✕) or invoke a new query.

**Settings → General → History** controls a per-preset *recent queries* dropdown (small clock icon). For capturing presets it appears in the row next to the captured selection; for direct-prompt presets — which have no selection row — it appears at the right edge of the panel header instead. Picking an entry restores the panel exactly as you saw it for that invocation — selection text (or user input for direct-prompt), instruction field, model, and the streamed response — without re-running the LLM. Hit ⌘↵ if you want a fresh response. The integer setting caps how many entries are kept per preset (0 disables recording and hides the dropdown). Stored only on this Mac.

**Per-preset panel size.** In **Settings → Prompts → Edit**, each preset has an optional *Panel size* (width × height in points). Either dimension can be set independently — an unset one falls back to the default 460×380. Dragging the panel's edge to resize automatically saves the new size back to the active preset, so each preset opens at the size you last left it.

**Settings → General → Appearance** controls the panel's look:

- Font size (11–18 pt).
- **Panel theme**: *System (translucent)* default · *Light (opaque)* · *Dark (opaque)* · *Custom colors* (`#RGB`, `#RRGGBB`, or `#RRGGBBAA` for both background and text, with a live swatch). Custom mode picks a matching `ColorScheme` automatically from the background's perceived luminance so chrome (borders, chevrons, secondary labels) stays legible.

If a Service entry doesn't appear in the right-click menu, see [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md#services-menu-entry-doesnt-appear).

## Quick start (contributors)

For day-to-day iteration, the one command you need is:

```bash
./bin/dev-restart.sh
```

It regenerates the Xcode project if `project.yml` changed, kills any running copy, builds, re-registers with Launch Services (so the right-click Services menu picks up changes), and relaunches. See [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md#iteration-loop-terminal-driven) for what it does and why.

Then read these in order:

1. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — how the codebase is laid out, the request pipeline, key types, threading model.
2. [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — environment setup, build, run, test, debug, log capture.
3. [`docs/EXTENDING.md`](docs/EXTENDING.md) — recipes for adding a provider, prompt preset, or capture strategy.
4. [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — the hard-won macOS-specific gotchas this project has hit. Read this *before* you debug anything weird.

## Repository layout

```text
text-select-llm/
├── README.md                  This file
├── project.yml                XcodeGen spec; generates Squint.xcodeproj
├── .gitignore
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DEVELOPMENT.md
│   ├── EXTENDING.md
│   └── TROUBLESHOOTING.md
├── Squint/                    Application source (Swift, organized by feature module)
│   ├── App/                   App entry point, AppDelegate, Info.plist, entitlements
│   ├── MenuBar/               NSStatusItem + menu
│   ├── Hotkey/                Global hotkey via KeyboardShortcuts SPM package
│   ├── Services/              macOS Services / right-click integration
│   ├── Capture/               Selected-text capture strategies (AX, clipboard, manual)
│   ├── Prompt/                PromptBuilder + variable expansion
│   ├── Prompts/               PromptPreset + PromptPresetStore (user-defined)
│   ├── LLM/                   LLMProvider protocol + OpenAI-compatible client
│   ├── Models/                ModelConfig + ModelStore
│   ├── Storage/               KeychainStore, SettingsStore, optional history
│   ├── Panel/                 Floating NSPanel + SwiftUI panel content
│   ├── Settings/              SwiftUI Settings scene (5 tabs incl. Prompts)
│   ├── Onboarding/            First-launch onboarding window
│   └── Util/                  Logger, debouncer, launch-at-login
└── SquintTests/               XCTest unit tests
```

## High-level architecture

```
Hotkey | Services
      ↓
  SelectionCaptureService  →  ContextBundle
      ↓                            ↓
  FloatingPanelController  →  PanelViewModel
                                   ↓
                           PromptBuilder
                                   ↓
                           ProviderRegistry
                                   ↓
                       OpenAICompatibleClient
                                   ↓
                  AsyncThrowingStream<LLMToken>
                                   ↓
                           PanelView (SwiftUI)
```

Full diagrams and module-by-module narrative in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Tech stack

- **Language:** Swift 5.9+, targeting macOS 14+.
- **UI:** SwiftUI for panel content and settings; AppKit for `NSStatusItem`, `NSPanel`, Services, activation policy.
- **Hotkey:** [`sindresorhus/KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) (SPM).
- **Markdown rendering:** [`gonzalezreal/swift-markdown-ui`](https://github.com/gonzalezreal/swift-markdown-ui) (SPM).
- **Networking:** `URLSession` with `bytes(for:).lines` for SSE streaming. No third-party HTTP lib.
- **Storage:** `UserDefaults` for prefs, JSON file in Application Support for `[ModelConfig]`, macOS Keychain (`SecItem*` APIs) for API keys.
- **Project generation:** XcodeGen — the `.xcodeproj` is regenerable from `project.yml`, so it's gitignored.

## Privacy

- No telemetry. No analytics. No crash reporting.
- No backend owned by this app — API calls go directly from the user's machine to their configured provider.
- API keys live in the macOS login Keychain.
- No background scraping. The app never reads selected text or pasteboard contents until the user explicitly invokes it (hotkey or right-click Services).
- On invocation in apps where Accessibility doesn't expose the selection, the app simulates Cmd+C to capture the highlighted text, then restores the previous pasteboard. This is on by default and can be disabled in **Settings → Capture**.
- Local history is **off by default**; when enabled, stored as a JSON file on disk only.

## License

Internal project — license TBD before any public release.
