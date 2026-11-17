//
//  PDFMaker.swift
//  Notchwheel
//
//  The "PDF" segment: every image in a drop becomes one page of a single PDF, in filename order,
//  for upload forms that only accept PDFs. Unlike the image actions this is many files in, one file
//  out, so it doesn't conform to FileAction (one in, one out); WheelSegment.run(on:) picks the engine.
//
//  Pages are A4, turned to landscape for landscape images, with the image scaled to fit on white.
//  Images are capped at 2480 px (A4 at 300 dpi) and embedded as JPEG, so a batch of phone photos
//  stays small enough for upload limits. Originals are never modified (P0-5).
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum PDFMaker {
    static let a4 = CGSize(width: 595.28, height: 841.89)   // points
    static let maxPixelSize = 2480
    static let jpegQuality = 0.8

    /// Never throws: each input ends up as a page, a skip or a failure.
    @concurrent
    static func combine(_ inputs: [URL]) async -> BatchResult {
        let start = Date()
        var result = BatchResult()
        let ordered = inputs.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        guard let first = ordered.first else { return result }

        let folder = first.deletingLastPathComponent()
        let temp = folder.appendingPathComponent(".notchwheel-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temp) }

        var defaultBox = CGRect(origin: .zero, size: a4)
        guard let context = CGContext(temp as CFURL, mediaBox: &defaultBox, nil) else {
            result.failures = ordered.map { .init(input: $0, reason: "can't write to \(folder.lastPathComponent)") }
            return result
        }

        var pageSources: [URL] = []
        for input in ordered {
            do {
                let image = try page(from: input)
                draw(image, into: context)
                pageSources.append(input)
                result.bytesIn += fileSize(input)
            } catch FileActionError.unsupported {
                result.skipped.append(input)
            } catch FileActionError.failed(let reason) {
                result.failures.append(.init(input: input, reason: reason))
            } catch {
                result.failures.append(.init(input: input, reason: error.localizedDescription))
            }
        }
        context.closePDF()

        if !pageSources.isEmpty {
            // One image: photo.pdf. Several: firstphoto-combined.pdf, next to the first image.
            let base = pageSources[0].deletingPathExtension().lastPathComponent
            let stem = pageSources.count == 1 ? base : "\(base)-combined"
            do {
                let output = try ImageAction.moveToFreeName(temp, folder: folder, stem: stem, fileExtension: "pdf")
                result.outputs = [output]
                result.bytesOut = fileSize(output)
            } catch {
                let reason = (error as? FileActionError).map { "\($0)" } ?? error.localizedDescription
                result.failures += pageSources.map { .init(input: $0, reason: reason) }
                result.bytesIn = 0
            }
        }
        result.seconds = Date().timeIntervalSince(start)
        return result
    }

    /// Decodes an image upright, capped at `maxPixelSize`, flattened on white, and re-encoded as a
    /// JPEG-backed CGImage so Quartz embeds the compressed JPEG data instead of raw pixels.
    static func page(from input: URL) throws -> CGImage {
        let values = try? input.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true { throw FileActionError.unsupported("folder") }

        guard let source = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let typeID = CGImageSourceGetType(source) as String?,
              let sourceType = UTType(typeID), sourceType.conforms(to: .image),
              CGImageSourceGetCount(source) > 0
        else { throw FileActionError.unsupported("not an image") }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FileActionError.failed("couldn't read the image")
        }
        if image.hasAlpha { image = try ImageAction.flattenedOnWhite(image) }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw FileActionError.failed("couldn't compress the image")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let provider = CGDataProvider(data: data),
              let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw FileActionError.failed("couldn't compress the image") }
        return jpeg
    }

    /// Adds one A4 page (landscape for landscape images) with the image centred and scaled to fit.
    static func draw(_ image: CGImage, into context: CGContext) {
        let landscape = image.width > image.height
        var box = CGRect(origin: .zero, size: landscape ? CGSize(width: a4.height, height: a4.width) : a4)
        let boxData = withUnsafeBytes(of: &box) { Data($0) } as CFData
        context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(box)
        let scale = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let origin = CGPoint(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: origin, size: size))
        context.endPDFPage()
    }

    private static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
