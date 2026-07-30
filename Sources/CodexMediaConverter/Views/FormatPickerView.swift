import SwiftUI

struct FormatPickerView: View {
    @Binding var workflow: ConversionWorkflow
    @Binding var targetKind: MediaKind
    @Binding var outputFormat: OutputFormat
    @Binding var speedMultiplier: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Workflow", selection: $workflow) {
                ForEach(ConversionWorkflow.allCases) { option in
                    Label(option.rawValue, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if workflow == .formatConversion {
                Text("Convert to")
                    .font(.headline)
                Picker("Media type", selection: $targetKind) {
                    ForEach(MediaKind.allCases, id: \.self) { kind in
                        Label(kind.rawValue, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Picker("Format", selection: $outputFormat) {
                        ForEach(OutputFormat.formats(for: targetKind)) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .frame(width: 180)
                    Text(outputFormat.summary)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if targetKind == .audio {
                    Label(
                        "Movie inputs extract their first audio track; the video stream is removed.",
                        systemImage: "waveform.badge.minus"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if targetKind == .video {
                    Label(
                        "Audio inputs become 1280×720 neon visualizer movies with the original audio.",
                        systemImage: "waveform.path.ecg.rectangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                speedControls
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var speedControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tutorial speed")
                    .font(.headline)
                Spacer()
                Text(speedMultiplier.formatted(.number.precision(.fractionLength(0...2))) + "×")
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(Color.accentColor)
                    .frame(minWidth: 58, alignment: .trailing)
            }
            Slider(value: $speedMultiplier, in: 1.25...10, step: 0.25) {
                Text("Speed")
            } minimumValueLabel: {
                Text("1.25×")
                    .font(.caption)
            } maximumValueLabel: {
                Text("10×")
                    .font(.caption)
            }
            Label("Exports MP4 video only. All audio is permanently removed.", systemImage: "speaker.slash.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
