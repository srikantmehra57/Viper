import XCTest
@testable import ViperCore

final class CommandLineInventoryTests: XCTestCase {
    func testNpmGlobalsListCommandsAndMarkBundledTools() throws {
        let runtime = PackageRuntime(manager: .npm, executable: URL(fileURLWithPath: "/opt/homebrew/bin/npm"))
        let data = Data(#"{"dependencies":{"@deepseek-ai/dsh":{"version":"0.1.5","description":"dsh CLI","bin":{"dsh":"lib/bin.js"},"path":"/opt/homebrew/lib/node_modules/@deepseek-ai/dsh"},"@scope/single":{"version":"1.0.0","bin":"cli.js"},"npm":{"version":"11.0.0","bin":{"npm":"a","npx":"b"}},"../bad":{"version":"1"}}}"#.utf8)
        let packages = try CommandLineInventory.parseNpmInstalled(data, runtime: runtime).sorted { $0.name < $1.name }
        XCTAssertEqual(packages.map(\.name), ["@deepseek-ai/dsh", "@scope/single", "npm"])
        XCTAssertEqual(packages[0].commands, ["dsh"])
        XCTAssertEqual(packages[0].location?.path, "/opt/homebrew/lib/node_modules/@deepseek-ai/dsh")
        XCTAssertEqual(packages[0].manualRemovalCommand, "/opt/homebrew/bin/npm uninstall --global @deepseek-ai/dsh")
        XCTAssertEqual(packages[1].commands, ["single"])
        XCTAssertTrue(packages[2].isBundledWithRuntime)
        XCTAssertThrowsError(try CommandLineInventory.parseNpmInstalled(Data(#"{"error":{"code":"EACCES"}}"#.utf8), runtime: runtime))
    }

    func testBrewFormulaeMarkDependenciesAndSkipAppCasks() throws {
        let prefix = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: prefix) }
        let bin = prefix.appendingPathComponent("opt/node/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data().write(to: bin.appendingPathComponent("node"))
        let runtime = PackageRuntime(manager: .homebrew, executable: prefix.appendingPathComponent("bin/brew"))
        let data = Data(#"{"formulae":[{"name":"node","desc":"JavaScript runtime","installed":[{"version":"26.8.2","installed_on_request":true}]},{"name":"libuv","installed":[{"version":"1.52.1","installed_on_request":false}]}],"casks":[{"token":"editor","name":["Editor"],"installed":"2.0","artifacts":[{"app":["Editor.app"]}]},{"token":"gcloud-cli","name":["Google Cloud CLI"],"installed":"500.0","artifacts":[{"binary":["google-cloud-sdk/bin/gcloud"]}]}]}"#.utf8)
        let packages = try CommandLineInventory.parseBrewInstalled(data, runtime: runtime)
        XCTAssertEqual(packages.map(\.name), ["node", "libuv", "Google Cloud CLI"])
        XCTAssertEqual(packages[0].commands, ["node"])
        XCTAssertFalse(packages[0].isDependency)
        XCTAssertTrue(packages[1].isDependency)
        XCTAssertEqual(packages[2].commands, ["gcloud"])
        XCTAssertEqual(packages[2].manualRemovalCommand, prefix.path + "/bin/brew uninstall --cask gcloud-cli")
    }

    func testLiveInventoryFindsGlobalNpmPackages() async throws {
        let npm = PackageRuntime.detect(.npm)
        try XCTSkipIf(npm.isEmpty, "npm is not installed")
        let result = try await CommandLineInventory.read(homebrew: [], npm: npm)
        XCTAssertTrue(result.checks.allSatisfy(\.succeeded), "\(result.checks)")
        XCTAssertTrue(result.packages.contains { $0.name == "npm" })
    }
}
