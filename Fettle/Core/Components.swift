import SwiftUI

// MARK: - Icon tile

struct IconTile: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 28
    var glyph: CGFloat = 16
    var gradient: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(gradient ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(tint.opacity(0.15)))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: glyph, weight: .semibold))
                    .foregroundStyle(gradient ? Color(hex: 0x3A1D00) : tint)
            )
    }
}

// MARK: - Status pill

struct StatusPill: View {
    var text: String
    var color: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color == Theme.textTertiary ? Theme.textSecondary : color)
        }
        .padding(.vertical, 5).padding(.horizontal, 9)
        .background(Capsule().fill(color.opacity(0.13)))
    }
}

// MARK: - Card container

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Switch

struct FSwitch: View {
    @Binding var isOn: Bool
    var tint: Color = Theme.accent
    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(tint)
            .scaleEffect(0.85)
    }
}

// MARK: - Duration / preset chip

struct Chip: View {
    var label: String
    var isSelected: Bool
    var tint: Color = Theme.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.accentLight : Color(hex: 0xC7C7CE))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? tint.opacity(0.14) : Theme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isSelected ? tint : .clear, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Panel header (detail screens)

struct PanelHeader: View {
    var title: String
    var pill: (text: String, color: Color)?
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC7C7CE))
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.card))
                }
                .buttonStyle(.plain)
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                if let pill { StatusPill(text: pill.text, color: pill.color) }
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            Hairline()
        }
    }
}

// MARK: - Primary button

struct PrimaryButton: View {
    var title: String
    var symbol: String
    var gradient: LinearGradient = Theme.accentGradient
    var fg: Color = Color(hex: 0x3A1D00)
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 16, weight: .bold))
                Text(title).font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(gradient))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings-style row with label + trailing control

struct SettingRow<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var subtitleTint: Color = Theme.textMuted
    var symbol: String?
    var symbolOn: Bool = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 11) {
            if let symbol {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(symbolOn ? Theme.accentLight : Theme.textSecondary))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0xE5E5EA))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(subtitleTint)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}
