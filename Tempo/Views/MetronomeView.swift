//
//  MetronomeView.swift
//  Tempo
//

import SwiftUI

struct MetronomeView: View {
    @Environment(MetronomeEngine.self) private var engine
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingTimeSignature = false
    @State private var showingSettings = false
    @State private var flashOpacity: Double = 0
    @State private var tapScale: CGFloat = 1

    private var theme: TempoTheme { TempoTheme(scheme: colorScheme) }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 700
            ZStack {
                TempoBackground(theme: theme)
                content(compact: compact)
                flashOverlay
            }
        }
        .onChange(of: engine.pulseToken) { _, _ in
            flash()
        }
        .onChange(of: scenePhase) { _, phase in
            engine.scenePhaseDidChange(phase)
        }
        .sheet(isPresented: $showingTimeSignature) {
            TimeSignatureSheet()
                .environment(engine)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet()
                .environment(engine)
        }
        .alert(
            Text("Audio unavailable"),
            isPresented: Binding(
                get: { engine.errorMessage != nil },
                set: { if !$0 { engine.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                engine.errorMessage = nil
            }
        } message: {
            Text(engine.errorMessage ?? "")
        }
    }

    // MARK: - Layout

    private func content(compact: Bool) -> some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: compact ? 4 : 14)
            beatSection
            Spacer(minLength: compact ? 6 : 16)
            tempoSection(compact: compact)

            sliderSection
                .padding(.top, compact ? 12 : 22)

            Spacer(minLength: compact ? 10 : 22)

            controlRow(compact: compact)
            statusLine
                .padding(.top, compact ? 10 : 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, compact ? 6 : 14)
        .frame(maxWidth: 560, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 10) {
            timeSignatureControl

            Spacer(minLength: 8)

            displayModeToggle

            GlassIconButton(systemName: "gearshape.fill", label: "Settings", theme: theme) {
                showingSettings = true
            }
        }
    }

    /// The time signature sits where a real music stand would put it: a
    /// stacked fraction, tappable for the picker.
    private var timeSignatureControl: some View {
        Button {
            showingTimeSignature = true
            Haptics.selectionChanged()
        } label: {
            HStack(spacing: 6) {
                Text(engine.timeSignature.displayName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(theme.surfaceStroke, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Time signature"))
        .accessibilityValue(Text(engine.timeSignature.displayName))
    }

    /// Compact two-way switch between the plain BPM number and the pendulum.
    private var displayModeToggle: some View {
        HStack(spacing: 2) {
            displayModeButton(.digits)
            displayModeButton(.pendulum)
        }
        .padding(3)
        .background(Capsule().fill(theme.surface))
        .overlay(Capsule().strokeBorder(theme.surfaceStroke, lineWidth: 1))
    }

    private func displayModeButton(_ mode: DisplayMode) -> some View {
        let selected = engine.displayMode == mode
        return Button {
            guard engine.displayMode != mode else { return }
            withAnimation(.snappy(duration: 0.24)) {
                engine.displayMode = mode
            }
            Haptics.selectionChanged()
        } label: {
            Image(systemName: mode.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? theme.onAccent : theme.secondaryText)
                .frame(width: 30, height: 30)
                .background(Circle().fill(selected ? theme.accent : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(mode.titleKey)))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var beatSection: some View {
        VStack(spacing: 8) {
            BeatTrack(
                beats: engine.timeSignature.beats,
                accents: engine.timeSignature.accentedBeats,
                current: engine.isRunning ? engine.displayedBeat : -1,
                theme: theme
            )

            HStack(spacing: 8) {
                if engine.isCountingIn {
                    Text("Count-in")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(theme.accent.opacity(0.14)))
                } else if engine.isRunning {
                    Text(verbatim: localizedInteger("Bar %lld", engine.displayedBar + 1))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(theme.secondaryText)
                } else {
                    Text("Ready")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .frame(height: 18)
        }
    }

    private func tempoSection(compact: Bool) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 7) {
                Text(LocalizedStringKey(engine.tempoMarking.descriptorKey))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Text(engine.tempoMarking.italian)
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(theme.secondaryText.opacity(0.72))
            }
            .frame(height: 18)

            if engine.displayMode == .digits {
                digitsTempo(compact: compact)
            } else {
                pendulumTempo(compact: compact)
            }
        }
    }

    private func digitsTempo(compact: Bool) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: compact ? 10 : 18) {
                HoldRepeatButton(systemName: "minus", theme: theme, size: compact ? 46 : 50) {
                    adjustBPM(by: -1)
                }

                Text("\(Int(engine.bpm.rounded()))")
                    .font(.system(size: compact ? 72 : 94, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: engine.bpm))
                    .animation(.snappy(duration: 0.16), value: engine.bpm)
                    .foregroundStyle(theme.primaryText)
                    .frame(minWidth: compact ? 132 : 176)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityLabel(Text("BPM"))
                    .accessibilityValue(Text("\(Int(engine.bpm.rounded()))"))

                HoldRepeatButton(systemName: "plus", theme: theme, size: compact ? 46 : 50) {
                    adjustBPM(by: 1)
                }
            }

            Text("BPM")
                .font(.system(size: 10, weight: .bold))
                .tracking(3.5)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func pendulumTempo(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 14) {
            HoldRepeatButton(systemName: "minus", theme: theme, size: compact ? 46 : 50) {
                adjustBPM(by: -1)
            }

            MetronomePendulum(theme: theme, compact: compact)

            HoldRepeatButton(systemName: "plus", theme: theme, size: compact ? 46 : 50) {
                adjustBPM(by: 1)
            }
        }
        .padding(.top, compact ? 4 : 8)
    }

    private var sliderSection: some View {
        VStack(spacing: 4) {
            TempoSlider(
                bpm: Binding(get: { engine.bpm }, set: { engine.bpm = $0 }),
                range: TempoMath.minBPM...TempoMath.maxBPM,
                theme: theme
            )

            HStack {
                Text("\(Int(TempoMath.minBPM))")
                Spacer()
                Text("120")
                Spacer()
                Text("\(Int(TempoMath.maxBPM))")
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(theme.secondaryText.opacity(0.8))
            .padding(.horizontal, 2)
        }
    }

    private func controlRow(compact: Bool) -> some View {
        let smallSize: CGFloat = compact ? 68 : 78
        let startSize: CGFloat = compact ? 82 : 96

        return HStack(alignment: .center, spacing: compact ? 16 : 30) {
            tapButton(size: smallSize)
            StartStopControl(size: startSize, theme: theme)
            subdivisionMenu(size: smallSize)
        }
    }

    private func tapButton(size: CGFloat) -> some View {
        Button {
            engine.tapTempoBPM()
            Haptics.tap()
            tapScale = 0.88
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                tapScale = 1
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: size * 0.23, weight: .semibold))
                Text("TAP")
                    .font(.system(size: size * 0.14, weight: .heavy))
                    .tracking(1.2)
            }
            .foregroundStyle(theme.primaryText.opacity(0.85))
            .frame(width: size, height: size)
            .background(Circle().fill(theme.surface))
            .overlay(Circle().strokeBorder(theme.surfaceStroke, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if engine.tapCount > 1 {
                    Text("\(engine.tapCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.onAccent)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Circle().fill(theme.accent))
                        .offset(x: 2, y: -2)
                }
            }
            .scaleEffect(tapScale)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Tap tempo"))
    }

    private func subdivisionMenu(size: CGFloat) -> some View {
        Menu {
            Picker(
                selection: Binding(
                    get: { engine.subdivision },
                    set: {
                        engine.subdivision = $0
                        Haptics.selectionChanged()
                    }
                )
            ) {
                ForEach(Subdivision.allCases) { subdivision in
                    Text(LocalizedStringKey(subdivision.titleKey)).tag(subdivision)
                }
            } label: {
                Text("Subdivision")
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: engine.subdivision.symbolName)
                    .font(.system(size: size * 0.21, weight: .semibold))
                Text("×" + engine.subdivision.badge)
                    .font(.system(size: size * 0.13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(theme.primaryText.opacity(0.85))
            .frame(width: size, height: size)
            .background(Circle().fill(theme.surface))
            .overlay(Circle().strokeBorder(theme.surfaceStroke, lineWidth: 1))
        }
        .accessibilityLabel(Text("Subdivision"))
        .accessibilityValue(Text(LocalizedStringKey(engine.subdivision.titleKey)))
    }

    private var statusLine: some View {
        HStack(spacing: 7) {
            if engine.isRunning {
                Text(verbatim: localizedInteger("Bar %lld", engine.displayedBar + 1))
                if engine.subdivision != .none {
                    Text("·")
                    Text("×" + engine.subdivision.badge)
                }
            } else {
                Text("Tap play to start")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(theme.secondaryText.opacity(0.85))
        .frame(height: 16)
        .animation(.easeInOut(duration: 0.2), value: engine.isRunning)
    }

    private var flashOverlay: some View {
        Rectangle()
            .fill(theme.accent)
            .opacity(flashOpacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    // MARK: - Actions

    private func adjustBPM(by delta: Double) {
        withAnimation(.snappy(duration: 0.14)) {
            engine.bpm += delta
        }
        Haptics.selectionChanged()
    }

    private func flash() {
        guard engine.flashEnabled,
              engine.isRunning,
              !engine.isCountingIn,
              engine.pulseKind == .accent
        else {
            return
        }

        flashOpacity = 0.09
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 40_000_000)
            withAnimation(.easeOut(duration: 0.30)) {
                flashOpacity = 0
            }
        }
    }
}

/// The transport button lives in its own view so the per-frame beat phase only
/// invalidates this small subtree instead of the whole screen.
private struct StartStopControl: View {
    @Environment(MetronomeEngine.self) private var engine

    let size: CGFloat
    let theme: TempoTheme

    var body: some View {
        ZStack {
            BeatPulseRing(phase: engine.beatPhase, isRunning: engine.isRunning, color: theme.accent)
                .frame(width: size + 16, height: size + 16)

            Button {
                engine.toggle()
                Haptics.tap()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [theme.accent, theme.accent.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Circle()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    Image(systemName: engine.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: size * 0.30, weight: .bold))
                        .foregroundStyle(theme.onAccent)
                        .offset(x: engine.isRunning ? 0 : size * 0.02)
                }
                .frame(width: size, height: size)
                .shadow(
                    color: theme.accent.opacity(engine.isRunning ? 0.55 : 0.28),
                    radius: engine.isRunning ? 22 : 14,
                    y: 6
                )
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(engine.isRunning ? Text("Stop") : Text("Start"))
        }
    }
}

#Preview {
    MetronomeView()
        .environment(MetronomeEngine())
}
