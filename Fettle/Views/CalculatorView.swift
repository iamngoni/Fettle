import SwiftUI

struct CalculatorView: View {
    @Bindable var tool: CalculatorTool
    @Environment(AppState.self) private var app
    @State private var hovered: UUID?

    private let resultColor = Color(hex: 0x7DE08F)

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 2) {
                    ForEach($tool.lines) { $line in
                        row($line)
                    }
                }
                .padding(.vertical, 12).padding(.horizontal, 14)
            }
            .background(Color(hex: 0x141417))
            footer
        }
        .onChange(of: tool.lines) { _, _ in tool.ensureTrailingBlank() }
        .onAppear { tool.ensureTrailingBlank() }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { app.route = .dashboard } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC7C7CE))
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.card))
                }.buttonStyle(.plain)
                Text("Calculator").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                if tool.lines.contains(where: { !$0.text.isEmpty }) {
                    Button { tool.clearAll() } label: {
                        Text("Clear").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            Hairline()
        }
    }

    private func row(_ line: Binding<CalcLine>) -> some View {
        let text = line.wrappedValue.text
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let isComment = trimmed.hasPrefix("//") || trimmed.hasPrefix("#")
        let isOnlyEmpty = tool.lines.count == 1 && text.isEmpty
        let canDelete = tool.lines.count > 1
        let showDelete = hovered == line.wrappedValue.id && canDelete

        return HStack(spacing: 8) {
            TextField(isOnlyEmpty ? "Try 20 EUR in USD" : "", text: line.text, axis: .horizontal)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(isComment ? Color(hex: 0x5A5A62) : Color(hex: 0xD7D7DC))

            if showDelete {
                Button { tool.removeLine(line.wrappedValue) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0x6E6E78))
                }.buttonStyle(.plain)
            }
            if let result = tool.result(for: text) {
                Text(result)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(resultColor)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = line.wrappedValue.id }
            else if hovered == line.wrappedValue.id { hovered = nil }
        }
    }

    private var footer: some View {
        HStack {
            Text("Natural language · units · live currency")
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            Spacer()
            Text("\(tool.rates.count) rates")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
