//
//  PDFMakerTests.swift
//  NotchwheelTests
//
//  The PDF segment: many images in, one PDF out.
//

import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Notchwheel

struct PDFMakerTests {
    private func pages(of url: URL) -> [CGRect] {
        guard let doc = CGPDFDocument(url as CFURL) else { return [] }
        return (1...max(1, doc.numberOfPages)).compactMap { doc.page(at: $0)?.getBoxRect(.mediaBox) }
    }

    @Test func combinesSeveralImagesIntoOnePDF() async throws {
        let f = try Fixtures()
        let a = try f.write("scan 1.jpg", type: .jpeg, width: 1200, height: 1600)
        let b = try f.write("scan 2.png", type: .png, width: 1600, height: 1200, alpha: true)
        let c = try f.write("scan 10.heic", type: .heic, width: 1200, height: 1600)
        let result = await WheelSegment.toPDF.run(on: [c, b, a])
        #expect(result.outputs.count == 1)
        #expect(result.failures.isEmpty)
        let pdf = try #require(result.outputs.first)
        // Named after the first file in filename order ("scan 1", then "scan 2", then "scan 10").
        #expect(pdf.lastPathComponent == "scan 1-combined.pdf")
        let boxes = pages(of: pdf)
        #expect(boxes.count == 3)
        #expect(boxes[0].height > boxes[0].width)   // portrait
        #expect(boxes[1].width > boxes[1].height)   // the landscape PNG gets a landscape page
        #expect(boxes[2].height > boxes[2].width)
    }

    @Test func singleImageKeepsItsName() async throws {
        let f = try Fixtures()
        let photo = try f.write("receipt.jpg", type: .jpeg, width: 800, height: 1000)
        let result = await WheelSegment.toPDF.run(on: [photo])
        #expect(result.outputs.first?.lastPathComponent == "receipt.pdf")
        #expect(pages(of: try #require(result.outputs.first)).count == 1)
        let again = await WheelSegment.toPDF.run(on: [photo])
        #expect(again.outputs.first?.lastPathComponent == "receipt-2.pdf")
    }

    @Test func skipsNonImagesAndLeavesOriginalsAlone() async throws {
        let f = try Fixtures()
        let photo = try f.write("photo.jpg", type: .jpeg, width: 500, height: 500)
        let before = try Data(contentsOf: photo)
        let notes = f.folder.appendingPathComponent("notes.txt")
        try "hi".write(to: notes, atomically: true, encoding: .utf8)
        let result = await WheelSegment.toPDF.run(on: [notes, photo])
        #expect(result.outputs.count == 1)
        #expect(result.skipped == [notes])
        #expect(try Data(contentsOf: photo) == before)
        // No temp files left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: f.folder.path).filter { $0.hasPrefix(".") }
        #expect(leftovers.isEmpty)
    }

    @Test func nothingWrittenWhenNoImages() async throws {
        let f = try Fixtures()
        let notes = f.folder.appendingPathComponent("notes.txt")
        try "hi".write(to: notes, atomically: true, encoding: .utf8)
        let result = await WheelSegment.toPDF.run(on: [notes])
        #expect(result.outputs.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.folder.path) == ["notes.txt"])
    }

    @Test func bigPhotosStaySmall() async throws {
        let f = try Fixtures()
        let big = try f.write("big.png", type: .png, width: 4032, height: 3024)
        let result = await WheelSegment.toPDF.run(on: [big])
        // Capped at 2480 px and embedded as JPEG, not raw pixels (which would be ~22 MB).
        #expect(result.bytesOut > 0 && result.bytesOut < 2_000_000)
    }
}
