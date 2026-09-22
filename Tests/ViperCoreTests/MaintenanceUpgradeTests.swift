import XCTest
@testable import ViperCore

final class MaintenanceUpgradeTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("viper-upgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    private func fixture(after: String = "2.0", status: Int = 0, offered: String = "2.0", metadataStatus: Int = 0, inventoryStatus: Int = 0) throws -> PackageUpgrade {
        let executable = folder.appendingPathComponent("brew")
        let script = """
        #!/bin/sh
        cd -- "$(dirname -- "$0")" || exit 99
        case "$1" in
          list)
            if [ -f started ]; then
              printf 'wget %s\\n' '\(after)'
              exit \(inventoryStatus)
            fi
            printf 'wget 1.0\\n'
            ;;
          info)
            printf '%s' '{"formulae":[{"name":"wget","versions":{"stable":"\(offered)"}}]}'
            exit \(metadataStatus)
            ;;
          upgrade)
            touch started
            exit \(status)
            ;;
          *) exit 99 ;;
        esac
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return try XCTUnwrap(PackageUpgrade(AvailableUpdate(name: "wget", package: "wget", installed: "1.0", available: "2.0", source: .homebrew, executable: executable, isCask: false, storeURL: nil)))
    }

    func testExactVersionAndSuccessfulCommandAreRequired() async throws {
        let request = try fixture()
        let result = await PackageProvider.upgrade(request)
        XCTAssertEqual(result.outcome, .updated("2.0"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("started").path))
    }

    func testFailedCommandWithTargetInstalledIsNotSuccess() async throws {
        let result = await PackageProvider.upgrade(try fixture(status: 42))
        guard case .failed = result.outcome else { return XCTFail("Unexpected outcome: \(result.outcome)") }
    }

    func testWrongPostVersionIsNotSuccess() async throws {
        let result = await PackageProvider.upgrade(try fixture(after: "1.5"))
        guard case .failed = result.outcome else { return XCTFail("Unexpected outcome: \(result.outcome)") }
    }

    func testFailedPostInventoryWithValidOutputIsNotSuccess() async throws {
        let result = await PackageProvider.upgrade(try fixture(inventoryStatus: 42))
        guard case .failed = result.outcome else { return XCTFail("Unexpected outcome: \(result.outcome)") }
    }

    func testChangedMetadataDoesNotStartUpgrade() async throws {
        let result = await PackageProvider.upgrade(try fixture(offered: "2.1"))
        guard case .skipped = result.outcome else { return XCTFail("Unexpected outcome: \(result.outcome)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("started").path))
    }

    func testFailedMetadataWithValidOutputDoesNotStartUpgrade() async throws {
        let result = await PackageProvider.upgrade(try fixture(metadataStatus: 42))
        guard case .skipped = result.outcome else { return XCTFail("Unexpected outcome: \(result.outcome)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("started").path))
    }

    func testVersionDeltaClassifiesDottedVersions() {
        XCTAssertEqual(PackageUpgrade.versionDelta(from: "1.2.3", to: "2.0.0"), "major update — review release notes")
        XCTAssertEqual(PackageUpgrade.versionDelta(from: "1.2.3", to: "1.3.0"), "minor update")
        XCTAssertEqual(PackageUpgrade.versionDelta(from: "1.2.3", to: "1.2.4"), "patch update")
        XCTAssertEqual(PackageUpgrade.versionDelta(from: "2", to: "2.0.1"), "patch update")
        XCTAssertNil(PackageUpgrade.versionDelta(from: "latest", to: "2.0.0"))
    }
}
