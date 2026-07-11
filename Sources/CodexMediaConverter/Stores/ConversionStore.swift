import AppKit
import Foundation

@MainActor
final class ConversionStore: ObservableObject {
    @Published var items: [ConversionItem] = []
    @Published var workflow: ConversionWorkflow = .formatConversion
    @Published var targetKind: MediaKind = .video {
        didSet {
            if outputFormat.kind != targetKind {
                outputFormat = OutputFormat.formats(for: targetKind)[0]
            }
        }
    }
    @Published var outputFormat: OutputFormat = .mp4
    @Published var speedMultiplier: Double = 2
    @Published var isConverting = false
    @Published var statusMessage = "Drop media here or choose files"
    @Published var outputDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies/Anything to Anything", isDirectory: true)

    private let service = ConversionService()
    private var conversionTask: Task<Void, Never>?

    var validItemCount: Int {
        switch workflow {
        case .formatConversion: items.filter { $0.sourceKind != nil }.count
        case .speedUp: items.filter { $0.sourceKind == .video }.count
        }
    }

    var primaryActionTitle: String {
        if isConverting { return workflow == .speedUp ? "Speeding Up…" : "Converting…" }
        let noun = validItemCount == 1 ? "File" : "Files"
        if workflow == .speedUp {
            return "Speed Up \(validItemCount) \(noun)"
        }
        return "Convert \(validItemCount) \(noun)"
    }

    func add(urls: [URL]) {
        let existing = Set(items.map(\.sourceURL))
        let newItems = urls
            .filter { !existing.contains($0) && !$0.hasDirectoryPath }
            .map { ConversionItem(sourceURL: $0) }
        items.append(contentsOf: newItems)
        statusMessage = items.isEmpty ? "Drop media here or choose files" : "\(items.count) file\(items.count == 1 ? "" : "s") ready"
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func clearFinished() {
        items.removeAll {
            if case .finished = $0.state { return true }
            return false
        }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputDirectory
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
        }
    }

    func startConversion() {
        guard !isConverting, validItemCount > 0 else { return }
        isConverting = true
        statusMessage = workflow == .speedUp ? "Speeding up and removing audio…" : "Converting…"
        let selectedWorkflow = workflow
        let format: OutputFormat = selectedWorkflow == .speedUp ? .mp4 : outputFormat
        let selectedSpeed = speedMultiplier
        let destination = outputDirectory

        conversionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            } catch {
                self.statusMessage = "Could not create output folder: \(error.localizedDescription)"
                self.isConverting = false
                return
            }

            for index in self.items.indices where self.isValidForSelectedWorkflow(self.items[index], workflow: selectedWorkflow) {
                if Task.isCancelled { break }
                self.items[index].state = .converting
                self.items[index].progress = 0
                let source = self.items[index].sourceURL
                let label = selectedWorkflow == .speedUp ? " \(self.speedLabel(selectedSpeed))" : ""
                let output = self.uniqueOutputURL(for: source, format: format, directory: destination, label: label)
                let request = ConversionRequest(
                    sourceURL: source,
                    outputURL: output,
                    outputFormat: format,
                    speedMultiplier: selectedWorkflow == .speedUp ? selectedSpeed : nil
                )
                do {
                    try await self.service.convert(request) { value in
                        Task { @MainActor [weak self] in
                            guard let self, self.items.indices.contains(index) else { return }
                            self.items[index].progress = value
                        }
                    }
                    self.items[index].progress = 1
                    self.items[index].state = .finished(output)
                } catch {
                    self.items[index].state = .failed(error.localizedDescription)
                }
            }
            self.isConverting = false
            let completed = self.items.filter { if case .finished = $0.state { true } else { false } }.count
            self.statusMessage = "Finished \(completed) conversion\(completed == 1 ? "" : "s")"
        }
    }

    func cancel() {
        conversionTask?.cancel()
        Task { await service.cancel() }
        isConverting = false
        statusMessage = "Cancelled"
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealOutputFolder() {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(outputDirectory)
    }

    private func isValidForSelectedWorkflow(_ item: ConversionItem, workflow: ConversionWorkflow) -> Bool {
        switch workflow {
        case .formatConversion: item.sourceKind != nil
        case .speedUp: item.sourceKind == .video
        }
    }

    private func speedLabel(_ speed: Double) -> String {
        speed.formatted(.number.precision(.fractionLength(0...2))) + "x"
    }

    private func uniqueOutputURL(for source: URL, format: OutputFormat, directory: URL, label: String = "") -> URL {
        let base = source.deletingPathExtension().lastPathComponent + label
        var candidate = directory.appendingPathComponent("\(base).\(format.fileExtension)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(suffix).\(format.fileExtension)")
            suffix += 1
        }
        return candidate
    }
}
