//
//  UsageLogTests.swift
//  NotchwheelTests
//

import Foundation
import Testing
@testable import Notchwheel

struct UsageLogTests {
    @Test func writesHeaderOnceThenOneRowPerDrop() throws {
        let f = try Fixtures()
        let log = f.folder.appendingPathComponent("logs/usage.csv")   // folder doesn't exist yet
        var r = BatchResult()
        r.outputs = [URL(fileURLWithPath: "/tmp/a.jpg"), URL(fileURLWithPath: "/tmp/b.jpg")]
        r.skipped = [URL(fileURLWithPath: "/tmp/notes.txt")]
        r.bytesIn = 18_600_000
        r.bytesOut = 2_300_000
        r.seconds = 0.84
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        UsageLog.record(action: "Compress", files: 3, result: r, date: date, to: log)
        UsageLog.record(action: "PDF", files: 1, result: BatchResult(), date: date, to: log)

        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[0] == Substring(UsageLog.header))
        #expect(lines[1] == "2027-01-15T08:00:00Z,Compress,3,18.60,2.30,0.84,2,1,0")
        #expect(lines[2].hasPrefix("2027-01-15T08:00:00Z,PDF,1,0.00,0.00,"))
    }
}
