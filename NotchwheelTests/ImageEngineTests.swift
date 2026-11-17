//
//  ImageEngineTests.swift
//  NotchwheelTests
//
//  Milestone 3 gate: PRD P0-4 (pipeline), P0-5 (safe output) and P0-7 (unsupported files).
//  Fixtures are generated into a fresh temporary folder for each test.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Notchwheel

/// A fresh folder of generated sample files, deleted when the test ends.
final class Fixtures {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchwheel-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    /// A gradient image, optionally with a transparent half.
    static func image(width: Int, height: Int, alpha: Bool = false) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
        let gradient = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1), CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1)] as CFArray, locations: nil)!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        if alpha { ctx.clear(CGRect(x: 0, y: 0, width: width / 2, height: height)) }
        return ctx.makeImage()!
    }

    /// Writes an image file. `gps` adds a location, as an iPhone photo would have.
    @discardableResult
    func write(_ name: String, type: UTType, width: Int, height: Int, alpha: Bool = false, gps: Bool = false, orientation: Int? = nil) throws -> URL {
        let url = folder.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "TestPhone"]]
        if gps {
            props[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 37.8136, kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 144.9631, kCGImagePropertyGPSLongitudeRef: "E",
            ]
        }
        if let orientation { props[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(dest, Self.image(width: width, height: height, alpha: alpha), props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw FileActionError.failed("fixture") }
        return url
    }

    /// A 1×1 lossless WebP (ImageIO reads WebP but can't write it, so this one is embedded).
    func webp(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(base64Encoded: "UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==")!.write(to: url)
        return url
    }

    func text(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data("not an image".utf8).write(to: url)
        return url
    }

    func pdf(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        ctx.fill(CGRect(x: 20, y: 20, width: 100, height: 100))
        ctx.endPDFPage()
        ctx.closePDF()
        return url
    }

    func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }
}

/// What ended up in an output file.
struct ImageInfo {
    let type: UTType?
    let width: Int
    let height: Int
    let properties: [CFString: Any]

    init(_ url: URL) {
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
        type = (CGImageSourceGetType(src) as String?).flatMap(UTType.init)
        properties = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    }

    var hasGPS: Bool { properties[kCGImagePropertyGPSDictionary] != nil }
    var orientation: Int { (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1 }
}

struct ImageEngineTests {
    // MARK: P0-4 pipeline

