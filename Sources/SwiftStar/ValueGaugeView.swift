import SwiftUI

/// 3/4-arc ring gauge (270° sweep, gap at the bottom, rounded caps),
/// severity-colored — ported from the DS4 Control agent window's status bar.
/// `text` nil = a bare ring for small status-bar indicators that rely on
/// `.help()` for their label rather than baking it into the ring.
struct ValueGaugeView: View {
    let fraction: Double  // 0.0 – 1.0
    let text: String?
    let textFontSize: CGFloat
    let trackColor: Color
    var diameter: CGFloat = 60

    private let sweep: Double = 0.75  // 270° arc, gap at the bottom
    private var lineWidth: CGFloat { max(diameter * 0.09, 3) }
    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(Color.secondary.opacity(0.22), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: sweep * clamped)
                .stroke(trackColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.4), value: clamped)

            if let text {
                Text(text)
                    .font(.system(size: textFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, lineWidth + 2)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}
