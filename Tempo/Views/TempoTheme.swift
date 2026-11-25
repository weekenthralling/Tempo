//
//  TempoTheme.swift
//  Tempo
//

import SwiftUI

/// One place for the app's palette, so light and dark mode stay in sync.
struct TempoTheme {
    let scheme: ColorScheme

    var isDark: Bool { scheme == .dark }

    var backgroundTop: Color {
        isDark
            ? Color(red: 0.078, green: 0.080, blue: 0.098)
            : Color(red: 0.980, green: 0.968, blue: 0.948)
    }

    var backgroundBottom: Color {
        isDark
            ? Color(red: 0.032, green: 0.033, blue: 0.042)
            : Color(red: 0.902, green: 0.884, blue: 0.858)
    }

    var accent: Color {
        isDark
            ? Color(red: 1.00, green: 0.64, blue: 0.18)
            : Color(red: 0.94, green: 0.50, blue: 0.04)
    }

    /// Color that stays readable on top of `accent`.
    var onAccent: Color {
        isDark ? Color.black.opacity(0.88) : Color.white
    }

    var primaryText: Color {
        isDark ? Color.white.opacity(0.95) : Color(red: 0.11, green: 0.10, blue: 0.09)
    }

    var secondaryText: Color {
        isDark ? Color.white.opacity(0.50) : Color(red: 0.42, green: 0.40, blue: 0.37)
    }

    var surface: Color {
        isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.70)
    }

    var surfaceStroke: Color {
        isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    var track: Color {
        isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    var backgroundGradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }
}

struct TempoBackground: View {
    let theme: TempoTheme

    var body: some View {
        ZStack {
            theme.backgroundGradient
            RadialGradient(
                colors: [theme.accent.opacity(theme.isDark ? 0.14 : 0.10), .clear],
                center: .top,
                startRadius: 12,
                endRadius: 420
            )
            .offset(y: -140)
        }
        .ignoresSafeArea()
    }
}

/// A small round, glassy icon button used in the header.
struct GlassIconButton: View {
    let systemName: String
    let label: LocalizedStringKey
    let theme: TempoTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.primaryText.opacity(0.8))
                .frame(width: 40, height: 40)
                .background(Circle().fill(theme.surface))
                .overlay(Circle().strokeBorder(theme.surfaceStroke, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A "+" or "−" button that fires once on tap and then repeats while held,
/// which is how people expect a tempo control to behave.
struct HoldRepeatButton: View {
    let systemName: String
    let theme: TempoTheme
    var size: CGFloat = 50
    let action: () -> Void

    @State private var isPressing = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(theme.primaryText.opacity(0.85))
            .frame(width: size, height: size)
            .background(Circle().fill(theme.surface))
            .overlay(Circle().strokeBorder(theme.surfaceStroke, lineWidth: 1))
            .contentShape(Circle())
            .scaleEffect(isPressing ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressing)
            .onLongPressGesture(minimumDuration: 0.30, maximumDistance: 40) {
                // Repeat is driven by the press state below.
            } onPressingChanged: { pressing in
                isPressing = pressing
                if pressing {
                    action()
                    startRepeating()
                } else {
                    stopRepeating()
                }
            }
            .onDisappear(perform: stopRepeating)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(systemName == "plus" ? Text("Increase tempo") : Text("Decrease tempo"))
            .accessibilityAction { action() }
    }

    private func startRepeating() {
        stopRepeating()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 380_000_000)
            while !Task.isCancelled {
                action()
                try? await Task.sleep(nanoseconds: 85_000_000)
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

/// Custom slider with a chunky thumb, because the stock slider is too thin for
/// a control that gets used with the phone resting on a music stand.
struct TempoSlider: View {
    @Binding var bpm: Double
    let range: ClosedRange<Double>
    let theme: TempoTheme

    @State private var isDragging = false

    private let thumbSize: CGFloat = 28
    private let trackHeight: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = CGFloat((bpm - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbX = progress * (width - thumbSize)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.track)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [theme.accent.opacity(0.55), theme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(thumbX + thumbSize / 2, trackHeight), height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(theme.accent, lineWidth: 3))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: theme.accent.opacity(0.35), radius: isDragging ? 10 : 5, y: 2)
                    .scaleEffect(isDragging ? 1.12 : 1)
                    .offset(x: thumbX)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let ratio = min(max((value.location.x - thumbSize / 2) / (width - thumbSize), 0), 1)
                        let raw = range.lowerBound + Double(ratio) * (range.upperBound - range.lowerBound)
                        bpm = raw.rounded()
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: 40)
        .accessibilityElement()
        .accessibilityLabel(Text("BPM"))
        .accessibilityValue(Text("\(Int(bpm.rounded()))"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                bpm = min(bpm + 1, range.upperBound)
            case .decrement:
                bpm = max(bpm - 1, range.lowerBound)
            @unknown default:
                break
            }
        }
    }
}

/// The row of dots showing where we are in the bar.
struct BeatTrack: View {
    let beats: Int
    let accents: Set<Int>
    let current: Int
    let theme: TempoTheme

    /// Dense meters (up to 16 beats) shrink so a bar always fits on the
    /// narrowest iPhone without wrapping or clipping.
    private var isDense: Bool { beats > 8 }
    private var spacing: CGFloat { isDense ? 4 : 9 }
    private var slot: CGFloat { isDense ? 13 : 17 }
    private var dotSize: CGFloat { isDense ? 7 : 9 }
    private var activeDotSize: CGFloat { isDense ? 9 : 11 }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<max(beats, 1), id: \.self) { index in
                let isCurrent = index == current
                let isAccent = accents.contains(index)

                ZStack {
                    if isAccent {
                        Circle()
                            .strokeBorder(theme.primaryText.opacity(0.22), lineWidth: 1.2)
                            .frame(width: slot - 0.5, height: slot - 0.5)
                    }
                    Circle()
                        .fill(isCurrent ? theme.accent : theme.primaryText.opacity(isAccent ? 0.34 : 0.16))
                        .frame(width: isCurrent ? activeDotSize : dotSize, height: isCurrent ? activeDotSize : dotSize)
                        .shadow(color: isCurrent ? theme.accent.opacity(0.9) : .clear, radius: 7)
                }
                .frame(width: slot, height: slot)
                .scaleEffect(isCurrent ? 1.18 : 1)
                .animation(.spring(response: 0.2, dampingFraction: 0.55), value: current)
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }
}

/// Progress arc around the start button, driven by the audio clock.
struct BeatPulseRing: View {
    let phase: Double
    let isRunning: Bool
    let color: Color

    var body: some View {
        Circle()
            .trim(from: 0, to: isRunning ? max(min(phase, 1), 0.001) : 0)
            .stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

@MainActor
enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let impact = UIImpactFeedbackGenerator(style: .light)

    static func selectionChanged() {
        selection.selectionChanged()
        selection.prepare()
    }

    static func tap() {
        impact.impactOccurred()
        impact.prepare()
    }
}
