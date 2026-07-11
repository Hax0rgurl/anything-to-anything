import SwiftUI

struct QueueView: View {
    @ObservedObject var store: ConversionStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.headline)
                Text("\(store.items.count)")
                    .foregroundStyle(.secondary)
                Spacer()
                if store.items.contains(where: { if case .finished = $0.state { true } else { false } }) {
                    Button("Clear Finished") { store.clearFinished() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            if store.items.isEmpty {
                Text("Files you add will appear here")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.items) { item in
                            QueueRow(item: item, remove: { store.remove(item.id) }, reveal: store.reveal)
                        }
                    }
                }
                .frame(maxHeight: 230)
            }
        }
    }
}

private struct QueueRow: View {
    let item: ConversionItem
    let remove: () -> Void
    let reveal: (URL) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.sourceKind?.symbol ?? "questionmark.square.dashed")
                .font(.title2)
                .foregroundStyle(item.sourceKind == nil ? Color.orange : Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.sourceURL.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Text(item.sourceKind?.rawValue ?? "Unsupported")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.state == .converting {
                    ProgressView(value: item.progress)
                } else {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                }
            }
            if case .finished(let url) = item.state {
                Button { reveal(url) } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain)
                    .help("Show converted file")
            } else if item.state != .converting {
                Button(action: remove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusText: String {
        switch item.state {
        case .failed(let error): error
        default: item.state.label
        }
    }

    private var statusColor: Color {
        switch item.state {
        case .failed: .red
        case .finished: .green
        default: .secondary
        }
    }
}
