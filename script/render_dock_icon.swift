import AppKit
import Foundation
import UniformTypeIdentifiers

struct Options {
    var sourcePath: String
    var outputPath: String
    var canvas: Int = 1024
    var glyphScale: Double = 0.72
    var whiteThreshold: UInt8 = 205
    var background = (red: 0.169, green: 0.424, blue: 0.722)
}

func loadPixels(from url: URL) -> (width: Int, height: Int, rgba: [UInt8])? {
    guard let image = NSImage(contentsOf: url),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return nil }

    let width = cgImage.width
    let height = cgImage.height
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &rgba,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (width, height, rgba)
}

func isGlyphPixel(r: UInt8, g: UInt8, b: UInt8, a: UInt8, threshold: UInt8) -> Bool {
    guard a > 12 else { return false }
    let minChannel = min(r, g, b)
    let maxChannel = max(r, g, b)
    return minChannel >= threshold && (maxChannel - minChannel) <= 48
}

func renderIcon(options: Options) throws {
    let sourceURL = URL(fileURLWithPath: options.sourcePath)
    guard let source = loadPixels(from: sourceURL) else {
        throw NSError(domain: "render_dock_icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read \(options.sourcePath)"])
    }

    let canvas = options.canvas
    var output = [UInt8](repeating: 0, count: canvas * canvas * 4)
    let bgR = UInt8((options.background.red * 255).rounded())
    let bgG = UInt8((options.background.green * 255).rounded())
    let bgB = UInt8((options.background.blue * 255).rounded())

    for index in stride(from: 0, to: output.count, by: 4) {
        output[index] = bgR
        output[index + 1] = bgG
        output[index + 2] = bgB
        output[index + 3] = 255
    }

    let target = Double(canvas) * options.glyphScale
    let scale = min(target / Double(source.width), target / Double(source.height))
    let drawWidth = Double(source.width) * scale
    let drawHeight = Double(source.height) * scale
    let offsetX = (Double(canvas) - drawWidth) / 2
    let offsetY = (Double(canvas) - drawHeight) / 2

    for y in 0 ..< canvas {
        for x in 0 ..< canvas {
            let srcX = (Double(x) - offsetX) / scale
            let srcY = (Double(y) - offsetY) / scale
            guard srcX >= 0, srcY >= 0,
                  srcX < Double(source.width - 1),
                  srcY < Double(source.height - 1)
            else { continue }

            let x0 = Int(srcX)
            let y0 = Int(srcY)
            let x1 = min(x0 + 1, source.width - 1)
            let y1 = min(y0 + 1, source.height - 1)
            let tx = srcX - Double(x0)
            let ty = srcY - Double(y0)

            func sample(_ sx: Int, _ sy: Int) -> (UInt8, UInt8, UInt8, UInt8) {
                let index = (sy * source.width + sx) * 4
                return (
                    source.rgba[index],
                    source.rgba[index + 1],
                    source.rgba[index + 2],
                    source.rgba[index + 3]
                )
            }

            let c00 = sample(x0, y0)
            let c10 = sample(x1, y0)
            let c01 = sample(x0, y1)
            let c11 = sample(x1, y1)

            let channels: [UInt8] = (0 ..< 4).map { channel in
                let v00 = Double([c00.0, c00.1, c00.2, c00.3][channel])
                let v10 = Double([c10.0, c10.1, c10.2, c10.3][channel])
                let v01 = Double([c01.0, c01.1, c01.2, c01.3][channel])
                let v11 = Double([c11.0, c11.1, c11.2, c11.3][channel])
                let top = v00 + (v10 - v00) * tx
                let bottom = v01 + (v11 - v01) * tx
                return UInt8(max(0, min(255, (top + (bottom - top) * ty).rounded())))
            }

            let alpha = channels[3]
            guard alpha > 12 else { continue }
            guard isGlyphPixel(
                r: channels[0],
                g: channels[1],
                b: channels[2],
                a: alpha,
                threshold: options.whiteThreshold
            ) else { continue }

            let coverage = Double(alpha) / 255
            let outIndex = (y * canvas + x) * 4
            output[outIndex] = UInt8((Double(channels[0]) * coverage + Double(bgR) * (1 - coverage)).rounded())
            output[outIndex + 1] = UInt8((Double(channels[1]) * coverage + Double(bgG) * (1 - coverage)).rounded())
            output[outIndex + 2] = UInt8((Double(channels[2]) * coverage + Double(bgB) * (1 - coverage)).rounded())
            output[outIndex + 3] = 255
        }
    }

    guard let context = CGContext(
        data: &output,
        width: canvas,
        height: canvas,
        bitsPerComponent: 8,
        bytesPerRow: canvas * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ),
        let cgImage = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: options.outputPath) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        throw NSError(domain: "render_dock_icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not write \(options.outputPath)"])
    }

    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "render_dock_icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "PNG finalize failed"])
    }
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("Usage: render_dock_icon <source.png> <output.png> [glyphScale]\n", stderr)
    exit(64)
}

var options = Options(sourcePath: args[1], outputPath: args[2])
if args.count >= 4, let scale = Double(args[3]) {
    options.glyphScale = scale
}

do {
    try renderIcon(options: options)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
