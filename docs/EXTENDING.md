# Extending the app

Recipes for the most common changes. Each recipe lists the files you'll touch and the order to do it in. Read [`ARCHITECTURE.md`](ARCHITECTURE.md) first.

## Add a new LLM provider

Currently only `OpenAICompatibleClient` ships, but the protocol seam is in place. Adding a native Anthropic / Gemini / Bedrock client is a localized change.

1. **Add an enum case** in `Squint/Models/ProviderKind.swift`:

   ```swift
   enum ProviderKind: String, Codable, CaseIterable, Identifiable {
       case openAICompatible
       case anthropic   // new

       var displayName: String {
           switch self {
           case .openAICompatible: return "OpenAI-compatible"
           case .anthropic:        return "Anthropic"
           }
       }
   }
   ```

2. **Implement `LLMProvider`** in a new file under `Squint/LLM/`:

   ```swift
   final class AnthropicClient: LLMProvider {
       func complete(request: LLMRequest) async throws -> LLMResponse { ... }
       func streamResponse(request: LLMRequest) async throws -> AsyncThrowingStream<LLMToken, Error> { ... }
   }
   ```

   Translate the provider-neutral `LLMRequest` (which contains `[ChatMessage]` with `system`/`user`/`assistant` roles) into the vendor's wire format. For Anthropic, hoist any `system` messages into the top-level `system` field and convert the rest to `messages: [{role, content}]`.

   Reuse the streaming-tuned URLSession pattern from `OpenAICompatibleClient.makeStreamingSession()` — disable the URL cache, use `.reloadIgnoringLocalCacheData`, set generous `timeoutIntervalForResource`. SSE buffering with `URLSession.shared` is real and bites every provider.

3. **Wire it into the registry** in `Squint/LLM/ProviderRegistry.swift`:

   ```swift
   func provider(for model: ModelConfig) -> LLMProvider {
       switch model.provider {
       case .openAICompatible:
           return OpenAICompatibleClient { [keychain] cfg in
               keychain.readAPIKey(account: cfg.apiKeyReference)
           }
       case .anthropic:
           return AnthropicClient { [keychain] cfg in
               keychain.readAPIKey(account: cfg.apiKeyReference)
           }
       }
   }
   ```

4. **Tests.** Copy `OpenAICompatibleClientTests.swift` and adapt to the vendor's response shapes. The `StubURLProtocol` pattern works for any URLSession-based client.

5. **No UI change required** — `ModelsSettingsView` already iterates `ProviderKind.allCases` for the picker. New providers appear automatically.

## Add a built-in default behavior — or just author a preset

Prompt behavior is owned by user-defined `PromptPreset`s now; there's no enum to extend. To ship a new "out of the box" persona, add it to `PromptPreset.factorySeeds` in `Squint/Prompts/PromptPreset.swift`:

- On a *fresh install* (`prompts.json` missing or empty), the entire `factorySeeds` array is installed and the first entry becomes the default preset.
- On an *upgrade*, `PromptPresetStore.installNewFactorySeedsIfNeeded()` appends only the seeds whose names haven't been offered to this catalog before *and* aren't currently present. The migration ledger lives in `UserDefaults` under `Squint.installedFactorySeedNames`. Once a seed name is recorded as offered, it's never reinstalled — so a seed the user later deletes stays gone.

Two shared copies are kept as `fileprivate static let` constants so seed copy edits stay consistent: `seedBaseSystemPrompt` (the "lens over selected text" framing used by `Explain` and `Ask`) and `seedDirectPromptSystemPrompt` (the "type a question, get an answer" framing used by `Prompt`). Reuse them unless the new preset really needs different framing. Otherwise just create the preset in **Settings → Prompts**.

A preset's *input modality* is implicit in two flags:

- `capturesSelection: Bool` — whether the capture pipeline runs at all. `false` makes the preset a pure direct-prompt wrapper (no selection captured, `PanelView` hides the selection preview, `PromptBuilder` uses the user-input field as the user message). The `Prompt` factory seed is the canonical example.
- `requiresUserInput: Bool` — whether `PanelViewModel.canSend` gates on the user-input field having content. Always pair with `capturesSelection: false` for a direct-prompt preset, otherwise auto-send would fire against an empty input.

