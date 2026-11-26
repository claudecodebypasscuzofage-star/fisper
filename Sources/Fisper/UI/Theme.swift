import SwiftUI
import AppKit

extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
    init(hex: UInt32, alpha: Double = 1) { self.init(nsColor: NSColor(hex: hex, alpha: alpha)) }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// Apple-style neutrals (System Settings / Notes palette) + one user-selectable accent.
enum Theme {
    static let sidebar = Color.dynamic(light: 0xEEEEF0, dark: 0x1C1C1E)
    static let canvas = Color.dynamic(light: 0xF5F5F7, dark: 0x1E1E20)
    static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x2A2A2D)
    static let cardAlt = Color.dynamic(light: 0xF2F2F5, dark: 0x323235)
    static let border = Color.dynamic(light: 0xE2E2E7, dark: 0x3A3A3D)
    static let hairline = Color.dynamic(light: 0xEDEDF0, dark: 0x343437)
    static let text = Color(nsColor: .labelColor)
    static let text2 = Color(nsColor: .secondaryLabelColor)
    static let text3 = Color(nsColor: .tertiaryLabelColor)
    static let cream = Color.dynamic(light: 0xFFFFFF, dark: 0x2A2A2D)
    static let creamBorder = border
    static let ink = Color.dynamic(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let inkText = Color.dynamic(light: 0xFFFFFF, dark: 0x1D1D1F)
    static let selection = Color.dynamic(light: 0xE4E4E9, dark: 0x3A3A3D)
    static let danger = Color(nsColor: .systemRed)
    static let success = Color(nsColor: .systemGreen)
    static let warnBG = Color.dynamic(light: 0xFFF6EA, dark: 0x3A2E20)
    static let warnBorder = Color.dynamic(light: 0xF5DDBB, dark: 0x5C4630)
    static let lilac = Color.dynamic(light: 0xEFE6FF, dark: 0x3B2F52)
    static let lilacText = Color.dynamic(light: 0x5B3A99, dark: 0xD9C6FF)

    /// The accent the user picked (Appearance → Accent). The root view is re-identified when it changes.
    @MainActor static var forest: Color { Preferences.shared.accent.color }
    @MainActor static var forestSoft: Color { forest.opacity(0.13) }

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .default) }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }
    private struct PrimaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(Theme.forest.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)))
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 13).padding(.vertical, 6.5)
            .background(Capsule().fill(Theme.cardAlt.opacity(configuration.isPressed ? 0.6 : 1)))
            .overlay(Capsule().stroke(Theme.border))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var fill: Color = Theme.card
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
    }
}

/// A key-cap style label, e.g. [fn]
struct KeyCap: View {
    let label: String
    var size: CGFloat = 12
    var body: some View {
        Text(label)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .frame(minWidth: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.border))
            .shadow(color: .black.opacity(0.08), radius: 0, x: 0, y: 1)
    }
}

/// Fisper's mark: a soft speech capsule with waveform bars.
struct FisperMark: View {
    var size: CGFloat = 20
    var body: some View {
        ZStack {
            Capsule().fill(Theme.forest.gradient).frame(width: size * 1.45, height: size)
            HStack(spacing: size * 0.12) {
                ForEach([0.38, 0.7, 0.5, 0.28], id: \.self) { h in
                    Capsule().fill(Color.white).frame(width: size * 0.12, height: size * h)
                }
            }
        }
    }
}
