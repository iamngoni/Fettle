import SwiftUI

struct SmartNotesDetailView: View {
    @Bindable var tool: SmartNotesTool
    @Environment(AppState.self) private var app

    private let purple = Color(hex: 0xBF5AF2)
    private let red = Color(hex: 0xFF453A)

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                VStack(spacing: 10) {
                    recorderCard
                    if let error = tool.errorMessage { errorNote(error) }
                    if tool.state == .done, let summary = tool.summary {
                        summarySection(summary)
                        if !tool.transcript.isEmpty { transcriptSection }
                    }
                    note
                }
                .padding(16)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { app.route = .dashboard } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC7C7CE)).frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.card))
                }.buttonStyle(.plain)
                Text("Smart Notes").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.system(size: 10, weight: .bold))
                    Text("ON-DEVICE").font(.system(size: 9.5, weight: .bold)).tracking(0.5)
                }
                .foregroundStyle(.white).padding(.vertical, 3).padding(.horizontal, 7)
                .background(RoundedRectangle(cornerRadius: 6).fill(purple))
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            Hairline()
        }
    }

    @ViewBuilder
    private var recorderCard: some View {
        VStack(spacing: 12) {
            switch tool.state {
            case .idle:
                Button { tool.start() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "record.circle").font(.system(size: 18, weight: .bold))
                        Text("Start recording").font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 11).fill(purple))
                }.buttonStyle(.plain)
                Text("Captures system audio + your mic, then summarizes on-device.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center)

            case .recording:
                HStack(spacing: 8) {
                    Circle().fill(red).frame(width: 9, height: 9)
                    Text("REC \(tool.elapsedString)").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0xFF8077))
                    Spacer()
                }
                Button { tool.stop() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill").font(.system(size: 15))
                        Text("Stop & summarize").font(.system(size: 13.5, weight: .bold))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(red))
                }.buttonStyle(.plain)

            case .processing:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Transcribing & summarizing…").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
                }.frame(maxWidth: .infinity).frame(height: 44)

            case .done:
                Button { tool.reset() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 14))
                        Text("New recording").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 10).fill(purple))
                }.buttonStyle(.plain)
            }
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(purple.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(purple.opacity(0.25), lineWidth: 1))
    }

    private func summarySection(_ s: MeetingSummary) -> some View {
        VStack(spacing: 7) {
            HStack {
                SectionLabel(text: "SUMMARY · \(s.engine.uppercased())")
                Spacer()
                Button { tool.copyNotes() } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(s.summary).font(.system(size: 13)).foregroundStyle(Color(hex: 0xD7D7DC))
                    .fixedSize(horizontal: false, vertical: true)
                if !s.actionItems.isEmpty {
                    Divider().overlay(Theme.hairline)
                    ForEach(Array(s.actionItems.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(purple)
                            Text(item).font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xD7D7DC))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
        }
    }

    private var transcriptSection: some View {
        VStack(spacing: 7) {
            SectionLabel(text: "TRANSCRIPT")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(tool.transcript) { line in
                    Text("\(line.speaker):  ").font(.system(size: 12, weight: .semibold)).foregroundStyle(line.speaker == "You" ? Color(hex: 0x7DA8FF) : Color(hex: 0xC9B3DE))
                    + Text(line.text).font(.system(size: 12)).foregroundStyle(Color(hex: 0xA6A6AE))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
        }
    }

    private func errorNote(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(Theme.accent)
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }

    private var note: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            Text("Audio is transcribed and summarized entirely on-device.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))
    }
}
