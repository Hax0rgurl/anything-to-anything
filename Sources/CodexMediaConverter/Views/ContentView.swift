import SwiftUI

struct ContentView: View {
    @StateObject private var store = ConversionStore()

    var body: some View {
        VStack(spacing: 18) {
            header
            DropZoneView(addFiles: store.add)
            FormatPickerView(
                workflow: $store.workflow,
                targetKind: $store.targetKind,
                outputFormat: $store.outputFormat,
                speedMultiplier: $store.speedMultiplier
            )
            QueueView(store: store)
            footer
        }
        .padding(24)
        .frame(minWidth: 650, minHeight: 700)
        .onOpenURL { store.add(urls: [$0]) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Anything to Anything")
                    .font(.title2.bold())
                Text("Video, audio, and photo — in any direction")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.revealOutputFolder() } label: {
                Label("Conversions", systemImage: "folder")
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save to")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.outputDirectory.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Change…") { store.chooseOutputDirectory() }
            }
            Divider()
            HStack {
                Text(store.statusMessage)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isConverting {
                    Button("Cancel", role: .destructive) { store.cancel() }
                }
                Button(store.primaryActionTitle) {
                    store.startConversion()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(store.isConverting || store.validItemCount == 0)
            }
        }
    }
}
