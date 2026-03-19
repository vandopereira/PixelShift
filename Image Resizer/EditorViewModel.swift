import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var images: [ImageFile] = []
    @Published var selectedImageID: UUID?
    @Published var outputFolder: URL?
    @Published var outputFormat: OutputFormat = .png
    @Published var resizeEnabled = false
    @Published var resizeMode: ResizeMode = .dimensions
    @Published var targetWidth = "1920"
    @Published var targetHeight = "1080"
    @Published var scalePercent = "100"
    @Published var rotationEnabled = false
    @Published var rotationMode: RotationMode = .custom
    @Published var rotationAngle: Double = 0
    @Published var originalPreview: NSImage?
    @Published var processedPreview: NSImage?
    @Published var statusMessage: String?
    @Published var statusIsError = false
    @Published var isExporting = false
    @Published var exportCompletedCount = 0
    @Published var exportTotalCount = 0
    @Published var isRenderingPreview = false
    @Published var lastExportedFolder: URL?

    private let processor = ImageProcessor()
    private var previewTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?

    var canExport: Bool {
        !images.isEmpty && outputFolder != nil && !isExporting
    }

    var exportProgress: Double {
        guard exportTotalCount > 0 else { return 0 }
        return Double(exportCompletedCount) / Double(exportTotalCount)
    }

    init() {
        bindPreviewUpdates()
    }

    func pickImages() {
        appendImages()
    }

    func replaceImages() {
        cancelPreviewTask()
        images.removeAll()
        selectedImageID = nil
        originalPreview = nil
        processedPreview = nil
        appendImages()
    }

    func removeSelectedImage() {
        guard let selectedImage else { return }

        images.removeAll { $0.id == selectedImage.id }
        selectedImageID = images.first?.id
        schedulePreviewRefresh(immediate: true)
        updateStatus("Imagem removida da lista.")
    }

    func clearImages() {
        cancelPreviewTask()
        images.removeAll()
        selectedImageID = nil
        originalPreview = nil
        processedPreview = nil
        updateStatus("Lista de imagens limpa.")
    }

    private func appendImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }

        let newItems = panel.urls.compactMap(ImageFile.init(url:))
        let addedItems = newItems.filter { newItem in
            !images.contains(where: { $0.url == newItem.url })
        }
        images.append(contentsOf: addedItems)

        if selectedImage == nil {
            selectedImageID = images.first?.id
        }

        schedulePreviewRefresh(immediate: true)
        updateStatus("Carregadas \(addedItems.count) imagem(ns).")
    }

    func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK else { return }
        outputFolder = panel.url
        updateStatus("Pasta de saída definida.")
    }

    func exportImages() {
        guard let outputFolder else {
            updateStatus("Escolha uma pasta de saída antes de exportar.", isError: true)
            return
        }

        guard !isExporting else { return }

        let images = self.images
        let recipe = buildRecipe()
        let format = outputFormat

        isExporting = true
        lastExportedFolder = nil
        exportCompletedCount = 0
        exportTotalCount = images.count
        updateStatus("Exportando 0 de \(images.count) imagem(ns)...")

        exportTask?.cancel()
        exportTask = Task.detached(priority: .userInitiated) { [processor] in
            let result = processor.export(images: images, to: outputFolder, recipe: recipe, format: format) { completed, total in
                Task { @MainActor in
                    self.exportCompletedCount = completed
                    self.exportTotalCount = total
                    self.updateStatus("Exportando \(completed) de \(total) imagem(ns)...")
                }
            }

            await MainActor.run {
                self.isExporting = false

                switch result {
                case .success(let exported):
                    self.exportCompletedCount = exported
                    self.exportTotalCount = images.count
                    self.lastExportedFolder = outputFolder
                    self.updateStatus("Exportadas \(exported) de \(images.count) imagem(ns) para \(outputFolder.path(percentEncoded: false)).")
                case .failure(let error):
                    self.lastExportedFolder = nil
                    self.updateStatus(error.localizedDescription, isError: true)
                }
            }
        }
    }

    func openLastExportedFolder() {
        guard let lastExportedFolder else { return }
        NSWorkspace.shared.open(lastExportedFolder)
    }

    private var selectedImage: ImageFile? {
        guard let selectedImageID else { return images.first }
        return images.first(where: { $0.id == selectedImageID }) ?? images.first
    }

    private func bindPreviewUpdates() {
        $selectedImageID
            .sink { [weak self] _ in
                self?.schedulePreviewRefresh(immediate: true)
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            $outputFormat.map { _ in () }.eraseToAnyPublisher(),
            $resizeEnabled.map { _ in () }.eraseToAnyPublisher(),
            $resizeMode.map { _ in () }.eraseToAnyPublisher(),
            $targetWidth.map { _ in () }.eraseToAnyPublisher(),
            $targetHeight.map { _ in () }.eraseToAnyPublisher(),
            $scalePercent.map { _ in () }.eraseToAnyPublisher(),
            $rotationEnabled.map { _ in () }.eraseToAnyPublisher(),
            $rotationMode.map { _ in () }.eraseToAnyPublisher(),
            $rotationAngle.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] _ in
            self?.schedulePreviewRefresh(immediate: false)
        }
        .store(in: &cancellables)
    }

    private var cancellables: Set<AnyCancellable> = []

    private func schedulePreviewRefresh(immediate: Bool) {
        previewTask?.cancel()

        guard let selectedImage else {
            originalPreview = nil
            processedPreview = nil
            isRenderingPreview = false
            return
        }

        originalPreview = NSImage(contentsOf: selectedImage.url)
        let recipe = buildRecipe()
        isRenderingPreview = true

        previewTask = Task.detached(priority: .utility) { [processor] in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(180))
            }

            guard !Task.isCancelled else { return }
            let preview = processor.preview(for: selectedImage.url, recipe: recipe)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.processedPreview = preview
                self.isRenderingPreview = false
            }
        }
    }

    private func refreshPreviews() {
        guard let selectedImage else {
            originalPreview = nil
            processedPreview = nil
            return
        }

        originalPreview = NSImage(contentsOf: selectedImage.url)

        let recipe = buildRecipe()
        processedPreview = processor.preview(for: selectedImage.url, recipe: recipe)
    }

    private func cancelPreviewTask() {
        previewTask?.cancel()
        isRenderingPreview = false
    }

    private func buildRecipe() -> ProcessingRecipe {
        let resize: ResizeSettings?
        if resizeEnabled {
            switch resizeMode {
            case .dimensions:
                resize = .dimensions(
                    width: Int(targetWidth) ?? 0,
                    height: Int(targetHeight) ?? 0
                )
            case .percentage:
                resize = .percentage(value: Double(scalePercent) ?? 100)
            }
        } else {
            resize = nil
        }

        let rotation: RotationSettings?
        if rotationEnabled {
            switch rotationMode {
            case .left90:
                rotation = .degrees(-90)
            case .right90:
                rotation = .degrees(90)
            case .custom:
                rotation = .degrees(rotationAngle)
            }
        } else {
            rotation = nil
        }

        return ProcessingRecipe(resize: resize, rotation: rotation)
    }

    private func updateStatus(_ message: String, isError: Bool = false) {
        statusMessage = message
        statusIsError = isError
    }
}
