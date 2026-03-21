import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel, isDropTargeted: $isDropTargeted)
        } detail: {
            ZStack {
                VStack(spacing: 0) {
                    header
                    Divider()
                    HSplitView {
                        PreviewPaneView(title: "Original", image: viewModel.originalPreview)
                        PreviewPaneView(title: "Preview", image: viewModel.processedPreview)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    ScrollView {
                        InspectorView(viewModel: viewModel)
                            .padding(20)
                    }
                }

                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                        )
                        .padding(20)
                        .overlay(
                            VStack(spacing: 10) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 40))
                                Text("Larga imagens aqui")
                                    .font(.headline)
                            }
                            .foregroundStyle(Color.accentColor)
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            viewModel.handleDroppedProviders(providers, replacing: false)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PixelShift")
                    .font(.system(size: 28, weight: .bold))
                Text("Conversão, resize, inversão e rotação local para macOS")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                headerActions
            }
        }
        .padding(20)
    }

    private var headerActions: some View {
        Group {
            Button("Adicionar Imagens") {
                viewModel.pickImages()
            }
            .keyboardShortcut("o")

            Button("Nova Seleção") {
                viewModel.replaceImages()
            }

            Button("Limpar Lista") {
                viewModel.clearImages()
            }
            .disabled(viewModel.images.isEmpty)

            Button("Escolher Pasta de Saída") {
                viewModel.pickOutputFolder()
            }

            Button("Exportar") {
                viewModel.exportImages()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canExport)
        }
    }

private struct PreviewPaneView: View {
    let title: String
    let image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )

            VStack(spacing: 16) {
                Text(title)
                    .font(.headline)

                if let image {
                    GeometryReader { proxy in
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .padding(20)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                        Text("Nenhuma imagem selecionada")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .padding(20)
        .drawingGroup()
    }
}
}

private struct SidebarView: View {
    @ObservedObject var viewModel: EditorViewModel
    @Binding var isDropTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Arquivos")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    viewModel.pickImages()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)

                Button {
                    viewModel.removeSelectedImage()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.images.isEmpty)
            }

            if viewModel.images.isEmpty {
                ContentUnavailableView(
                    "Sem imagens",
                    systemImage: "photo.stack",
                    description: Text("Adicione ou arraste uma ou mais imagens para começar.")
                )
            } else {
                List(selection: $viewModel.selectedImageID) {
                    ForEach(viewModel.images) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.url.lastPathComponent)
                                .lineLimit(1)
                            Text(item.dimensionsDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(item.id)
                    }
                }
            }

            if let outputFolder = viewModel.outputFolder {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saída")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(outputFolder.path(percentEncoded: false))
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }

            if !viewModel.images.isEmpty {
                Button("Limpar Todas") {
                    viewModel.clearImages()
                }
            }
        }
        .padding(16)
        .background(isDropTargeted ? Color.accentColor.opacity(0.06) : .clear)
    }
}

private struct InspectorView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Replaced heavy ViewThatFits with a simpler VStack/HStack approach
            // On macOS inspectors, a single column is usually more stable and predictable.
            VStack(alignment: .leading, spacing: 24) {
                FormatSectionView(outputFormat: $viewModel.outputFormat)
                Divider()
                ResizeSectionView(
                    enabled: $viewModel.resizeEnabled,
                    mode: $viewModel.resizeMode,
                    width: $viewModel.targetWidth,
                    height: $viewModel.targetHeight,
                    percent: $viewModel.scalePercent
                )
                Divider()
                TransformSectionView(viewModel: viewModel)
            }

            StatusSectionView(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FormatSectionView: View {
    @Binding var outputFormat: OutputFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Formato")
                .font(.headline)

            Picker("Converter para", selection: $outputFormat) {
                ForEach(OutputFormat.allCases) { format in
                    Text(format.label).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
        }
    }
}

private struct ResizeSectionView: View {
    @Binding var enabled: Bool
    @Binding var mode: ResizeMode
    @Binding var width: String
    @Binding var height: String
    @Binding var percent: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Resize")
                .font(.headline)

            Toggle("Aplicar resize", isOn: $enabled)

            Picker("Modo", selection: $mode) {
                ForEach(ResizeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .disabled(!enabled)

            if mode == .dimensions {
                HStack {
                    LabeledField(title: "Largura", value: $width)
                    LabeledField(title: "Altura", value: $height)
                }
            } else {
                LabeledField(title: "Percentual", value: $percent)
                    .frame(maxWidth: 180)
            }
        }
        .disabled(!enabled)
    }
}

private struct TransformSectionView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Transformações")
                    .font(.headline)
                Spacer()
                Button("Resetar") {
                    viewModel.resetTransformations()
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Aplicar rotação", isOn: $viewModel.rotationEnabled)
                
                HStack(spacing: 8) {
                    Button("90° Esq.") {
                        viewModel.rotationMode = .left90
                        viewModel.rotationAngle = -90
                    }
                    Button("90° Dir.") {
                        viewModel.rotationMode = .right90
                        viewModel.rotationAngle = 90
                    }
                    Button("Ângulo") {
                        viewModel.rotationMode = .custom
                    }
                }
                .disabled(!viewModel.rotationEnabled)

                HStack {
                    Text("Ângulo")
                        .font(.caption)
                    Slider(value: $viewModel.rotationAngle, in: -180...180, step: 1)
                        .frame(maxWidth: 220)
                    Text("\(Int(viewModel.rotationAngle))°")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                .disabled(!viewModel.rotationEnabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Espelhar horizontalmente", isOn: $viewModel.flipHorizontal)
                Toggle("Espelhar verticalmente", isOn: $viewModel.flipVertical)
            }
        }
    }
}

private struct StatusSectionView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = viewModel.statusMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .foregroundStyle(viewModel.statusIsError ? .red : .secondary)
                        .textSelection(.enabled)

                    if !viewModel.isExporting, let folder = viewModel.lastExportedFolder {
                        Button("Abrir pasta exportada") {
                            viewModel.openLastExportedFolder()
                        }
                    }
                }
            }

            if viewModel.isExporting {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: viewModel.exportProgress)
                    Text("Total: \(viewModel.exportCompletedCount) / \(viewModel.exportTotalCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isRenderingPreview {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Atualizando preview...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct LabeledField: View {
    let title: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: $value)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