    @Test func compressTurnsHEICIntoSmallerJPGWithoutLocation() async throws {
        let f = try Fixtures()
        let photo = try f.write("photo.heic", type: .heic, width: 4032, height: 3024, gps: true)
        let result = await BatchRunner.run(WheelSegment.compress.action!, on: [photo])

        #expect(result.outputs.map(\.lastPathComponent) == ["photo-compressed.jpg"])
        let out = ImageInfo(try #require(result.outputs.first))
        #expect(out.type == .jpeg)
        #expect(max(out.width, out.height) == 2560)       // longest edge capped
        #expect(out.width == 2560 && out.height == 1920)   // aspect ratio kept
        #expect(!out.hasGPS)                               // location stripped
        #expect(ImageInfo(photo).hasGPS)                   // original untouched
    }

    @Test func compressNeverUpscalesSmallImages() async throws {
        let f = try Fixtures()
        let small = try f.write("small.png", type: .png, width: 800, height: 600)
        let result = await BatchRunner.run(WheelSegment.compress.action!, on: [small])
        let out = ImageInfo(try #require(result.outputs.first))
        #expect(out.width == 800 && out.height == 600)
    }

    @Test func convertsBetweenFormats() async throws {
        let f = try Fixtures()
        let heic = try f.write("a.heic", type: .heic, width: 600, height: 400)
        let png = try f.write("b.png", type: .png, width: 600, height: 400, alpha: true)
        let jpg = try f.write("c.jpg", type: .jpeg, width: 600, height: 400)

        let toJPG = await BatchRunner.run(WheelSegment.toJPG.action!, on: [heic, png])
        #expect(Set(toJPG.outputs.map(\.lastPathComponent)) == ["a.jpg", "b.jpg"])
        #expect(toJPG.outputs.allSatisfy { ImageInfo($0).type == .jpeg })

        let toPNG = await BatchRunner.run(WheelSegment.toPNG.action!, on: [jpg])
        #expect(toPNG.outputs.map(\.lastPathComponent) == ["c.png"])
        #expect(ImageInfo(try #require(toPNG.outputs.first)).type == .png)

        let toHEIC = await BatchRunner.run(WheelSegment.toHEIC.action!, on: [jpg])
        #expect(toHEIC.outputs.map(\.lastPathComponent) == ["c.heic"])
        #expect(ImageInfo(try #require(toHEIC.outputs.first)).type == .heic)
    }

    @Test func readsWebP() async throws {
        let f = try Fixtures()
        let webp = try f.webp("sticker.webp")
        let result = await BatchRunner.run(WheelSegment.toPNG.action!, on: [webp])
        #expect(result.failures.isEmpty && result.skipped.isEmpty)
        let out = ImageInfo(try #require(result.outputs.first))
        #expect(out.type == .png && out.width == 1 && out.height == 1)
    }

    @Test func resizeKeepsFormatAndCapsLongestEdge() async throws {
        let f = try Fixtures()
        let wide = try f.write("wide.png", type: .png, width: 3000, height: 1000)
        let result = await BatchRunner.run(WheelSegment.resize.action!, on: [wide])
        #expect(result.outputs.map(\.lastPathComponent) == ["wide-resized.png"])
        let out = ImageInfo(try #require(result.outputs.first))
        #expect(out.type == .png && out.width == 2048 && out.height == 683)
    }

    @Test func rotatedPhotosComeOutUpright() async throws {
        let f = try Fixtures()
        // Stored landscape with orientation 6 ("rotate 90° to display"), so it displays portrait.
        let rotated = try f.write("rotated.jpg", type: .jpeg, width: 400, height: 200, orientation: 6)
        let result = await BatchRunner.run(WheelSegment.toPNG.action!, on: [rotated])
        let out = ImageInfo(try #require(result.outputs.first))
        #expect(out.width == 200 && out.height == 400)
        #expect(out.orientation == 1)
    }

    @Test func tenIPhonePhotosCompressInUnderThreeSeconds() async throws {
        let f = try Fixtures()
        let photos = try (1...10).map { try f.write("IMG_\($0).heic", type: .heic, width: 4032, height: 3024, gps: true) }
        let result = await BatchRunner.run(WheelSegment.compress.action!, on: photos)
        #expect(result.outputs.count == 10)
        #expect(result.seconds < 3, "took \(result.seconds) s")
    }

    // MARK: P0-5 safe output

    @Test func neverOverwritesExistingFilesOrTheOriginal() async throws {
        let f = try Fixtures()
        let jpg = try f.write("photo.jpg", type: .jpeg, width: 300, height: 200)
        let original = try Data(contentsOf: jpg)

        // → JPG on a JPG would be "photo.jpg", which is the original: it must become photo-2.jpg.
        let same = await BatchRunner.run(WheelSegment.toJPG.action!, on: [jpg])
        #expect(same.outputs.map(\.lastPathComponent) == ["photo-2.jpg"])
        #expect(try Data(contentsOf: jpg) == original)

        // Compressing twice gives -compressed and -compressed-2.
        _ = await BatchRunner.run(WheelSegment.compress.action!, on: [jpg])
        _ = await BatchRunner.run(WheelSegment.compress.action!, on: [jpg])
        #expect(try f.names() == ["photo-2.jpg", "photo-compressed-2.jpg", "photo-compressed.jpg", "photo.jpg"])
        #expect(try Data(contentsOf: jpg) == original)
    }

    @Test func leavesNoTemporaryFilesBehind() async throws {
        let f = try Fixtures()
        let png = try f.write("a.png", type: .png, width: 200, height: 200)
        _ = await BatchRunner.run(WheelSegment.toHEIC.action!, on: [png])
        #expect(try f.names() == ["a.heic", "a.png"])
    }

    // MARK: P0-7 unsupported files

    @Test func skipsNonImagesAndReportsThem() async throws {
        let f = try Fixtures()
        let photo = try f.write("photo.png", type: .png, width: 300, height: 200)
        let notes = try f.text("notes.txt")
        let doc = try f.pdf("invoice.pdf")
        let folder = f.folder.appendingPathComponent("Album")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)

        let result = await BatchRunner.run(WheelSegment.compress.action!, on: [photo, notes, doc, folder])
        #expect(result.outputs.count == 1)
        #expect(result.skipped.count == 3)
        #expect(result.failures.isEmpty)
        #expect(result.summary.contains("3 skipped (not images)"))
    }

    @Test func summaryReadsLikeThePRD() {
        var r = BatchResult()
        r.outputs = Array(repeating: URL(fileURLWithPath: "/tmp/x.jpg"), count: 4)
        r.bytesIn = 18_600_000
        r.bytesOut = 2_300_000
        r.skipped = [URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.txt")]
        #expect(r.summary == "4 files, 18.6 MB → 2.3 MB · 2 skipped (not images)")
    }
}
