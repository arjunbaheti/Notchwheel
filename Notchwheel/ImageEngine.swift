//
//  ImageEngine.swift
//  Notchwheel
//
//  The five image actions (PRD P0-4), built on Apple's ImageIO: no third-party code.
//  Reads HEIC, JPG, PNG, TIFF, WebP and GIF (first frame); writes JPG, PNG, HEIC (and TIFF when
//  resizing a TIFF). Output always lands next to the original under a new name (P0-5).
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum OutputFormat: Sendable, Equatable {
    case jpeg(quality: Double)
    case png
    case heic(quality: Double)
    case tiff

    var type: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .tiff: .tiff
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .tiff: "tiff"
        }
    }

    var quality: Double? {
        switch self {
        case let .jpeg(q), let .heic(q): q
        case .png, .tiff: nil
        }
    }
}

nonisolated struct ImageAction: FileAction {
    let name: String
    /// nil keeps the source format where possible (Resize).
    let format: OutputFormat?
    /// Longest edge in pixels; never upscales. nil keeps the original size.
    let maxPixelSize: Int?
    /// Drops EXIF, GPS and other metadata (Compress), so shared photos don't leak location.
    let stripMetadata: Bool
    /// "compressed" gives photo-compressed.jpg; nil gives photo.jpg.
    let suffix: String?

    func process(_ input: URL) throws -> URL {
        let values = try? input.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true { throw FileActionError.unsupported("folder") }

        guard let source = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let typeID = CGImageSourceGetType(source) as String?,
              let sourceType = UTType(typeID), sourceType.conforms(to: .image),
              CGImageSourceGetCount(source) > 0
        else { throw FileActionError.unsupported("not an image") }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let longest = max(width, height)
        let target = min(maxPixelSize ?? longest, longest)

        // Decodes, applies the EXIF orientation and downscales in one step. Orientation is baked
        // into the pixels, so the output is always written upright (orientation 1).
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, target),
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions as CFDictionary) else {
            throw FileActionError.failed("couldn't read the image")
        }

        let output = format ?? Self.keepFormat(sourceType, hasAlpha: image.hasAlpha)
        if case .jpeg = output, image.hasAlpha {
            image = try Self.flattenedOnWhite(image) // JPG has no transparency; avoid black backgrounds
        }

        var writeProperties: [CFString: Any] = [:]
        if !stripMetadata {
            writeProperties = properties
            writeProperties[kCGImagePropertyPixelWidth] = nil
            writeProperties[kCGImagePropertyPixelHeight] = nil
            writeProperties[kCGImagePropertyOrientation] = 1
            if var tiff = writeProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                writeProperties[kCGImagePropertyTIFFDictionary] = tiff
            }
        }
        if let quality = output.quality {
            writeProperties[kCGImageDestinationLossyCompressionQuality] = quality
        }

        let folder = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let stem = suffix.map { "\(base)-\($0)" } ?? base

        // Write to a hidden temporary file first, so a failure never leaves a half-written file
        // under the real name, then move it to the first free name.
        let temp = folder.appendingPathComponent(".\(stem).notchwheel-\(UUID().uuidString).\(output.fileExtension)")
        defer { try? FileManager.default.removeItem(at: temp) }
        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, output.type.identifier as CFString, 1, nil) else {
            throw FileActionError.failed("can't write to \(folder.lastPathComponent)")
        }
        CGImageDestinationAddImage(destination, image, writeProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw FileActionError.failed("couldn't save the \(output.fileExtension.uppercased()) file")
        }
        return try Self.moveToFreeName(temp, folder: folder, stem: stem, fileExtension: output.fileExtension)
    }

    /// photo.jpg, or photo-2.jpg, photo-3.jpg... if taken. moveItem refuses to replace an
    /// existing file, so nothing (including the original) is ever overwritten.
    static func moveToFreeName(_ temp: URL, folder: URL, stem: String, fileExtension: String) throws -> URL {
        for n in 1...999 {
            let name = n == 1 ? "\(stem).\(fileExtension)" : "\(stem)-\(n).\(fileExtension)"
            let candidate = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { continue }
            do {
                try FileManager.default.moveItem(at: temp, to: candidate)
                return candidate
            } catch where FileManager.default.fileExists(atPath: candidate.path) {
                continue // taken in the meantime
            } catch {
                throw FileActionError.failed("couldn't save: \(error.localizedDescription)")
            }
        }
        throw FileActionError.failed("too many files named \(stem)")
    }

    /// Resize keeps JPG, PNG, HEIC and TIFF as they are; formats ImageIO can't write (WebP, GIF)
    /// become PNG if they have transparency, otherwise JPG.
    static func keepFormat(_ type: UTType, hasAlpha: Bool) -> OutputFormat {
        if type.conforms(to: .jpeg) { return .jpeg(quality: 0.9) }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return .heic(quality: 0.8) }
        if type.conforms(to: .tiff) { return .tiff }
        return hasAlpha ? .png : .jpeg(quality: 0.9)
    }

    static func flattenedOnWhite(_ image: CGImage) throws -> CGImage {
        let space = (image.colorSpace?.model == .rgb ? image.colorSpace : nil) ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw FileActionError.failed("couldn't prepare the image") }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        guard let flat = context.makeImage() else { throw FileActionError.failed("couldn't prepare the image") }
        return flat
    }
}

nonisolated extension CGImage {
    var hasAlpha: Bool {
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: true
        default: false
        }
    }
}

extension WheelSegment {
    /// The PRD P0-3 / P0-4 presets for each image segment. Nil for PDF, which combines the whole
    /// drop into one file instead of converting files one by one (see PDFMaker).
    var action: (any FileAction)? {
        switch self {
        case .toPDF:
            nil
        case .compress:
            ImageAction(name: "Compress", format: .jpeg(quality: 0.75), maxPixelSize: 2560, stripMetadata: true, suffix: "compressed")
        case .toJPG:
            ImageAction(name: "JPG", format: .jpeg(quality: 0.9), maxPixelSize: nil, stripMetadata: false, suffix: nil)
        case .toPNG:
            ImageAction(name: "PNG", format: .png, maxPixelSize: nil, stripMetadata: false, suffix: nil)
        case .toHEIC:
            ImageAction(name: "HEIC", format: .heic(quality: 0.8), maxPixelSize: nil, stripMetadata: false, suffix: nil)
        case .resize:
            ImageAction(name: "Resize", format: nil, maxPixelSize: 2048, stripMetadata: false, suffix: "resized")
        }
    }

    /// Runs this segment on a drop, off the main thread.
    func run(on urls: [URL]) async -> BatchResult {
        if let action { await BatchRunner.run(action, on: urls) } else { await PDFMaker.combine(urls) }
    }
}
