import SwiftUI

struct MeetingsDetailView: View {
    @Bindable var tool: MeetingsTool
    @Environment(AppState.self) private var app

    private let accent = Color(hex: 0x0A84FF)
    private let green = Color(hex: 0x32D74B)

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Meetings",
                        pill: tool.isActive ? ("On", green) : ("Off", Theme.textTertiary)) {
                app.route = .dashboard
            }
            Group {
                VStack(spacing: 10) {
                    if !tool.authorized {
                        accessPrompt
                    } else if let next = tool.nextMeeting {
                        nextMeetingHero(next)
                    } else {
                        emptyState
                    }
                    if tool.upcoming.count > 1 { laterToday }
                    alertSettings
                    if tool.authorized { previewButton }
                    note
                }
                .padding(16)
            }
            .onAppear { tool.refresh() }
        }
    }

    private var accessPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 26)).foregroundStyle(accent)
            Text("Calendar access needed").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(tool.accessDenied
                 ? "Calendar access was denied. Enable Fettle under Privacy → Calendars."
                 : "Fettle reads your calendar locally to alert you before meetings.")
                .font(.system(size: 12)).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center)
            Button { tool.requestAccess() } label: {
                Text(tool.accessDenied ? "Open Settings" : "Grant access")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.vertical, 10).padding(.horizontal, 18)
                    .background(RoundedRectangle(cornerRadius: 10).fill(accent))
            }.buttonStyle(.plain).padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(20)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
    }

    private func nextMeetingHero(_ m: MeetingEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "clock").font(.system(size: 12))
                    Text(m.startsInText).font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.vertical, 4).padding(.horizontal, 9)
                .background(Capsule().fill(accent))
                Spacer()
                Text(m.sourceName).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(hex: 0x9CC8FF))
            }
            Text(m.title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text(m.attendees > 0 ? "\(m.timeRange) · with \(m.attendees) people" : m.timeRange)
                .font(.system(size: 12)).foregroundStyle(Color(hex: 0xB8C9DC))
            Button { tool.join(m) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "video.fill").font(.system(size: 16))
                    Text("Join now").font(.system(size: 13.5, weight: .bold))
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(accent))
            }
            .buttonStyle(.plain).disabled(m.url == nil).opacity(m.url == nil ? 0.4 : 1)
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(accent.opacity(0.25), lineWidth: 1))
    }

    private var laterToday: some View {
        VStack(spacing: 7) {
            SectionLabel(text: "LATER TODAY")
            Card {
                ForEach(Array(tool.upcoming.dropFirst().prefix(5).enumerated()), id: \.element.id) { index, m in
                    if index > 0 { Hairline() }
                    HStack(spacing: 11) {
                        Text(shortTime(m.start)).font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xC7C7CE)).frame(width: 52, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Text(m.sourceName).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                        }
                        Spacer(minLength: 8)
                        Circle().fill(m.calendarColor).frame(width: 8, height: 8)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                }
            }
        }
    }

    private var alertSettings: some View {
        VStack(spacing: 7) {
            SectionLabel(text: "ALERT")
            Card {
                SettingRow(title: "Full-screen alert") { FSwitch(isOn: $tool.alertEnabled, tint: green) }
                Hairline()
                SettingRow(title: "Alert lead time") {
                    HStack(spacing: 8) {
                        Text("\(Int(tool.leadMinutes)) min").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        Stepper("", value: $tool.leadMinutes, in: 1...15).labelsHidden().scaleEffect(0.8)
                    }
                }
                Hairline()
                SettingRow(title: "Auto-open meeting link") { FSwitch(isOn: $tool.autoOpenLink, tint: green) }
                Hairline()
                SettingRow(title: "Play alert sound") { FSwitch(isOn: $tool.playSound, tint: green) }
            }
        }
    }

    private var previewButton: some View {
        Button { tool.testAlert() } label: {
            HStack(spacing: 7) {
                Image(systemName: "play.rectangle").font(.system(size: 13))
                Text("Preview alert").font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        }.buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar").font(.system(size: 22)).foregroundStyle(Theme.textTertiary)
            Text("No more meetings today").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 26)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
    }

    private var note: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            Text("Fettle reads calendars locally via EventKit — events never leave your Mac.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: date)
    }
}
