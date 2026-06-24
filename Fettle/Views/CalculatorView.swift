import SwiftUI

struct CalculatorView: View {
    @Bindable var tool: CalculatorTool
    @Environment(AppState.self) private var app

    private let resultColor = Color(hex: 0x7DE08F)

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Calculator", pill: nil) { app.route = .dashboard }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(tool.lines.indices, id: \.self) { i in
                        row(i)
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

    private func row(_ i: Int) -> some View {
        let isComment = tool.lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("//")
            || tool.lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("#")
        return HStack(spacing: 10) {
            TextField(i == 0 && tool.lines.count == 1 ? "Try  20 EUR in USD" : "", text: $tool.lines[i], axis: .horizontal)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(isComment ? Color(hex: 0x5A5A62) : Color(hex: 0xD7D7DC))
            if let result = tool.result(for: tool.lines[i]) {
                Text(result)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(resultColor)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 5)
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
