import XCTest
@testable import ViperCore

final class ProgressTests: XCTestCase {
    func testHomebrewOutputAdvancesThroughPhases() {
        var parser = ProgressParser()
        XCTAssertTrue(parser.consume("==> Fetching downloads for: merve\n==> Downloading https://ghcr.io/v2/homebrew/core/merve/blobs/sha256:abc\n"))
        XCTAssertEqual(parser.progress.phase, .downloading)
        XCTAssertEqual(parser.progress.detail, "Downloading sha256:abc")
        _ = parser.consume("==> Pouring merve--1.2.2_3.arm64_sequoia.bottle.tar.gz\n")
        XCTAssertEqual(parser.progress.phase, .installing)
        _ = parser.consume("==> Downloading https://example.com/late.tar.gz\n")
        XCTAssertEqual(parser.progress.phase, .installing, "Progress never moves backwards")
    }

    func testCurlProgressBarPercentagesAreReadAcrossCarriageReturns() {
        var parser = ProgressParser()
        _ = parser.consume("==> Downloading https://example.com/app.dmg\n")
        _ = parser.consume("#####                     21.4%\r##########                42.0%")
        XCTAssertEqual(parser.progress.downloadFraction ?? 0, 0.42, accuracy: 0.001)
        _ = parser.consume("\r#####                     20.0%\r")
        XCTAssertEqual(parser.progress.downloadFraction ?? 0, 0.42, accuracy: 0.001, "A lower redraw doesn't reduce progress")
    }

    func testNpmHttpLogsCountAsDownloading() {
        var parser = ProgressParser()
        _ = parser.consume("npm http fetch GET 200 https://registry.npmjs.org/@openai/codex 120ms (cache miss)\n")
        XCTAssertEqual(parser.progress.phase, .downloading)
        _ = parser.consume("added 1 package in 3s\n")
        XCTAssertEqual(parser.progress.phase, .installing)
    }

    func testOverallFractionOnlyGrowsWithPhase() {
        let phases = OperationProgress.Phase.allCases.map { OperationProgress(phase: $0).overallFraction }
        XCTAssertEqual(phases, phases.sorted())
    }

    func testDownloadBytesOnlyIncrease() {
        var parser = ProgressParser()
        parser.observeDownload(bytes: 5_000)
        parser.observeDownload(bytes: 2_000)
        XCTAssertEqual(parser.progress.downloadedBytes, 5_000)
        XCTAssertEqual(parser.progress.phase, .downloading)
    }

    func testCommandRunnerStreamsOutputWhileRunning() async throws {
        final class Collector: @unchecked Sendable {
            let lock = NSLock()
            var chunks: [String] = []
            func add(_ text: String) { lock.lock(); chunks.append(text); lock.unlock() }
        }
        let collector = Collector()
        let output = try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"),
                                                 arguments: ["-c", "echo first; sleep 0.4; echo second"],
                                                 onOutput: { collector.add($0) })
        XCTAssertEqual(output.status, 0)
        XCTAssertGreaterThanOrEqual(collector.chunks.count, 2, "Output arrives in pieces while the command runs")
        XCTAssertEqual(collector.chunks.joined(), "first\nsecond\n")
        XCTAssertEqual(String(decoding: output.data, as: UTF8.self), "first\nsecond\n")
    }
}
