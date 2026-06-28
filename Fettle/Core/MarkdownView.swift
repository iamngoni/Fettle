import SwiftUI

/// Lightweight Markdown renderer for summaries — handles headings, bullet and
/// numbered lists, and inline styling (bold/italic/code/links). Good enough to
/// render Gemma / Apple Intelligence output cleanly without a heavy dependency.
struct MarkdownView: View {
    let markdown: String
    var accent: Color = Color(hex: 0xBF5AF2)

    private var lines: [Substring] { markdown.split(separator: "\n", omittingEmptySubsequences: false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, raw in
                row(String(raw))
            }
        }
    }

    @ViewBuilder
    private func row(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("```") {
            EmptyView()   // strip code-fence markers (```markdown … ```)
        } else if line.isEmpty {
            Color.clear.frame(height: 3)
        } else if line.hasPrefix("### ") {
            Text(inline(String(line.dropFirst(4))))
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                .padding(.top, 2)
        } else if line.hasPrefix("## ") {
            Text(inline(String(line.dropFirst(3))))
                .font(.system(size: 13.5, weight: .bold)).foregroundStyle(Theme.textPrimary)
                .padding(.top, 3)
        } else if line.hasPrefix("# ") {
            Text(inline(String(line.dropFirst(2))))
                .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
                .padding(.top, 3)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            bullet("•", inline(String(line.dropFirst(2))))
        } else if let range = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            bullet(String(line[..<range.upperBound]).trimmingCharacters(in: .whitespaces),
                   inline(String(line[range.upperBound...])))
        } else {
            Text(inline(line)).font(.system(size: 13)).foregroundStyle(Color(hex: 0xD7D7DC))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ marker: String, _ content: AttributedString) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(marker).font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
            Text(content).font(.system(size: 13)).foregroundStyle(Color(hex: 0xD7D7DC))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
