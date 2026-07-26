import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let addFiles: ([URL]) -> Void
    @State private var isTargeted = false
    @State private var isImporterPresented = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            VStack(spacing: 4) {
                Text("Drop a video, audio, photo, or document")
                    .font(.headline)
                Text("Batch conversion is supported for compatible files")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button("Choose Files…") { isImporterPresented = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(isTargeted ? Color.accentColor : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [8]))
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                    else if let value = item as? URL { url = value }
                    else { url = nil }
                    if let url { DispatchQueue.main.async { addFiles([url]) } }
                }
            }
            return true
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { addFiles(urls) }
        }
    }
}
