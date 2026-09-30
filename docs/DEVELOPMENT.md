# Development

This document covers everything you need to set up a workstation, build the app, run tests, and debug. For *what* the app is, read [`../README.md`](../README.md). For *how it's structured*, read [`ARCHITECTURE.md`](ARCHITECTURE.md). For known macOS oddities, read [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

## Prerequisites

- **macOS 14 (Sonoma) or newer** — the deployment target. Development was done on macOS 26.
- **Xcode 15 or newer** — installed from the Mac App Store, *not* just the Command Line Tools. `xcodebuild` against an `.app` target requires the full Xcode app.
- **XcodeGen** — `brew install xcodegen`. Used to regenerate `Squint.xcodeproj` from `project.yml`. The `.xcodeproj` is gitignored.
- **An LLM provider account** — any OpenAI Chat Completions-compatible endpoint will work. Get an OpenAI API key from <https://platform.openai.com/api-keys>, or run a local model via [Ollama](https://ollama.com/) and skip the cloud entirely.

First-time Xcode setup gotchas:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer   # if CLT is selected
sudo xcodebuild -license accept                                    # accept Xcode license
sudo xcodebuild -runFirstLaunch                                    # install required system content
```

If you skip these you'll get cryptic errors about missing `CoreSimulator` frameworks or unaccepted licenses.

## Generate the Xcode project

```bash
xcodegen generate
open Squint.xcodeproj
```

`project.yml` is the source of truth — it declares the app target, deployment target, `Info.plist` template (including `LSUIElement` and the `NSServices` entry), entitlements, SPM dependencies, and the test target. Edit it, regenerate, commit `project.yml` (never the `.xcodeproj`).

## Build and run from the IDE

1. Open `Squint.xcodeproj` in Xcode.
2. Select the `Squint` scheme.
3. Cmd+R. The app will build, sign with an ad-hoc identity, and launch.
4. The app is `LSUIElement` so it appears only in the menu bar — no Dock icon.

To stop it, click the menu-bar icon → **Quit**, or use Xcode's stop button.

## Build and run from the command line

```bash
# Resolve SPM packages once (or after editing project.yml)
xcodebuild -project Squint.xcodeproj \
           -scheme Squint \
           -destination 'platform=macOS' \
           -resolvePackageDependencies

# Build
xcodebuild -project Squint.xcodeproj \
           -scheme Squint \
           -configuration Debug \
           -destination 'platform=macOS' \
           -derivedDataPath build \
           CODE_SIGNING_ALLOWED=NO \
           build

# Run the built app
open build/Build/Products/Debug/Squint.app
```

The `CODE_SIGNING_ALLOWED=NO` flag lets you build without a development team for local development.

## Iteration loop (terminal-driven)

When iterating quickly on `Capture/`, `Panel/`, `LLM/`, or anything else where you'd rather not click through Xcode's run/stop cycle, use the bundled script:

```bash
./bin/dev-restart.sh
```

It does, in order:

1. Regenerates `Squint.xcodeproj` if `project.yml` is newer (skipped otherwise).
2. `killall Squint` — terminates any running copy.
3. `xcodebuild … build` against the macOS Debug configuration with code signing disabled.
4. `lsregister -f` + `pbs -update` against the freshly built `.app` so Launch Services and the right-click Services menu point at the new bundle.
5. `open` the rebuilt `.app`, then verifies the process is alive.

If the build fails, the script prints the first 40 lines of compile errors/warnings and exits non-zero. The whole cycle takes a few seconds for incremental rebuilds.

A few things to keep in mind:

- The `lsregister -f` + `pbs -update` step is only needed if you changed `Info.plist`, `project.yml`'s `NSServices` section, or you suspect Launch Services is pointing at a stale bundle. For pure Swift edits you can skip it. (See [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#services-menu-entry-doesnt-appear) for why this matters.)
- Even after `lsregister -f`, the **consuming app** (TextEdit, Notes, …) still won't see a changed Service entry until *it* is quit and relaunched.
- Accessibility permission survives rebuilds because it's keyed on the bundle identifier, not the binary path. You don't need to re-grant after each rebuild — only after wiping the app from the Accessibility list.
- If you change `project.yml`, run `xcodegen generate` first.

## Run tests

```bash
xcodebuild -project Squint.xcodeproj \
           -scheme Squint \
           -configuration Debug \
           -destination 'platform=macOS' \
           -derivedDataPath build \
           CODE_SIGNING_ALLOWED=NO \
           test
