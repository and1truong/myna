import SwiftUI

/// Renders inline markdown (bold, italic, code, quotes) while preserving
/// whitespace and newlines. Falls back to plain text on parse failure.
struct MarkdownText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(content)
        }
    }
}
