//
//  MetronomePendulum.swift
//  Tempo
//
//  A minimal mechanical pendulum, driven by the same audio clock as the
//  clicks. The rod leaves one extreme on a click, reaches the opposite extreme
//  exactly on the next click, and reverses there — the motion of a real
//  pendulum metronome rather than a decorative loop.
//

import SwiftUI

struct MetronomePendulum: View {
    @Environment(MetronomeEngine.self) private var engine

    let theme: TempoTheme
    let compact: Bool

    private var canvasSize: CGSize {
        compact ? CGSize(width: 210, height: 280) : CGSize(width: 320, height: 400)
    }

    private var maxAngle: Double { compact ? 22 : 24 }

    var body: some View {
        // The parity of the beat token flips once per beat. Combined with
        // cos(π·phase) this makes the rod continuous across clicks: it ends a
        // swing exactly where the next one begins.
        let parity: Double = engine.pulseToken.isMultiple(of: 2) ? 1 : -1
        let angle = engine.isRunning ? parity * maxAngle * cos(.pi * engine.beatPhase) : 0

        ZStack {
            GeometryReader { proxy in
                let size = proxy.size
                let pivot = CGPoint(x: size.width / 2, y: size.height - 7)
                let rodLength = size.height * 0.91

                rod(length: rodLength, angle: angle)
                    .position(x: pivot.x, y: pivot.y - rodLength / 2)

                Circle()
                    .fill(theme.primaryText.opacity(0.55))
                    .frame(width: 9, height: 9)
                    .position(x: pivot.x, y: pivot.y)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .accessibilityHidden(true)
    }

    // MARK: - Pieces

    private func rod(length: CGFloat, angle: Double) -> some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(theme.primaryText.opacity(0.55))
                .frame(width: 3, height: length)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.accent, theme.accent.opacity(0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 44, height: 14)
                .offset(y: -length * 0.62)

            Circle()
                .fill(theme.accent)
                .frame(width: 9, height: 9)
                .offset(y: -length + 4)
        }
        .frame(width: 52, height: length, alignment: .bottom)
        .rotationEffect(.degrees(angle), anchor: .bottom)
    }
}
