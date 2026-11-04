import SwiftUI
import UIKit
import Shared

/// The brand's accents, the same values as Android's theme; neutrals stay iOS system colours.
enum Brand {
    static let primary = Color(light: 0x7F77DD, dark: 0xAFA9EC)
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x26215C)
    static let primaryContainer = Color(light: 0xECEAFB, dark: 0x3B3684)
    static let onPrimaryContainer = Color(light: 0x26215C, dark: 0xE5E2FA)
    /// The trip's start and "go" accents.
    static let start = Color(light: 0x188038, dark: 0x81C995)
    static let error = Color(light: 0xD93025, dark: 0xF28B82)
    static let errorContainer = Color(light: 0xF9DEDC, dark: 0x8C1D18)
    static let onErrorContainer = Color(light: 0x410E0B, dark: 0xF9DEDC)
    static let sectionOutline = Color(light: 0xA8C7FA, dark: 0x4A6FA5)

    static func mode(_ mode: ChargeMode) -> Color {
        mode == .ac ? Color(light: 0xBD5A03, dark: 0xD7A96C) : Color(light: 0x068475, dark: 0x62C6BC)
    }

    static func onMode(_ mode: ChargeMode) -> Color {
        mode == .ac ? Color(light: 0xFFFFFF, dark: 0x2E1C05) : Color(light: 0xFFFFFF, dark: 0x05201C)
    }

    static func operatorColor(_ site: ChargeSite) -> Color {
        Color(argb: OperatorColors.shared.of(site: site))
    }

    static func networkColor(_ key: String) -> Color {
        Color(argb: OperatorColors.shared.network(key: key))
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(argb: Int64) {
        self.init(uiColor: UIColor(rgb: UInt32(truncatingIfNeeded: argb & 0xFFFFFF)))
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The numbered disc for a stop or a ranked charger, in its network's colour.
struct RankBadge: View {
    let number: Int
    let color: Color
    var textColor: Color = .white

    var body: some View {
        Text("\(number)")
            .font(.caption2.weight(.heavy))
            .monospacedDigit()
            .foregroundStyle(textColor)
            .frame(width: 24, height: 24)
            .background(color, in: Circle())
    }
}

/// The brand mark and wordmark, as on Android's drawer head.
struct BrandHead: View {
    var body: some View {
        HStack(spacing: 14) {
            Image("PowertripMark").resizable().scaledToFit().frame(height: 24)
            Image("PowertripWordmark").resizable().scaledToFit().frame(height: 32)
                .accessibilityLabel(localized("app_name"))
        }
    }
}

extension View {
    /// The filled brand button; its label takes the colour that reads on the primary in either theme.
    func brandProminent() -> some View {
        modifier(BrandProminent())
    }

    /// Controls over the map: an opaque surface, so they read on any map.
    func floatingSurface<S: Shape>(in shape: S) -> some View {
        background(Color(.secondarySystemGroupedBackground), in: shape)
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}

private struct BrandProminent: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        // Disabled, the system's own label colour is the one that reads on its grey fill.
        if isEnabled {
            content.buttonStyle(.borderedProminent).tint(Brand.primary).foregroundStyle(Brand.onPrimary)
        } else {
            content.buttonStyle(.borderedProminent).tint(Brand.primary)
        }
    }
}

/// "9 h 16 min" or "42 min" — durations, not clock times.
func durationText(_ minutes: Double) -> String {
    let total = Int(minutes.rounded())
    let hours = total / 60
    let rest = total % 60
    return hours > 0
        ? localized("trip_duration_hours_minutes", Int32(hours), Int32(rest))
        : localized("trip_duration_minutes", Int32(rest))
}

/// Wall-clock arrival: now plus the ETA offset, in the device's 12/24 h style.
func etaText(_ minutesFromStart: Double, now: Date) -> String {
    now.addingTimeInterval(minutesFromStart * 60).formatted(date: .omitted, time: .shortened)
}
