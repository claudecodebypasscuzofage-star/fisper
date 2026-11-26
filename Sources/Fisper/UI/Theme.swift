import SwiftUI
import AppKit

extension Color {
    /// A color that adapts to light/dark appearance.
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

enum Theme {
    static let sidebar = Color.dynamic(light: 0xF3F2EE, dark: 0x1B1B1A)
    static let canvas = Color.dynamic(light: 0xFCFCFA, dark: 0x232322)
    static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x2B2B2A)
    static let cardAlt = Color.dynamic(light: 0xF7F6F2, dark: 0x2A2A28)
    static let border = Color.dynamic(light: 0xE7E5DF, dark: 0x3A3A37)
    static let hairline = Color.dynamic(light: 0xEFEDE8, dark: 0x333331)
    static let text = Color.dynamic(light: 0x1B1B1A, dark: 0xF2F1EC)
    static let text2 = Color.dynamic(light: 0x5F5E5A, dark: 0xB4B2AB)
    static let text3 = Color.dynamic(light: 0x9A9892, dark: 0x7D7B75)
    static let cream = Color.dynamic(light: 0xFFFEE9, dark: 0x2F2E22)
    static let creamBorder = Color.dynamic(light: 0xEDEBC6, dark: 0x4A4830)
    static let forest = Color.dynamic(light: 0x0E5A4F, dark: 0x3FB59C)
    static let forestSoft = Color.dynamic(light: 0xDCEFEA, dark: 0x1E3B35)
    static let lilac = Color.dynamic(light: 0xEEDCFF, dark: 0x3F2F55)
    static let lilacText = Color.dynamic(light: 0x5A2D8A, dark: 0xD8BDFF)
    static let ink = Color.dynamic(light: 0x1C1C1B, dark: 0xF2F1EC)
    static let inkText = Color.dynamic(light: 0xFFFFFF, dark: 0x1C1C1B)
    static let selection = Color.dynamic(light: 0xE6E4DE, dark: 0x2E2E2C)
    static let danger = Color.dynamic(light: 0xC2412D, dark: 0xFF8A73)
    static let warnBG = Color.dynamic(light: 0xFFF3E6, dark: 0x3A2A1C)
    static let warnBorder = Color.dynamic(light: 0xF2D2AE, dark: 0x5C432B)

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.inkText)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.ink.opacity(configuration.isPressed ? 0.8 : 1)))
            .contentShape(Rectangle())
    }
}

struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.cardAlt.opacity(configuration.isPressed ? 0.6 : 1)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.border))
            .contentShape(Rectangle())
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
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

/// A key-cap style label, e.g. [fn]
struct KeyCap: View {
    let label: String
    var size: CGFloat = 13
    var body: some View {
        Text(label)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.border))
            .shadow(color: .black.opacity(0.06), radius: 0, x: 0, y: 1)
    }
}

/// Fisper's mark: a soft speech capsule with three waveform bars.
struct FisperMark: View {
    var size: CGFloat = 20
    var body: some View {
        ZStack {
            Capsule().fill(Theme.forest).frame(width: size * 1.45, height: size)
            HStack(spacing: size * 0.12) {
                ForEach([0.38, 0.7, 0.5, 0.28], id: \.self) { h in
                    Capsule().fill(Color.white).frame(width: size * 0.12, height: size * h)
                }
            }
        }
    }
}