```

Or in Xcode: Cmd+U.

The test bundle (`SquintTests/`) covers the pure-Swift parts:

- `PromptBuilderTests` — prompt assembly across modes, follow-up appending, app-context inclusion.
- `OpenAICompatibleClientTests` — `complete` / `streamResponse` against a `URLProtocol` stub, including SSE parsing, missing-API-key handling, and HTTP error surfacing.
- `ModelStoreTests` — CRUD, default-model promotion, JSON round-trip across instances.
- `KeychainStoreTests` — write / read / delete / overwrite against a test-scoped Keychain service.
- `SelectionCaptureServiceTests` — manual-input fallthrough.

UI, Services, hotkey, and Accessibility paths are deliberately not unit-tested — they're tested manually because their behavior depends on actual OS state (TCC permissions, frontmost app, pasteboard, Services menu cache).

## Debug workflow

### Logging

Everything notable goes through `AppLogger` (`Util/Logger.swift`), which writes to `os.Logger(subsystem: "com.zsolttanko.squint", category: "app")`.

Live tail in a terminal while you reproduce an issue:

```bash
log stream --predicate 'subsystem == "com.zsolttanko.squint"' --level info
```

Window of past logs:

```bash
log show --predicate 'subsystem == "com.zsolttanko.squint"' --info --last 5m
```

The streaming client emits three timing breadcrumbs per LLM request, useful for diagnosing TTFT issues:

```
LLM stream request started: <model>
LLM headers received in N.NNs
LLM first delta in N.NNs
```

If `headers received` is fast but `first delta` is many seconds later, you're hitting reasoning-model latency, not a client bug. See [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#streaming-feels-slow-to-start).

### In-panel status indicator

The floating panel's title bar contains a small **orange dot** (next to the gear icon) when Accessibility access is not granted. Hovering it shows a tooltip with the full explanation. When AX is trusted and everything is working normally the dot is not shown.

Capture method, frontmost app, and preset/model details are no longer shown in the panel UI. For "why doesn't this work in app X?" triage, use the `os.Logger` stream (see above) — the `SelectionCaptureService` logs the chosen strategy and the resulting text length on every invocation.

**Panel keyboard shortcuts (useful during development):**

| Key | Action |
| --- | --- |
| `Esc` | Close panel (collapses follow-up first if open). Handled at the `NSPanel` level via `cancelOperation(_:)`, so it fires immediately after the panel is shown — no "click a text field to activate Esc" step. Closing also cancels any in-flight LLM stream. |
| `⌘↵` | Send / Ask |
| `↵` | Send when the preset's user-input field is focused. `Shift+↵` inserts a newline. |
| `⌘C` | Copy *selected* text if a selection is active inside the Markdown view; otherwise falls back to copying the full response. Panel overrides `performKeyEquivalent(with:)` and dispatches `copy:` down the responder chain first. |
| `⌘+` / `⌘=` / `⌘-` | Bump `SettingsStore.panelFontSize` ± 1 pt, clamped to `panelFontSizeRange` (11–18 pt). Hidden zero-opacity buttons in `PanelView.fontSizeShortcuts`. Both `=` (US natural) and `+` (with shift) are bound. |
| `⌘L` | Toggle follow-up bar |
| `⌘,` | Open Settings (panel stays open behind it) |

**No in-canvas Stop button.** Streaming is implicitly cancelled when the panel closes (Esc / ✕). Click-off in the *Stay on top* and *Recede to background* modes deliberately does **not** cancel the stream — the stream survives focus changes and is consumable when you bring the panel back via Cmd+Tab.

Settings window also supports `Esc` to close (private `SettingsWindow` subclass overrides `cancelOperation(_:)` → `performClose(nil)`).

### Inspect persisted state

```bash
# Configured models
cat ~/Library/Application\ Support/Squint/models.json | jq

