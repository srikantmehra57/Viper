import XCTest
@testable import ViperCore

final class ShellEnvironmentTests: XCTestCase {
    func testParsesPathBetweenMarkersIgnoringShellNoise() {
        let text = "Welcome back!\n\u{1b}[1m prompt noise\n__M__/Users/me/.local/bin:/opt/homebrew/bin:relative:/opt/homebrew/bin__M__\n"
        XCTAssertEqual(ShellEnvironment.parse(text, marker: "__M__"), ["/Users/me/.local/bin", "/opt/homebrew/bin"])
        XCTAssertEqual(ShellEnvironment.parse("no markers here", marker: "__M__"), [])
    }

    func testResolveReturnsFirstExecutableOnPath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("viper-shell-\(UUID().uuidString)")
        let first = root.appendingPathComponent("a"), second = root.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in [first, second] {
            let tool = folder.appendingPathComponent("npm")
            FileManager.default.createFile(atPath: tool.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        }
        XCTAssertEqual(ShellEnvironment.resolve("npm", in: [first.path, second.path])?.path, first.appendingPathComponent("npm").path)
        XCTAssertNil(ShellEnvironment.resolve("npm", in: [root.path]))
    }
}

final class VolumeCapacityTests: XCTestCase {
    func testAvailableMatchesFinderAndPurgeableIsTheDifference() throws {
        let capacity = VolumeCapacity(name: "Disk", totalBytes: 245_000, availableBytes: 158_000, freeBytes: 151_000)
        XCTAssertEqual(capacity.usedBytes, 87_000)
        XCTAssertEqual(capacity.purgeableBytes, 7_000)
        let live = try VolumeCapacity.read(at: URL(fileURLWithPath: "/"))
        XCTAssertGreaterThanOrEqual(live.availableBytes, live.freeBytes)
        XCTAssertLessThanOrEqual(live.availableBytes, live.totalBytes)
    }
}
