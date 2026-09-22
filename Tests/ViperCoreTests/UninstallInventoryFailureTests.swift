import XCTest
@testable import ViperCore

final class UninstallInventoryFailureTests: XCTestCase {
    func testFailedInventoryKeepsRelatedData() async throws {
        let manager = FileManager.default
        let home = manager.temporaryDirectory.appendingPathComponent("viper-inventory-failure-\(UUID().uuidString)").resolvingSymlinksInPath()
        try manager.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: home) }
        let brew = home.appendingPathComponent("brew")
        try "#!/bin/sh\ncase \"$1\" in uninstall) exit 0 ;; *) exit 42 ;; esac\n".write(to: brew, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: brew.path)
        let settings = home.appendingPathComponent(".audittool")
        try manager.createDirectory(at: settings, withIntermediateDirectories: true)
        let tool = CommandLinePackage(name: "audittool", package: "audittool", version: "1", summary: nil, source: .homebrewFormula,
                                      runtime: .init(manager: .homebrew, executable: brew), commands: ["audittool"], location: nil,
                                      isDependency: false, isBundledWithRuntime: false)
        let context = UninstallContext(home: home, applications: [], tools: [tool], protectedBundleIdentifiers: [], homebrewPrefixes: [])
        let plan = try UninstallPlanner.plan(for: tool, context: context)
        let outcomes = await UninstallExecutor.execute(plan, selected: Set(plan.items.map(\.id)), home: home, isRunning: { false }, trash: { _ in
            XCTFail("Related data must not be trashed when package removal cannot be verified")
            return nil
        })
        XCTAssertEqual(outcomes.count, 2)
        guard case .failed = outcomes.first?.result else { return XCTFail("Inventory failure must produce an unconfirmed removal") }
        guard case .skipped = outcomes.last?.result else { return XCTFail("Related data must be kept") }
        XCTAssertTrue(manager.fileExists(atPath: settings.path))
    }

    func testSuccessfulHomebrewUninstallConfirmsAbsenceFromFullInventory() async throws {
        let manager = FileManager.default
        let home = manager.temporaryDirectory.appendingPathComponent("viper-homebrew-uninstall-\(UUID().uuidString)").resolvingSymlinksInPath()
        try manager.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: home) }
        let brew = home.appendingPathComponent("brew")
        let script = """
        #!/bin/sh
        case "$1" in
          uninstall) exit 0 ;;
          list)
            if [ "$#" -gt 3 ]; then exit 1; fi
            printf 'another-tool 2.0\\n'
            ;;
          *) exit 42 ;;
        esac
        """
        try script.write(to: brew, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: brew.path)
        let runtime = PackageRuntime(manager: .homebrew, executable: brew)
        let request = try XCTUnwrap(PackageUninstall(runtime: runtime, kind: .formula, package: "audittool"))
        let outcome = await PackageProvider.uninstall(request)
        XCTAssertEqual(outcome, .removed)
    }
}
