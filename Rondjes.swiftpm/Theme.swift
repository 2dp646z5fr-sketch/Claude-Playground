import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: 1)
    }
}

extension Color {
    /// A colour that follows light / dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// Colours and type, shared with the web version.
enum Theme {
    static let bg       = Color(light: 0xeef1ea, dark: 0x0f1612)
    static let surface  = Color(light: 0xfbfcf8, dark: 0x17201a)
    static let surface2 = Color(light: 0xf3f6ef, dark: 0x1c271f)
    static let ink      = Color(light: 0x142219, dark: 0xe7eee6)
    static let muted    = Color(light: 0x5d6b60, dark: 0x93a396)
    static let line     = Color(light: 0xd9dfd3, dark: 0x26322a)
    static let pine     = Color(light: 0x1f4d36, dark: 0xa6d396)
    static let pineInk  = Color(light: 0xf3f7ef, dark: 0x0f1612)
    static let moss     = Color(light: 0x6fa64c, dark: 0x86c262)
    static let mossSoft = Color(light: 0xe2eed8, dark: 0x1e3320)
    static let sun      = Color(light: 0xff6b2c, dark: 0xff7a3d)
    static let urban    = Color(light: 0xa3abae, dark: 0x5f696c)
    static let danger   = Color(light: 0xb42318, dark: 0xff8a7a)

    static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Small uppercase label.
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1)
            .foregroundStyle(Theme.muted)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var background: Color = Theme.pine
    var foreground: Color = Theme.pineInk
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 14)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: 14).fill(background))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(minHeight: 48)
            .padding(.horizontal, 14)
            .foregroundStyle(Theme.ink)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Card background used across the app.
extension View {
    func card(radius: CGFloat = 22) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.line))
    }
}
