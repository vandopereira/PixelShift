import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                HSplitView {
                    previewPane(title: "Original", image: viewModel.originalPreview)
                    previewPane(title: "Preview", image: viewModel.processedPreview)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                ScrollView {
                    InspectorView(viewModel: viewModel)
                        .padding(20)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Image Resizer")
                    .font(.system(size: 28, weight: .bold))
                Text("Conversão, resize e rotação local para macOS")
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    headerActions
                }

                VStack(alignment: .leading, spacing: 10) {
                    headerActions
                }
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

    @ViewBuilder
    private func previewPane(title: String, image: NSImage?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
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
    }
}

private struct SidebarView: View {
    @ObservedObject var viewModel: EditorViewModel

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
                    description: Text("Adicione uma ou mais imagens para começar.")
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
    }
}

private struct InspectorView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    formatSection
                    resizeSection
                    rotationSection
                }

                VStack(alignment: .leading, spacing: 18) {
                    formatSection
                    resizeSection
                    rotationSection
                }
            }

            if let message = viewModel.statusMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .foregroundStyle(viewModel.statusIsError ? .red : .secondary)
                        .textSelection(.enabled)

                    if !viewModel.isExporting, let folder = viewModel.lastExportedFolder {
                        Button("Abrir pasta exportada") {
                            viewModel.openLastExportedFolder()
                        }
                        .help(folder.path(percentEncoded: false))
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Formato")
                .font(.headline)

            Picker("Converter para", selection: $viewModel.outputFormat) {
                ForEach(OutputFormat.allCases) { format in
                    Text(format.label).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Resize")
                .font(.headline)

            Toggle("Aplicar resize", isOn: $viewModel.resizeEnabled)

            Picker("Modo", selection: $viewModel.resizeMode) {
                ForEach(ResizeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .disabled(!viewModel.resizeEnabled)

            if viewModel.resizeMode == .dimensions {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        LabeledField(title: "Largura", value: $viewModel.targetWidth)
                        LabeledField(title: "Altura", value: $viewModel.targetHeight)
                    }

                    VStack(alignment: .leading) {
                        LabeledField(title: "Largura", value: $viewModel.targetWidth)
                        LabeledField(title: "Altura", value: $viewModel.targetHeight)
                    }
                }
            } else {
                LabeledField(title: "Percentual", value: $viewModel.scalePercent)
                    .frame(maxWidth: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rotationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rotação")
                .font(.headline)

            Toggle("Aplicar rotação", isOn: $viewModel.rotationEnabled)

            ViewThatFits(in: .horizontal) {
                HStack {
                    rotationButtons
                }

                VStack(alignment: .leading) {
                    rotationButtons
                }
            }
            .disabled(!viewModel.rotationEnabled)

            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Ângulo")
                    Slider(value: $viewModel.rotationAngle, in: -180...180, step: 1)
                        .frame(maxWidth: 220)
                        .disabled(!viewModel.rotationEnabled)
                    Text("\(Int(viewModel.rotationAngle))°")
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ângulo")
                    Slider(value: $viewModel.rotationAngle, in: -180...180, step: 1)
                        .disabled(!viewModel.rotationEnabled)
                    Text("\(Int(viewModel.rotationAngle))°")
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rotationButtons: some View {
        Group {
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
