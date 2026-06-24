import SwiftUI

struct ConvertView: View {
    @Bindable var tool: ConvertTool
    @Environment(AppState.self) private var app

    private let accent = Color(hex: 0x0A84FF)

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Convert", pill: nil) { app.route = .dashboard }
            Group {
                VStack(spacing: 10) {
                    categoryPicker
                    formatPicker
                    chooseButton
                    if !tool.jobs.isEmpty { queue }
                    note
                }
                .padding(16)
            }
        }
    }

    private var categoryPicker: some View {
        HStack(spacing: 0) {
            ForEach(ConvertTool.Category.allCases, id: \.self) { cat in
                let active = tool.category == cat
                Button { tool.category = cat } label: {
                    Text(cat.rawValue)
                        .font(.system(size: 12.5, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 7).fill(active ? Color.white.opacity(0.08) : .clear))
                }.buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.card))
    }

    private var formatPicker: some View {
        VStack(spacing: 7) {
            SectionLabel(text: "OUTPUT FORMAT")
            HStack(spacing: 8) {
                ForEach(tool.formatOptions, id: \.self) { fmt in
                    Chip(label: fmt.uppercased(), isSelected: tool.selectedFormat == fmt, tint: accent) {
                        tool.selectFormat(fmt)
                    }
                }
            }
        }
    }

    private var chooseButton: some View {
        Button { tool.pickAndConvert() } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.plus").font(.system(size: 16, weight: .semibold))
                Text("Choose files to convert").font(.system(size: 13.5, weight: .bold))
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 11).fill(accent))
        }.buttonStyle(.plain)
    }

    private var queue: some View {
        VStack(spacing: 7) {
            SectionLabel(text: "QUEUE")
            Card {
                ForEach(Array(tool.jobs.enumerated()), id: \.element.id) { index, job in
                    if index > 0 { Hairline() }
                    HStack(spacing: 10) {
                        statusIcon(job.status)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(job.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Text(job.detail).font(.system(size: 11)).foregroundStyle(Theme.textMuted).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                }
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: JobStatus) -> some View {
        switch status {
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(Color(hex: 0x32D74B))
        case .failed: Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.red)
        }
    }

    private var note: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            Text("Runs locally with native macOS frameworks — no uploads. Output saved beside the original.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))
    }
}
