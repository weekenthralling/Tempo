//
//  TimeSignatureSheet.swift
//  Tempo
//

import SwiftUI

struct TimeSignatureSheet: View {
    @Environment(MetronomeEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var theme: TempoTheme { TempoTheme(scheme: colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    commonMeters
                    customMeter
                }
                .padding(20)
            }
            .background(TempoBackground(theme: theme))
            .navigationTitle(Text("Time signature"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .tint(theme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var commonMeters: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Common meters")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 84), spacing: 10)],
                spacing: 10
            ) {
                ForEach(TimeSignature.presets) { preset in
                    presetChip(preset)
                }
            }
        }
    }

    private var customMeter: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Custom")

            Stepper(
                value: Binding(
                    get: { engine.timeSignature.beats },
                    set: { engine.timeSignature = TimeSignature(beats: $0, noteValue: engine.timeSignature.noteValue) }
                ),
                in: TimeSignature.validBeats
            ) {
                HStack {
                    Text(verbatim: localizedInteger("Beats per bar: %lld", engine.timeSignature.beats))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                }
            }
            .tint(theme.accent)

            VStack(alignment: .leading, spacing: 8) {
                Text("Note value")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)

                Picker(
                    "Note value",
                    selection: Binding(
                        get: { engine.timeSignature.noteValue },
                        set: { engine.timeSignature = TimeSignature(beats: engine.timeSignature.beats, noteValue: $0) }
                    )
                ) {
                    ForEach(TimeSignature.allowedNoteValues, id: \.self) { value in
                        Text("1/\(value)").tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text("6/8, 9/8 and 12/8 are compound meters — Tempo accents the first note of each group.")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func presetChip(_ preset: TimeSignature) -> some View {
        let selected = preset == engine.timeSignature

        return Button {
            engine.timeSignature = preset
            Haptics.selectionChanged()
        } label: {
            VStack(spacing: 3) {
                Text(preset.displayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Group {
                    if preset.isCompound {
                        Text("Compound")
                    } else if preset.beats == 4 {
                        Text("Common")
                    } else {
                        Text(verbatim: " ")
                    }
                }
                .font(.system(size: 9, weight: .semibold))
                .opacity(preset.isCompound || preset.beats == 4 ? 0.7 : 0)
            }
            .foregroundStyle(selected ? theme.onAccent : theme.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? theme.accent : theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(theme.surfaceStroke, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(preset.displayName))
        .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(theme.secondaryText)
    }
}

#Preview {
    TimeSignatureSheet()
        .environment(MetronomeEngine())
}
