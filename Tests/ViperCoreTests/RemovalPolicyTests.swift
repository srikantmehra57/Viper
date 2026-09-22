import XCTest
@testable import ViperCore

final class RemovalPolicyTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/viper-test")

    func testSystemPathsAndHomeRootAreProtected() {
        for path in ["/", "/System/Library/file", "/usr/local/bin/tool", "/Library/Application Support/shared", "/Users/viper-test", "/Users/someone-else/file"] {
            guard case .protected = RemovalPolicy.assess(URL(fileURLWithPath: path), home: home) else {
                return XCTFail("Must protect \(path)")
            }
        }
    }

    func testPersonalDataAlwaysRequiresReview() {
        guard case .reviewRequired = RemovalPolicy.assess(home.appendingPathComponent("Documents/report.pdf"), home: home) else {
            return XCTFail("Personal data must require review")
        }
    }

    func testSharedSettingsAndCredentialsAreProtected() {
        for suffix in ["Library/Preferences/app.plist", ".ssh/id_ed25519", ".aws/credentials", ".config/tool/settings"] {
            guard case .protected = RemovalPolicy.assess(home.appendingPathComponent(suffix), home: home) else {
                return XCTFail("Sensitive data must be protected")
            }
        }
    }

    func testPathPrefixDoesNotAcceptOtherUser() {
        guard case .protected = RemovalPolicy.assess(URL(fileURLWithPath: "/Users/viper-test-other/Downloads/file"), home: home) else {
            return XCTFail("Path containment must use component boundaries")
        }
    }

    func testSymlinkEscapeIsProtected() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ViperPolicy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let link = temporary.appendingPathComponent("system-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/System"))
        guard case .protected = RemovalPolicy.assess(link.appendingPathComponent("Library"), home: temporary) else {
            return XCTFail("Symlinks must not bypass protection")
        }
    }
}
