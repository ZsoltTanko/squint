import SwiftUI
import AppKit

/// The floating panel UI. Designed for power users who fire on selected text,
/// glance at the response, and hit Esc. Everything that isn't the response
/// either hides or shrinks.
///
/// Layout, top to bottom:
///   - Slim header (preset chip · model chip · status dot · gear · ✕)
///   - Single-line collapsed selection preview (click to expand)
///   - Response area (the star — fills available space, renders the full
///     conversation transcript: Markdown answers, with follow-up questions
///     as visually distinct rows between them)
///   - Inline error pill (only when there's an error)
///   - Optional follow-up bar (hidden by default, ⌘L or click to reveal)
struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var queryHistory = QueryHistoryStore.shared
    var onClose: () -> Void

    @State private var selectionExpanded: Bool = false
    @FocusState private var followUpFocused: Bool
    /// Focus for the empty-state "Type or paste text…" field (manual
    /// selection entry).
    @FocusState private var manualSelectionFocused: Bool
    /// Focus for the preset's user-input field (the one shown when the
    /// active preset has `requiresUserInput == true`). Distinct from
    /// `manualSelectionFocused` since both can coexist on screen.
    @FocusState private var presetInputFocused: Bool
    @State private var copyHover: Bool = false

    private var fontSize: CGFloat { CGFloat(settings.panelFontSize) }

    private var resolvedAppearance: PanelResolvedAppearance {
        PanelAppearanceResolver.resolve(
            mode: settings.panelAppearanceMode,
            customBackgroundHex: settings.panelCustomBackgroundHex,
            customTextHex: settings.panelCustomTextHex
        )
    }

    var body: some View {
        let appearance = resolvedAppearance
        return VStack(spacing: 0) {
            header
            selectionPreview
            responseArea
            errorBar
            followUpBar
        }
        .background(backgroundShape(for: appearance))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .modifier(ForegroundColorModifier(tintColor: appearance.foregroundColor))
        .modifier(ColorSchemeOverrideModifier(scheme: appearance.forcedColorScheme))
        // Auto-focus the preset user-input field on each invocation when
        // the active preset requires it, so Opt+Space + start typing
        // works without clicking.
        .onAppear { focusPresetInputIfNeeded() }
        .onChange(of: viewModel.invocationToken) { _, _ in
            focusPresetInputIfNeeded()
        }
        // Fallback for when a SwiftUI `TextField` is first responder.
        // The primary Esc handler lives on `FloatingPanel.cancelOperation`
        // so it works even when no SwiftUI view is focused.
        .onExitCommand {
            if viewModel.isFollowUpOpen {
                viewModel.closeFollowUp()
            } else {
                onClose()
            }
        }
        // Keyboard affordance to reveal the follow-up bar without clicking.
        .background(
            Button("") { showFollowUp() }
                .keyboardShortcut("l", modifiers: [.command])
                .opacity(0)
                .accessibilityHidden(true)
        )
        // Font size shortcuts: ⌘= and ⌘+ both bump up (the latter is what
        // a US-layout user actually presses); ⌘- bumps down. Clamped to
        // `SettingsStore.panelFontSizeRange` so we never drift out of
        // bounds. Hidden buttons rather than a `.commands` scene because
        // this is a panel, not a document window.
        .background(fontSizeShortcuts)
    }

    /// Hidden buttons that own the ⌘+/⌘= / ⌘- keyboard shortcuts for the
    /// response font size. Lives in `.background(...)` so the buttons take
    /// no layout space but still participate in the responder chain.
    private var fontSizeShortcuts: some View {
        ZStack {
            Button("") { adjustFontSize(by: +1) }
                .keyboardShortcut("=", modifiers: [.command])
            Button("") { adjustFontSize(by: +1) }
                .keyboardShortcut("+", modifiers: [.command])
            Button("") { adjustFontSize(by: -1) }
                .keyboardShortcut("-", modifiers: [.command])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func adjustFontSize(by delta: Double) {
        let range = SettingsStore.panelFontSizeRange
        let next = (settings.panelFontSize + delta).rounded()
        settings.panelFontSize = min(max(next, range.lowerBound), range.upperBound)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            chipPreset
            chipModel
            Spacer(minLength: 4)
            // For direct-prompt presets the dedicated selection-preview row
            // is suppressed (there is no selection), so surface the per-preset
            // history dropdown in the header instead — otherwise it would
            // have nowhere to live.
            if let preset = viewModel.selectedPreset, !preset.capturesSelection {
                queryHistoryMenu
            }
            statusDot
            iconButton(system: "gearshape", help: "Settings (⌘,)") {
                AppDelegate.openSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
            iconButton(system: "xmark", help: "Close (Esc)", onClick: onClose)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
    }

    private var chipPreset: some View {
        PresetPicker(
            presetStore: viewModel.presetStore,
            selectedID: $viewModel.selectedPresetID,
            onChange: { viewModel.onPresetChanged() }
        )
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .controlSize(.small)
    }

    private var chipModel: some View {
        ModelPicker(modelStore: viewModel.modelStore, selectedID: $viewModel.selectedModelID)
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
    }

    @ViewBuilder
    private var statusDot: some View {
        if !AccessibilityCapture.isTrusted {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
                .help("Accessibility access not granted — the global hotkey can't read selected text. Open Settings → Permissions.")
                .padding(.trailing, 2)
        } else {
            EmptyView()
        }
    }

    private func iconButton(system: String, help: String, onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Selection preview

    @ViewBuilder
    private var selectionPreview: some View {
        if let preset = viewModel.selectedPreset, !preset.capturesSelection {
            // Direct-prompt presets have no selection concept at all. Don't
            // render anything here — the user-input field that doubles as
            // the LLM's user message lives in `responseArea`, and the
            // history dropdown lives in the header for this mode.
            EmptyView()
        } else if !viewModel.bundle.selectedText.isEmpty {
            // Toggle-to-expand preview + trailing history menu as siblings
            // so the menu doesn't sit inside another Button (SwiftUI bans
            // nested buttons). The menu lives in the same row's background
            // strip and steals only its own ~18pt of width.
            HStack(spacing: 4) {
                Button {
                    selectionExpanded.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: selectionExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                        Text(viewModel.bundle.selectedText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(selectionExpanded ? nil : 1)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                queryHistoryMenu
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04))
        } else if !AccessibilityCapture.isTrusted || viewModel.manualSelectedText.isEmpty {
            // No selection captured and either AX denied or the user hasn't
            // typed anything yet — give them a tiny inline editor.
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(emptyStateMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    TextField("Type or paste text…", text: $viewModel.manualSelectedText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .lineLimit(1...4)
                        .focused($manualSelectionFocused)
                }
                queryHistoryMenu
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    /// Compact dropdown listing recent queries for the active preset. Hidden
    /// when history is disabled (`queryHistoryLimit == 0`) or the preset
    /// has no recorded entries yet, so it doesn't take visual space when
    /// it would have nothing to offer.
    private var queryHistoryEntriesForActivePreset: [QueryHistoryEntry] {
        queryHistory.recent(
            presetID: viewModel.selectedPresetID,
            limit: settings.queryHistoryLimit
        )
    }

    @ViewBuilder
    private var queryHistoryMenu: some View {
        let entries = queryHistoryEntriesForActivePreset
        if !entries.isEmpty {
            Menu {
                ForEach(entries) { entry in
                    Button(historyMenuLabel(entry)) {
                        viewModel.applyHistoryEntry(entry)
                    }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Recent queries for this preset")
        }
    }

    /// Truncate long entries so the menu stays a glance-readable strip
    /// rather than wrapping. Whitespace collapsed for the same reason.
    /// Prefixed with the user-input field when the preset captured one,
    /// so two history items sharing a selection but with different
    /// follow-on questions are distinguishable at a glance.
    private func historyMenuLabel(_ entry: QueryHistoryEntry) -> String {
        let base = entry.userInput.isEmpty
            ? entry.text
            : "\(entry.userInput) — \(entry.text)"
        let single = base.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        if single.count <= 60 { return single }
        return String(single.prefix(60)) + "…"
    }

    // MARK: - Response

    private var responseArea: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if let preset = viewModel.selectedPreset, preset.requiresUserInput {
                            // `.plain` (not `.roundedBorder`) because the
                            // rounded-border style silently ignores
                            // `axis: .vertical` and refuses to wrap, leaving
                            // long input scrolling off the right edge. We
                            // draw an equivalent border ourselves below.
                            TextField(
                                preset.userInputPlaceholder ?? "Instruction…",
                                text: $viewModel.userInput,
                                axis: .vertical
                            )
                            .textFieldStyle(.plain)
                            // Generous upper bound — direct-prompt mode is
                            // often used with multi-paragraph prompts and the
                            // outer ScrollView can scroll past the field if
                            // it ever does run out of vertical space.
                            .lineLimit(1...30)
                            .font(.system(size: fontSize))
                            .focused($presetInputFocused)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Without this, a vertical-axis TextField sitting
                            // inside a ScrollView reports a single-line height
                            // for its intrinsic size and then scrolls its own
                            // content internally as the user types. The cursor
                            // stays visible but earlier lines clip off the top
                            // of the visible field. `fixedSize(vertical:)`
                            // forces the field to claim its full natural
                            // height so the parent ScrollView (not the field)
                            // owns any overflow scrolling.
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.primary.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                            )
                            // Enter sends, Shift+Enter inserts a newline (the
                            // default behaviour for a vertical-axis TextField).
                            .onKeyPress(.return) {
                                if NSEvent.modifierFlags.contains(.shift) {
                                    return .ignored
                                }
                                if viewModel.canSend, !viewModel.isStreaming {
                                    viewModel.send()
                                    return .handled
                                }
                                return .ignored
                            }
                        }

                        transcript
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                // When a follow-up question is appended, bring it to the top
                // of the viewport so the answer streams in below it — the
                // user reads the new exchange from its start instead of
                // staring at the (unchanged) previous response.
                .onChange(of: viewModel.latestUserTurnID) { _, newID in
                    guard let newID else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(newID, anchor: .top)
                        }
                    }
                }
            }

            // Floating action overlay — copy on hover, bottom-right.
            // Streaming is implicitly stopped by closing the panel
            // (Esc / ✕); no in-canvas stop button.
            HStack(spacing: 4) {
                if !viewModel.streamingText.isEmpty {
                    Button {
                        copyResponse()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(copyHover ? .primary : .secondary)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(copyHover ? Color.primary.opacity(0.08) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Copy response (⌘C)")
                    .onHover { copyHover = $0 }
                }
            }
            .padding(.bottom, 6)
            .padding(.trailing, 8)
        }
        // Hidden ⌘↵ shortcut so Cmd+Return always sends, even with no visible button.
        .background(
            Button("") { viewModel.send() }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!viewModel.canSend || viewModel.isStreaming)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }

    /// The conversation transcript: every completed exchange plus the
    /// in-flight response. Assistant turns render as Markdown exactly like
    /// the old single-response layout; follow-up questions render as a
    /// visually distinct row (divider + tinted strip) so the eye can find
    /// turn boundaries when scanning back.
    @ViewBuilder
    private var transcript: some View {
        let turns = viewModel.conversationTurns
        if turns.isEmpty {
            if viewModel.isStreaming {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
            } else {
                emptyResponsePlaceholder
            }
        } else {
            ForEach(turns) { turn in
                turnRow(turn)
            }
            // A follow-up was sent but the first token hasn't arrived yet —
            // the transcript ends with the user's question, so show the
            // spinner below it.
            if viewModel.isStreaming, viewModel.streamingText.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func turnRow(_ turn: PanelViewModel.ConversationTurn) -> some View {
        switch turn.kind {
        case .assistant:
            MarkdownResponseView(
                text: turn.text,
                fontSize: fontSize,
                textOverrideColor: resolvedAppearance.foregroundColor
            )
        case .user:
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: max(fontSize - 4, 9), weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 3)
                    Text(turn.text)
                        .font(.system(size: fontSize - 1, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
    }

    @ViewBuilder
    private var emptyResponsePlaceholder: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.send()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .medium))
                    Text("Ask")
                        .font(.system(size: 11, weight: .medium))
                    Text("⌘↵")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSend)
        }
        .padding(.top, 4)
    }

    // MARK: - Error

    @ViewBuilder
    private var errorBar: some View {
        if let err = viewModel.lastError {
            Text(err)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
        }
    }

    // MARK: - Follow-up (hidden by default)

    @ViewBuilder
    private var followUpBar: some View {
        if viewModel.isFollowUpOpen {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextField("Follow up…", text: $viewModel.followUpInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($followUpFocused)
                    .onSubmit {
                        viewModel.sendFollowUp()
                        viewModel.isFollowUpOpen = false
                    }
                if !viewModel.followUpInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("↵")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            .onAppear { followUpFocused = true }
        } else if !viewModel.streamingText.isEmpty || !viewModel.conversation.isEmpty {
            // Tiny affordance — only appears once there's something to follow up on.
            HStack {
                Spacer()
                Button(action: showFollowUp) {
                    HStack(spacing: 3) {
                        Text("Follow up")
                        Text("⌘L").foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Ask a follow-up (⌘L)")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Actions

    private func showFollowUp() {
        viewModel.isFollowUpOpen = true
        DispatchQueue.main.async { followUpFocused = true }
    }

    private var emptyStateMessage: String {
        if !AccessibilityCapture.isTrusted {
            return "No selection — Accessibility access not granted."
        }
        return "No selection captured."
    }

    private func focusPresetInputIfNeeded() {
        guard let preset = viewModel.selectedPreset, preset.requiresUserInput else { return }
        // Defer one runloop tick so the TextField is mounted and ready to
        // accept focus when the panel is first shown for a new invocation.
        DispatchQueue.main.async { presetInputFocused = true }
    }

    private func copyResponse() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(viewModel.streamingText, forType: .string)
    }

    // MARK: - Appearance helpers

    @ViewBuilder
    private func backgroundShape(for appearance: PanelResolvedAppearance) -> some View {
        switch appearance.backgroundFill {
        case .translucentMaterial:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        case .solid(let fillColor):
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fillColor)
        }
    }
}

/// Applies `foregroundStyle(color)` only when a tint is provided, leaving
/// the system defaults intact otherwise.
private struct ForegroundColorModifier: ViewModifier {
    let tintColor: Color?
    func body(content: Content) -> some View {
        if let tintColor {
            content.foregroundStyle(tintColor)
        } else {
            content
        }
    }
}

/// Forces a specific `ColorScheme` on the subtree when one is provided,
/// so system-drawn controls contrast correctly against the chosen
/// background. `nil` means follow the system setting.
private struct ColorSchemeOverrideModifier: ViewModifier {
    let scheme: ColorScheme?
    func body(content: Content) -> some View {
        if let scheme {
            content.environment(\.colorScheme, scheme)
        } else {
            content
        }
    }
}