# Per-preset query history (powers the panel's recent-queries dropdown)
cat ~/Library/Application\ Support/Squint/query-history.json | jq

# Full opt-in history (only present when the toggle in Settings → General is on)
cat ~/Library/Application\ Support/Squint/history.json | jq

# UserDefaults
defaults read com.zsolttanko.squint
```

To inspect or remove API keys: open **Keychain Access.app** → the **login** keychain → search for `com.zsolttanko.squint`. One generic-password entry per model, with the model's UUID as account.

### Reset the app to first-launch state

```bash
killall Squint 2>/dev/null
defaults delete com.zsolttanko.squint
rm -rf ~/Library/Application\ Support/Squint
# Optionally remove keychain entries via Keychain Access (manual)
```

Then relaunch. You'll see the onboarding window.

### Reset Accessibility permission

If a stale `Squint` row is stuck in **System Settings → Privacy & Security → Accessibility**:

1. Open the pane.
2. Select the row, click `–`, confirm.
3. Quit the app.
4. Relaunch the app, press the global hotkey once.
5. The system prompt will reappear; click **Open System Settings**, toggle the new row on.
6. **Quit and relaunch the app again** — AX trust is cached at process start and the running process never sees the new permission until it restarts.

This is a system-level constraint, not a bug in the app. See [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#hotkey-doesnt-capture-selected-text).

### Refresh the macOS Services menu

Services entries are cached. After rebuilding the app, the Services menu in *consuming* apps (TextEdit, Notes, Safari, …) won't show the new entry until you re-register and the consuming app is relaunched:

```bash
APP="$(pwd)/build/Build/Products/Debug/Squint.app"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP"
/System/Library/CoreServices/pbs -update
# Then quit and relaunch the consuming app (e.g. TextEdit)
```

If the Service still doesn't appear, open **System Settings → Keyboard → Keyboard Shortcuts → Services → Text** and ensure **Ask Squint** is ticked. macOS hides Services the user hasn't enabled.

## Code style

- **Swift API Design Guidelines apply.** Names should read at the call site.
- **Comments only when the code can't carry the meaning.** Don't narrate what the code does. Do explain non-obvious *why*: trade-offs, OS quirks, intentional defaults.
- **Module boundaries matter.** Don't add cross-module imports that violate the dependency direction in `ARCHITECTURE.md`. If you find yourself wanting to, the modules are wrong — refactor instead.
- **MainActor discipline.** Anything that touches UI, `@Published` properties, or AppKit must be on `@MainActor`. Network/IO should not be.
- **No hidden side effects.** Capture, prompt building, and provider calls all take their dependencies as parameters or via the `AppDelegate.shared` graph. No singletons reaching into `UserDefaults.standard` from random files.

## Branching, commits, PRs

(Establish per-team conventions; suggested defaults below.)

- Branch from `main`.
- Conventional Commit-ish prefixes are fine: `feat: …`, `fix: …`, `refactor: …`, `docs: …`, `test: …`.
- One concern per PR. If you touch the spec and the code, separate PRs with a clear ordering: spec change merges first, code follows.
- Re-run `xcodegen generate` if you edited `project.yml`. Commit `project.yml`, never the generated `.xcodeproj`.

## Continuous integration

Not yet configured. Suggested first step: a GitHub Actions workflow on macOS runners that runs `xcodegen generate` then `xcodebuild test` on every PR. Easy to add later — we just haven't.

## Releasing (future)

Not yet in scope. When it's time:

- Get a paid Apple Developer ID.
- Replace ad-hoc signing with Developer ID signing in `project.yml`.
- Notarize via `notarytool` after build.
- Decide on a distribution channel (direct download, Homebrew cask, MAS — each has very different sandbox/entitlement implications; MAS would require turning the sandbox back on, which is currently disabled in entitlements).
