import Foundation
import Testing
@testable import SwiftStarKit

struct LineBufferTests {
    @Test func retainsPartialLinesAndReturnsAllCompleteLines() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("first\nse".utf8)).map { String(decoding: $0, as: UTF8.self) } == ["first"])
        #expect(buffer.append(Data("cond\nthird\n".utf8)).map { String(decoding: $0, as: UTF8.self) } == ["second", "third"])
        #expect(buffer.finish() == nil)
    }

    @Test func finishReportsAnUnterminatedDiagnosticLine() {
        var buffer = LineBuffer()
        _ = buffer.append(Data("partial".utf8))
        #expect(buffer.finish().map { String(decoding: $0, as: UTF8.self) } == "partial")
        #expect(buffer.finish() == nil)
    }
}
