//
//  MetronomePendulum.swift
//  Tempo
//
//  A stylised mechanical metronome, driven by the same audio clock as the
//  clicks. The rod leaves one extreme on a click, reaches the opposite extreme
//  exactly on the next click, and reverses there — the motion of a real
//  pendulum metronome rather than a decorative loop.
//

import SwiftUI

struct MetronomePendulum: View {
    @Environment(MetronomeEngine.self) private var engine

    let theme: TempoTheme
    let compact: Bool

    private var width: CGFloat { compact ? 150 : 196 }
    private var height: CGFloat { compact ? 158 : 204 }
    private var maxAngle: Double { compact ? 22 : 24 }

    var body: some View {
        // The parity of the beat token flips once per beat. Combined with
        // cos(π·phase) this makes the rod continuous across clicks: it ends a
        // swing exactly where the next one begins.
        let parity: Double = engine.pulseToken.isMultiple(of: 2) ? 1 : -1
        let angle = engine.isRunning ? parity * maxAngle * cos(.pi * engine.beatPhase) : 0

        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(theme.surface)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(theme.surfaceStroke, lineWidth: 1)

            GeometryReader { proxy in
                let size = proxy.size
                let pivot = CGPoint(x: size.width / 2, y: size.height * 0.78)
                let rodLength = size.height * 0.64
                let scaleRadius = rodLength * 0.98

                scaleArc(pivot: pivot, radius: scaleRadius)

                ForEach(0...8, id: \.self) { index in
                    let t = Double(index) / 8 - 0.5
                    let tickAngle = t * 2 * maxAngle
                    let isCenter = index == 4
                    let inner = scaleRadius - (isCenter ? 11 : 6)

                    Path { path in
                        path.move(to: point(from: pivot, radius: inner, angle: tickAngle))
                        path.addLine(to: point(from: pivot, radius: scaleRadius, angle: tickAngle))
                    }
                    .stroke(
                        isCenter ? theme.accent.opacity(0.85) : theme.primaryText.opacity(0.22),
                        style: StrokeStyle(lineWidth: isCenter ? 2.5 : 1.5, lineCap: .round)
                    )
                }

                Circle()
                    .fill(theme.primaryText.opacity(0.55))
                    .frame(width: 9, height: 9)
                    .position(x: pivot.x, y: pivot.y)

                rod(length: rodLength, angle: angle)
                    .position(x: pivot.x, y: pivot.y - rodLength / 2)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(engine.bpm.rounded()))")
                        .font(.system(size: compact ? 28 : 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("BPM")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(theme.secondaryText)
                }
                .foregroundStyle(theme.primaryText)
                .position(x: size.width / 2, y: size.height - (compact ? 20 : 24))
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("BPM"))
        .accessibilityValue(Text("\(Int(engine.bpm.rounded()))"))
    }

    // MARK: - Pieces

    private func scaleArc(pivot: CGPoint, radius: CGFloat) -> some View {
        Path { path in
            for step in 0...24 {
                let angle = -maxAngle + Double(step) / 24 * 2 * maxAngle
                let point = point(from: pivot, radius: radius, angle: angle)
                if step == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
        .stroke(theme.primaryText.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    private func rod(length: CGFloat, angle: Double) -> some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(theme.primaryText.opacity(0.55))
                .frame(width: 2.5, height: length)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.accent, theme.accent.opacity(0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 30, height: 11)
                .offset(y: -length * 0.62)

            Circle()
                .fill(theme.accent)
                .frame(width: 8, height: 8)
                .offset(y: -length + 4)
        }
        .frame(width: 44, height: length, alignment: .bottom)
        .rotationEffect(.degrees(angle), anchor: .bottom)
    }

    private func point(from pivot: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        let radians = (angle - 90) * .pi / 180
        return CGPoint(
            x: pivot.x + radius * CGFloat(cos(radians)),
            y: pivot.y + radius * CGFloat(sin(radians))
        )
    }
}
