import SwiftUI
import MarkdownUI

struct MarkdownResponseView: View {
    let text: String
    let fontSize: CGFloat
    /// Optional override for body text color. `nil` means "use whatever the
    /// environment's `.primary` resolves to" — which follows the forced or
    /// system `ColorScheme`.
    let textOverrideColor: Color?

    init(
        text: String,
        fontSize: CGFloat = CGFloat(SettingsStore.defaultPanelFontSize),
        textOverrideColor: Color? = nil
    ) {
        self.text = text
        self.fontSize = fontSize
        self.textOverrideColor = textOverrideColor
    }

    var body: some View {
        if text.isEmpty {
            EmptyView()
        } else {
            Markdown(text)
                .markdownTheme(.inlineLens(fontSize: fontSize, textOverrideColor: textOverrideColor))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension Theme {
    /// Tight, glanceable theme tuned for the floating panel.
    /// Headings are only mildly larger than body so the response reads as a
    /// single paragraph stream; lists and code blocks get compact spacing.
    static func inlineLens(fontSize: CGFloat, textOverrideColor: Color? = nil) -> Theme {
        Theme()
            .text {
                FontSize(fontSize)
                if let textOverrideColor {
                    ForegroundColor(textOverrideColor)
                }
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(fontSize - 1)
            }
            .strong { FontWeight(.semibold) }
            .link { ForegroundColor(.accentColor) }
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(fontSize + 4)
                        FontWeight(.semibold)
                    }
                    .markdownMargin(top: 8, bottom: 4)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(fontSize + 3)
                        FontWeight(.semibold)
                    }
                    .markdownMargin(top: 6, bottom: 4)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(fontSize + 2)
                        FontWeight(.semibold)
                    }
                    .markdownMargin(top: 6, bottom: 3)
            }
            .heading4 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(fontSize + 1)
                        FontWeight(.semibold)
                    }
                    .markdownMargin(top: 4, bottom: 2)
            }
            .paragraph { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.18))
                    .markdownMargin(top: 0, bottom: 6)
            }
            .listItem { configuration in
                configuration.label.markdownMargin(top: 0, bottom: 2)
            }
            .codeBlock { configuration in
                ScrollView(.horizontal) {
                    configuration.label
                        .padding(8)
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(fontSize - 1)
                        }
                }
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .markdownMargin(top: 4, bottom: 6)
            }
    }
}