These two flags cover the three first-class modalities (selection-only, selection + input, input-only); see the table in [`ARCHITECTURE.md`](ARCHITECTURE.md#prompt-assembly).

If you're adding a new template variable (currently `{{selection}}`, `{{userInput}}`, `{{app}}`, `{{windowTitle}}`, `{{date}}`):

1. Add it to the `substitutions` dictionary in `PromptBuilder.expand`.
2. Add it to the `known` set in `PromptBuilder.unknownVariables` so the editor's preview pane stops flagging it.
3. Pass the value through from `PanelViewModel` / `FloatingPanelController` if it isn't already on `ContextBundle`.
4. Add a test in `PromptResolutionTests`.

## Add a new capture strategy

`SelectionCaptureService` runs strategies in priority order. Adding a new one means adding a file under `Capture/` and slotting it into the orchestrator.

Example: a "browser DOM via AppleScript" strategy for Safari/Chrome.

1. **Add a case** in `Squint/Capture/CaptureMethod.swift` (e.g. `.browserDom`).
2. **Implement the strategy** in `Squint/Capture/BrowserDomCapture.swift` with an `async` static method returning `String?`.
3. **Insert into the priority chain** in `SelectionCaptureService.captureForHotkey()`. Decide where it slots — for browsers it should go *before* `.accessibility` because AX of web content is nearly useless.
4. **Plumb any toggles** through `SettingsStore` (e.g. `enableBrowserDomCapture`) and surface them in `Settings/CaptureSettingsView`.

## Add a new setting

For a typed boolean / string / enum / int setting:

1. **Add a key** to `SettingsStore.Keys` in `Squint/Storage/SettingsStore.swift`.
2. **Register a default** in `SettingsStore.init()`.
3. **Add a typed accessor** on `SettingsStore` (mirror the existing pattern — `objectWillChange.send()` after writing). For `Int` settings where `0` is a valid user choice (e.g. "off"), branch on `defaults.object(forKey:) == nil` to disambiguate "not set yet" from "set to 0" — `defaults.integer(forKey:)` collapses both to `0` otherwise. `queryHistoryLimit` is the example.
4. **Bind a UI control** in the appropriate `Settings/*View.swift` using either `@AppStorage(SettingsStore.Keys.foo)` (for SwiftUI-only views) or a `Binding(get:set:)` against the store. `Stepper(value:in:)` paired with a side-display `Text` is a good pattern for bounded integers.
5. **Use the setting** wherever it changes behavior. Tests for any logic gated by the setting belong in the relevant module's test file.

## Add a new field to `ModelConfig` or `PromptPreset`

Both are `Codable` and persisted to JSON.

1. **Add the field** to the struct (`Squint/Models/ModelConfig.swift` or `Squint/Prompts/PromptPreset.swift`). Update the `init` defaults. Optional fields stay backward-compatible without ceremony — Swift's synthesised decoder `decodeIfPresent`s `Optional` properties. Non-optional fields need a default supplied by a custom decoder (see `PromptPreset.init(from:)`); pick a default that matches pre-existing behavior so the migration is invisible.
2. **PromptPreset only — extend BOTH `CodingKeys` and `encode(to:)`.** `PromptPreset` has a hand-written `init(from:)`, which silently disables Swift's synthesis of `encode(to:)`. The encoder is therefore also hand-written and must list every field. **If you add a field to `init(from:)` but forget `encode(to:)`, the field round-trips inside a single process via property defaults but is dropped on save** — next launch decodes it as the default and the user's choice is silently lost. The `testCapturesSelectionRoundTripsThroughEncodeAndDecode` test asserts the encoded JSON string actually contains the new key; copy that pattern for any new field.
3. **Surface it in the editor** — add a `@State` and a `TextField` / `Toggle` in the relevant editor (`ModelsSettingsView.ModelEditor` or `PromptPresetEditor`). Map it back into `draft` on Save. For numeric fields parsed from a string-backed `TextField`, use the existing `_panelWidthText` / `_panelHeightText` pattern as a template.
4. **Use it downstream** — usually inside `OpenAICompatibleClient.buildRequest` (or your new provider) for `ModelConfig`, or inside `FloatingPanelController` / `PanelViewModel` for `PromptPreset`. Send / apply the field only when non-empty so non-supporting models or older presets aren't broken.
5. **Write a test** if the field changes wire-format output or panel behaviour. The `URLProtocol` stub in `OpenAICompatibleClientTests` can capture the request body and assert against it.

`reasoningEffort` (on `ModelConfig`) and `capturesSelection` / `panelWidth` / `panelHeight` (on `PromptPreset`) are the canonical examples — search the codebase for them to see all the touch points.

## Add a new field to `QueryHistoryEntry`

The history dropdown's "repaint the panel exactly as it was" promise gets richer the more state we record. To add a new field (e.g. `temperature` per-invocation):

1. Add the property as `Optional` to `QueryHistoryEntry` in `Squint/Storage/QueryHistoryStore.swift`. Update the memberwise `init` and `init(from:)` (the custom decoder backfills `nil`/empty for missing fields on older entries — keep that pattern).
2. Add the corresponding parameter to `QueryHistoryStore.record(...)`.
3. Pass the value at the recording site (`PanelViewModel.runRequest` success branch).
4. Restore it in `PanelViewModel.applyHistoryEntry(_:)` — guard against now-invalid values (e.g. a model UUID that's been deleted from the catalog) and fall back to the current selection rather than nilling it out.

## Change the default hotkey

Edit the default in `Squint/Hotkey/ShortcutNames.swift`:

```swift
static let invokePanel = Self("invokePanel", default: .init(.space, modifiers: [.option]))
```

Existing users won't be affected — `KeyboardShortcuts` persists their choice once they change it via Settings → General.

## Add a menu bar item

Edit `Squint/MenuBar/MenuBarController.buildMenu()`. Wire its action to a new closure passed in the initializer, and route the closure to the appropriate `AppDelegate` method.
