import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            VStack(spacing: 15) {
                ForEach(ToolSection.allCases) { section in
                    let tools = app.tools(in: section)
                    if !tools.isEmpty {
                        VStack(spacing: 7) {
                            SectionLabel(text: section.rawValue)
                            Card {
                                ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                                    if index > 0 { Hairline() }
                                    ToolRowView(tool: tool)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            FooterBar()
        }
    }

    private var header: some View {
        HStack {
            Text("Fettle")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if app.activeCount > 0 {
                StatusPill(text: "\(app.activeCount) Active", color: Theme.green)
            } else {
                StatusPill(text: "Idle", color: Theme.textTertiary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

struct ToolRowView: View {
    let tool: any FettleTool
    @Environment(AppState.self) private var app

    private var activeBinding: Binding<Bool> {
        Binding(get: { tool.isActive }, set: { tool.setActive($0) })
    }

    var body: some View {
        HStack(spacing: 11) {
            IconTile(symbol: tool.symbol, tint: tool.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(tool.statusText).font(.system(size: 11.5)).foregroundStyle(tool.statusTint)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { if tool.hasDetail { app.route = .tool(tool.kind) } }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 9) {
            switch tool.control {
            case .toggle:
                FSwitch(isOn: activeBinding, tint: tool.tint)
            case .navigate:
                chevron
            case .toggleAndNavigate:
                chevron
                FSwitch(isOn: activeBinding, tint: tool.tint)
            case .value(let text):
                Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xC7C7CE))
                chevron
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(hex: 0x5A5A62))
    }
}
