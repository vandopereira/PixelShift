import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ProcessingRecipe: Sendable {
    let resize: ResizeSettings?
    let rotation: RotationSettings?
}

enum ResizeSettings: Sendable {
    case dimensions(width: Int, height: Int)
    case percentage(value: Double)
}

enum RotationSettings: Sendable {
    case degrees(Double)
}

enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg
    case heic
    case tiff
    case bmp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .bmp: return "BMP"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .tiff: return "tiff"
        case .bmp: return "bmp"
        }
    }

    var typeIdentifier: CFString {
        switch self {
        case .png: return UTType.png.identifier as CFString
        case .jpeg: return UTType.jpeg.identifier as CFString
        case .heic: return UTType.heic.identifier as CFString
        case .tiff: return UTType.tiff.identifier as CFString
        case .bmp: return UTType.bmp.identifier as CFString
        }
    }
}

enum ResizeMode: String, CaseIterable, Identifiable, Sendable {
    case dimensions
    case percentage

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dimensions: return "Largura x Altura"
        case .percentage: return "Percentual"
        }
    }
}

enum RotationMode: String, CaseIterable, Identifiable, Sendable {
    case left90
    case right90
    case custom

    var id: String { rawValue }
}

struct ImageFile: Identifiable, Equatable, Sendable {
    let id = UUID()
    let url: URL
    let pixelSize: CGSize

    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        self.url = url
        self.pixelSize = CGSize(width: image.width, height: image.height)
    }

    var dimensionsDescription: String {
        "\(Int(pixelSize.width)) x \(Int(pixelSize.height)) px"
    }
}

enum ImageProcessorError: LocalizedError {
    case failedToLoad(URL)
    case failedToRender
    case failedToCreateDestination(URL)
    case failedToFinalize(URL)

    var errorDescription: String? {
        switch self {
        case .failedToLoad(let url):
            return "Falha ao carregar \(url.lastPathComponent)."
        case .failedToRender:
            return "Falha ao renderizar a imagem processada."
        case .failedToCreateDestination(let url):
            return "Falha ao criar o arquivo de saída em \(url.lastPathComponent)."
        case .failedToFinalize(let url):
            return "Falha ao finalizar a exportação em \(url.lastPathComponent)."
        }
    }
}

final class ImageProcessor: @unchecked Sendable {
    func preview(for url: URL, recipe: ProcessingRecipe) -> NSImage? {
        guard let image = loadImage(from: url),
              let rendered = render(image: image, recipe: recipe) else {
            return nil
        }

        return NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
    }

    func export(
        images: [ImageFile],
        to folder: URL,
        recipe: ProcessingRecipe,
        format: OutputFormat,
        onProgress: ((Int, Int) -> Void)? = nil
    ) -> Result<Int, Error> {
        do {
            var exported = 0
            let total = images.count

            for item in images {
                guard let image = loadImage(from: item.url) else {
                    throw ImageProcessorError.failedToLoad(item.url)
                }

                guard let rendered = render(image: image, recipe: recipe) else {
                    throw ImageProcessorError.failedToRender
                }

                let baseName = item.url.deletingPathExtension().lastPathComponent
                let destination = folder.appending(path: "\(baseName)_converted.\(format.fileExtension)")
                try write(image: rendered, to: destination, format: format)
                exported += 1
                onProgress?(exported, total)
            }

            return .success(exported)
        } catch {
            return .failure(error)
        }
    }

    private func loadImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        return CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: true
        ] as CFDictionary)
    }

    private func render(image: CGImage, recipe: ProcessingRecipe) -> CGImage? {
        let baseSize = CGSize(width: image.width, height: image.height)
        let resizedSize = resolveResizedSize(from: baseSize, resize: recipe.resize)
        let rotationDegrees = resolveRotationDegrees(recipe.rotation)
        let canvasSize = resolveCanvasSize(for: resizedSize, rotationDegrees: rotationDegrees)

        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: max(Int(canvasSize.width.rounded()), 1),
                height: max(Int(canvasSize.height.rounded()), 1),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(origin: .zero, size: canvasSize))

        context.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)
        context.rotate(by: rotationDegrees * .pi / 180)
        context.scaleBy(x: 1, y: -1)

        let drawRect = CGRect(
            x: -resizedSize.width / 2,
            y: -resizedSize.height / 2,
            width: resizedSize.width,
            height: resizedSize.height
        )
        context.draw(image, in: drawRect)

        return context.makeImage()
    }

    private func resolveResizedSize(from original: CGSize, resize: ResizeSettings?) -> CGSize {
        guard let resize else { return original }

        switch resize {
        case .dimensions(let width, let height):
            let safeWidth = max(CGFloat(width), 1)
            let safeHeight = max(CGFloat(height), 1)
            return CGSize(width: safeWidth, height: safeHeight)
        case .percentage(let value):
            let factor = max(CGFloat(value) / 100, 0.01)
            return CGSize(width: original.width * factor, height: original.height * factor)
        }
    }

    private func resolveRotationDegrees(_ rotation: RotationSettings?) -> CGFloat {
        guard let rotation else { return 0 }

        switch rotation {
        case .degrees(let value):
            return CGFloat(value)
        }
    }

    private func resolveCanvasSize(for size: CGSize, rotationDegrees: CGFloat) -> CGSize {
        let radians = rotationDegrees * .pi / 180
        let transform = CGAffineTransform(rotationAngle: radians)
        let rect = CGRect(origin: CGPoint(x: -size.width / 2, y: -size.height / 2), size: size)
        let rotated = rect.applying(transform)
        return CGSize(width: abs(rotated.width), height: abs(rotated.height))
    }

    private func write(image: CGImage, to url: URL, format: OutputFormat) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.typeIdentifier, 1, nil) else {
            throw ImageProcessorError.failedToCreateDestination(url)
        }

        let properties: CFDictionary = [
            kCGImageDestinationLossyCompressionQuality: 0.9
        ] as CFDictionary

        CGImageDestinationAddImage(destination, image, properties)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessorError.failedToFinalize(url)
        }
    }
}
