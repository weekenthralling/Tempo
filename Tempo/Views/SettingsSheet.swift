//
//  SettingsSheet.swift
//  Tempo
//

import SwiftUI

struct SettingsSheet: View {
    @Environment(MetronomeEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var theme: TempoTheme { TempoTheme(scheme: colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    soundCard
                    timingCard
                    feedbackCard
                    audioCard
                    aboutCard
                }
                .padding(20)
            }
            .background(TempoBackground(theme: theme))
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .tint(theme.accent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Cards

    private var soundCard: some View {
        card("Click sound") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: 8)],
                spacing: 8
            ) {
                ForEach(ClickSound.allCases) { sound in
                    soundChip(sound)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)

                Slider(
                    value: Binding(get: { engine.volume }, set: { engine.volume = $0 }),
                    in: 0...1
                )
                .tint(theme.accent)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }

            Button {
                engine.previewClickSound()
                Haptics.tap()
            } label: {
                Label("Preview sound", systemImage: "play.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(engine.isRunning)
            .opacity(engine.isRunning ? 0.45 : 1)
        }
    }

    private var timingCard: some View {
        card("Timing") {
            HStack(spacing: 12) {
                Text("Count-in")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.primaryText)

                Spacer(minLength: 8)

                Picker(
                    "Count-in",
                    selection: Binding(get: { engine.countInBars }, set: { engine.countInBars = $0 })
                ) {
                    Text("Off").tag(0)
                    Text("1 bar").tag(1)
                    Text("2 bars").tag(2)
                    Text("3 bars").tag(3)
                    Text("4 bars").tag(4)
                }
                .pickerStyle(.menu)
                .tint(theme.accent)
                .labelsHidden()
            }

            Divider().overlay(theme.surfaceStroke)

            settingToggle(
                title: "Accent first beat",
                systemImage: "bolt.fill",
                isOn: Binding(get: { engine.accentFirstBeat }, set: { engine.accentFirstBeat = $0 })
            )
        }
    }

    private var feedbackCard: some View {
        card("Feedback") {
            settingToggle(
                title: "Beat haptics",
                systemImage: "iphone.radiowaves.left.and.right",
                isOn: Binding(get: { engine.hapticsEnabled }, set: { engine.hapticsEnabled = $0 })
            )

            Divider().overlay(theme.surfaceStroke)

            settingToggle(
                title: "Flash on accent",
                systemImage: "sun.max.fill",
                isOn: Binding(get: { engine.flashEnabled }, set: { engine.flashEnabled = $0 })
            )
        }
    }

    private var audioCard: some View {
        card("Audio") {
            settingToggle(
                title: "Mix with other audio",
                systemImage: "music.note",
                isOn: Binding(get: { engine.mixWithOtherAudio }, set: { engine.mixWithOtherAudio = $0 })
            )

            Divider().overlay(theme.surfaceStroke)

            settingToggle(
                title: "Keep screen awake",
                systemImage: "light.max",
                isOn: Binding(get: { engine.keepScreenAwake }, set: { engine.keepScreenAwake = $0 })
            )

            Text("Tempo uses the playback audio session, so it keeps ticking with the screen locked or the silent switch on. Lock screen play/pause works too.")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aboutCard: some View {
        card("About") {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "metronome.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.accent))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tempo")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    Text("Version \(Self.appVersion)")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()
            }

            Text("A single-purpose metronome. No ads, no tracking, no network access.")
                .font(.system(size: 13))
                .foregroundStyle(theme.primaryText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: "SwiftUI · AVAudioEngine")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText.opacity(0.8))
        }
    }

    // MARK: - Components

    private func soundChip(_ sound: ClickSound) -> some View {
        let selected = engine.clickSound == sound

        return Button {
            engine.clickSound = sound
            engine.previewClickSound()
            Haptics.selectionChanged()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: sound.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                Text(LocalizedStringKey(sound.titleKey))
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? theme.accent.opacity(0.16) : theme.track)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? theme.accent.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func settingToggle(title: LocalizedStringKey, systemImage: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.primaryText)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(theme.accent)
                .accessibilityLabel(Text(title))
        }
    }

    private func card<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(theme.secondaryText)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.surfaceStroke, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        default:
            return "1.0"
        }
    }
}

#Preview {
    SettingsSheet()
        .environment(MetronomeEngine())
}
