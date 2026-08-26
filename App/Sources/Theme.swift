// App/Sources/Theme.swift
import SwiftUI

/// All Neon-HUD design tokens live here — nowhere else defines colors/fonts.
enum Theme {
    static let background = Color(red: 0.03, green: 0.04, blue: 0.08)
    static let neonCyan = Color(red: 0.0, green: 0.95, blue: 1.0)
    static let neonMagenta = Color(red: 1.0, green: 0.15, blue: 0.75)
    static let neonAmber = Color(red: 1.0, green: 0.72, blue: 0.1)
    static let dimText = Color(white: 0.55)

    static func digits(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
    static let label = Font.system(size: 10, weight: .medium, design: .monospaced)

    /// Gauge color escalates with utilization.
    static func gaugeColor(percent: Double) -> Color {
        switch percent {
        case ..<60: neonCyan
        case ..<85: neonAmber
        default: neonMagenta
        }
    }
}

/// Horizontal neon gauge with glow.
struct NeonGauge: View {
    let title: String
    let percent: Double        // 0...100
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title.uppercased()).font(Theme.label).foregroundStyle(Theme.dimText)
                Spacer()
                Text("\(Int(percent))%")
                    .font(Theme.digits(13))
                    .foregroundStyle(Theme.gaugeColor(percent: percent))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Theme.gaugeColor(percent: percent))
                        .frame(width: max(4, geo.size.width * percent / 100))
                        .shadow(color: Theme.gaugeColor(percent: percent).opacity(0.8), radius: 6)
                }
            }
            .frame(height: 6)
            if let subtitle {
                Text(subtitle).font(Theme.label).foregroundStyle(Theme.dimText)
            }
        }
    }
}

/// Faint CRT scanlines over the panel.
struct ScanlineOverlay: View {
    var body: some View {
        Canvas { context, size in
            // swiftlint:disable:next identifier_name
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(.black.opacity(0.18)))
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}
