import SwiftUI
import AppKit

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct SmartNotesDetailView: View {
    @Bindable var tool: SmartNotesTool
    @Environment(AppState.self) private var app

    @State private var contentHeight: CGFloat = 0

    /// Grow to fit content, but never taller than (almost) the screen.
    private var maxPanelHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return min(860, screen - 120)
    }

    private let purple = Color(hex: 0xBF5AF2)
    private let red = Color(hex: 0xFF453A)
    private let green = Color(hex: 0x30D158)

    @State private var showingSession = false

    var body: some View {
        Group {
            if showingSession, let summary = tool.summary {
                sessionScreen(summary)
            } else {
                homeScreen
            }
        }
        .onAppear { tool.loadSessions() }
        .onChange(of: tool.state) { _, newState in
            // After a recording finishes, open its own screen.
            if newState == .done { showingSession = true }
        }
    }

    private var homeScreen: some View {
        VStack(spacing: 0) {
            headerView(title: "Smart Notes") { app.route = .dashboard }
            scrollBody {
                recorderCard
                if let error = tool.errorMessage { errorNote(error) }
                engineSection
                historySection
                note
            }
        }
    }

    private func sessionScreen(_ summary: MeetingSummary) -> some View {
        VStack(spacing: 0) {
            headerView(title: tool.meetingTitle, pill: summary.engine) {
                showingSession = false
                tool.reset()
            }
            scrollBody {
                summarySection(summary)
                if !tool.transcript.isEmpty { transcriptSection }
            }
        }
    }

    /// Shared scroll container that grows to content height, capped at the screen.
    @ViewBuilder private func scrollBody<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 10) { content() }
                .padding(16)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                })
        }
        .frame(height: min(contentHeight == 0 ? maxPanelHeight : contentHeight, maxPanelHeight))
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
    }

    private var engineSection: some View {
        VStack(spacing: 14) {
            VStack(spacing: 7) {
                engineCard("TRANSCRIPTION", TranscriptionEngine.allCases, selected: tool.transcriptionEngine,
                           subtitle: { $0.subtitle }, badge: { _ in nil },
                           select: { tool.transcriptionEngine = $0 })
                if tool.transcriptionEngine == .whisper { whisperStatusRow }
            }
            VStack(spacing: 7) {
                engineCard("INTELLIGENCE", MeetingSummarizer.Engine.allCases, selected: tool.intelligenceEngine,
                           subtitle: { $0.subtitle }, badge: { _ in nil },
                           select: { tool.intelligenceEngine = $0 })
                if tool.intelligenceEngine.mlxVariant != nil { mlxStatusRow }
            }
            storageCard
        }
    }

    @ViewBuilder private var mlxStatusRow: some View {
        Card {
            Group {
                switch tool.mlxStatus {
                case .notLoaded:
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 15)).foregroundStyle(purple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(tool.intelligenceEngine.rawValue) not downloaded").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            Text("Runs locally via MLX · downloads once").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                        }
                        Spacer(minLength: 8)
                        Button { tool.downloadMLX() } label: {
                            Text("Download").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .padding(.vertical, 5).padding(.horizontal, 11)
                                .background(RoundedRectangle(cornerRadius: 7).fill(purple))
                        }.buttonStyle(.plain)
                    }
                case .downloading(let p):
                    VStack(spacing: 7) {
                        HStack {
                            Text("Downloading \(tool.intelligenceEngine.rawValue)…").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(Int(p * 100))%").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textPrimary)
                        }
                        ProgressView(value: p).tint(purple)
                    }
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading \(tool.intelligenceEngine.rawValue)…").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                case .ready:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(green)
                        Text("\(tool.intelligenceEngine.rawValue) ready").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                case .failed(let message):
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(red)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(tool.intelligenceEngine.rawValue) unavailable").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            Text(message).font(.system(size: 11)).foregroundStyle(Theme.textMuted).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Button { tool.downloadMLX() } label: {
                            Text("Retry").font(.system(size: 11, weight: .bold)).foregroundStyle(purple)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }

    @ViewBuilder private var whisperStatusRow: some View {
        Card {
            Group {
                switch tool.whisperStatus {
                case .notLoaded:
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 15)).foregroundStyle(purple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Whisper model not downloaded").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            Text("large-v3 · 626 MB · one-time").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                        }
                        Spacer(minLength: 8)
                        Button { tool.downloadWhisper() } label: {
                            Text("Download").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .padding(.vertical, 5).padding(.horizontal, 11)
                                .background(RoundedRectangle(cornerRadius: 7).fill(purple))
                        }.buttonStyle(.plain)
                    }
                case .downloading(let p):
                    VStack(spacing: 7) {
                        HStack {
                            Text("Downloading Whisper…").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(Int(p * 100))%").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textPrimary)
                        }
                        ProgressView(value: p).tint(purple)
                    }
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading Whisper…").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                case .ready:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(green)
                        Text("Whisper ready").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                case .failed(let message):
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(red)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Whisper unavailable").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            Text(message).font(.system(size: 11)).foregroundStyle(Theme.textMuted).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Button { tool.downloadWhisper() } label: {
                            Text("Retry").font(.system(size: 11, weight: .bold)).foregroundStyle(purple)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }

    private func engineCard<E: RawRepresentable & Equatable>(
        _ title: String, _ all: [E], selected: E,
        subtitle: @escaping (E) -> String, badge: @escaping (E) -> String?,
        select: @escaping (E) -> Void) -> some View where E.RawValue == String {
        VStack(spacing: 7) {
            SectionLabel(text: title)
            Card {
                ForEach(Array(all.enumerated()), id: \.offset) { index, engine in
                    if index > 0 { Hairline() }
                    Button { select(engine) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(engine.rawValue).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0xE5E5EA))
                                    if let b = badge(engine) {
                                        Text(b).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent)
                                            .padding(.vertical, 1).padding(.horizontal, 5)
                                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.accent.opacity(0.15)))
                                    }
                                }
                                Text(subtitle(engine)).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                            }
                            Spacer(minLength: 8)
                            if engine == selected {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(purple)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var storageCard: some View {
        VStack(spacing: 7) {
            SectionLabel(text: "STORAGE")
            Card {
                SettingRow(title: "Keep recordings", subtitle: "Save audio to a Fettle folder instead of deleting") {
                    FSwitch(isOn: $tool.keepRecordings, tint: purple)
                }
                if tool.keepRecordings {
                    Hairline()
                    Button { tool.openRecordingsFolder() } label: {
                        HStack {
                            Text("Show recordings").font(.system(size: 13, weight: .medium)).foregroundStyle(purple)
                            Spacer()
                            Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(purple)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var historySection: some View {
        if !tool.sessions.isEmpty {
            VStack(spacing: 7) {
                SectionLabel(text: "HISTORY")
                Card {
                    ForEach(Array(tool.sessions.prefix(25).enumerated()), id: \.element.id) { index, session in
                        if index > 0 { Hairline() }
                        HStack(spacing: 10) {
                            Button { tool.openSession(session); showingSession = true } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(session.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                    Text("\(dateText(session.date)) · \(session.durationText) · \(session.summary.engine)")
                                        .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button { tool.deleteSession(session) } label: {
                                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                    }
                }
            }
        }
    }

    private func dateText(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }

    private func headerView(title: String, pill: String? = nil, onBack: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC7C7CE)).frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.card))
                }.buttonStyle(.plain)
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.system(size: 10, weight: .bold))
                    Text((pill ?? "ON-DEVICE").uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(0.5).lineLimit(1)
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
                    Text(tool.processingMessage).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
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
            HStack(spacing: 12) {
                SectionLabel(text: "SUMMARY · \(s.engine.uppercased())")
                Spacer()
                Button { tool.reSummarize() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                        Text("Re-summarize").font(.system(size: 11, weight: .semibold))
                    }.foregroundStyle(purple)
                }.buttonStyle(.plain)
                Button { tool.copyNotes() } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 10) {
                MarkdownView(markdown: s.summary, accent: purple)
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
                    (Text("\(line.speaker):  ").font(.system(size: 12, weight: .semibold)).foregroundStyle(line.speaker == "You" ? Color(hex: 0x7DA8FF) : Color(hex: 0xC9B3DE))
                    + Text(line.text).font(.system(size: 12)).foregroundStyle(Color(hex: 0xA6A6AE)))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
