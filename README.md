# PixelShift

PixelShift is a native macOS desktop app for converting, resizing, rotating, and batch-exporting images locally with a fast SwiftUI interface.

## Features

- Convert images between `PNG`, `JPEG`, `HEIC`, `TIFF`, and `BMP`
- Resize by width/height or percentage
- Rotate `90°` left/right or by a custom angle
- Export one or many images to a chosen output folder

## Open In Xcode

1. Abra [`Image Resizer.xcodeproj`](/Users/vando/Dev/Image%20Resizer/Image%20Resizer.xcodeproj/project.pbxproj) no Xcode.
2. Se o Xcode pedir, aceite a licença do toolchain.
3. Rode o target `Image Resizer`.

## Notes

- Built with native macOS APIs: `SwiftUI`, `AppKit`, `CoreGraphics`, and `ImageIO`
- All processing is local, with no uploads
