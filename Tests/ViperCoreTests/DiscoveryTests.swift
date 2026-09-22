import Darwin
import XCTest
@testable import ViperCore

final class DiscoveryTests: XCTestCase {
    func testInstallerUsesReviewedNpmVersionAndRejectsInventoryErrors() throws {
        let runtime = PackageRuntime(manager: .npm, executable: URL(fileURLWithPath: "/usr/local/bin/npm"))
        let request = try XCTUnwrap(PackageRequest(method: .npm, package: "@vendor/tool", runtime: runtime))
        XCTAssertEqual(try PackageProvider.installArguments(request, reviewedVersion: "1.2.3"), ["install", "--global", "@vendor/tool@1.2.3"])
        XCTAssertThrowsError(try PackageProvider.installArguments(request, reviewedVersion: "latest"))
        XCTAssertThrowsError(try PackageProvider.parseNpmList(Data(#"{"error":{"code":"EACCES"}}"#.utf8)))
        XCTAssertThrowsError(try PackageProvider.parseNpmList(Data(#"{"problems":["missing dependency"],"dependencies":{}}"#.utf8)))
    }
    func testLeftoverMatchingExcludesSystemAndInstalledHelpers() {
        let installed: Set<String> = ["com.vendor.App", "org.tool.desktop"]
        XCTAssertFalse(LeftoverScanner.isCandidate("com.apple.finder", installedIdentifiers: installed))
        XCTAssertFalse(LeftoverScanner.isCandidate("com.vendor.app", installedIdentifiers: installed))
        XCTAssertFalse(LeftoverScanner.isCandidate("com.vendor.app.helper", installedIdentifiers: installed))
        XCTAssertFalse(LeftoverScanner.isCandidate("org.tool", installedIdentifiers: installed))
        XCTAssertFalse(LeftoverScanner.isCandidate("random-name", installedIdentifiers: installed))
        XCTAssertTrue(LeftoverScanner.isCandidate("com.oldvendor.app", installedIdentifiers: installed))
    }

    func testLeftoverScanUsesOnlySupportedLocationsAndSkipsSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = root.appendingPathComponent("Preferences")
        try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
        try Data().write(to: preferences.appendingPathComponent("com.old.app.plist"))
        try Data().write(to: preferences.appendingPathComponent("com.installed.app.plist"))
        try Data().write(to: preferences.appendingPathComponent("com.apple.finder.plist"))
        try FileManager.default.createSymbolicLink(at: preferences.appendingPathComponent("com.link.app.plist"), withDestinationURL: preferences.appendingPathComponent("com.old.app.plist"))
        let report = try LeftoverScanner.scan(library: root, installedIdentifiers: ["com.installed.app"])
        XCTAssertEqual(report.items.count, 1)
        XCTAssertEqual(report.items.first?.url.lastPathComponent, "com.old.app.plist")
        XCTAssertTrue(report.items.first?.reason.contains("No installed app") == true)
        XCTAssertFalse(report.items.first!.selectedByDefault, "Settings are never preselected")
    }

    func testBrewParsingFiltersPinnedAndPreservesVersions() throws {
        let data = Data(#"{"formulae":[{"name":"git","installed_versions":["2.1"],"current_version":"2.2","pinned":false},{"name":"pinned","installed_versions":["1"],"current_version":"2","pinned":true}],"casks":[{"name":"editor","installed_versions":["1.0"],"current_version":"2.0"}]}"#.utf8)
        let updates = try UpdateChecker.parseBrew(data, executable: URL(fileURLWithPath: "/opt/homebrew/bin/brew"))
        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates[0].installed, "2.1")
        XCTAssertTrue(updates[1].isCask)
    }

    func testNpmParsingHandlesScopedPackagesAndRejectsErrorPayload() throws {
        let data = Data(#"{"@vendor/agent":{"current":"1.0","latest":"2.0"},"same":{"current":"1","latest":"1"}}"#.utf8)
        let updates = try UpdateChecker.parseNpm(data, executable: URL(fileURLWithPath: "/usr/local/bin/npm"))
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0].package, "@vendor/agent")
        XCTAssertThrowsError(try UpdateChecker.parseNpm(Data(#"{"error":{"code":"NETWORK"}}"#.utf8), executable: URL(fileURLWithPath: "/usr/local/bin/npm")))
    }

    func testPackageIdentifiersAndNumericVersions() {
        XCTAssertFalse(UpdateChecker.safePackage("--flag", npm: false))
        XCTAssertFalse(UpdateChecker.safePackage("package;command", npm: true))
        XCTAssertFalse(UpdateChecker.safePackage("../escape", npm: false))
        XCTAssertTrue(UpdateChecker.safePackage("@vendor/tool", npm: true))
        XCTAssertTrue(UpdateChecker.isNewer("1.10", than: "1.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.1", than: "2.0"))
    }

    func testStorageExclusionsAndHiddenPreference() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let excluded = root.appendingPathComponent("Excluded")
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
        try Data([1]).write(to: excluded.appendingPathComponent("skip.txt"))
        try Data([1]).write(to: root.appendingPathComponent(".hidden"))
        try Data([1]).write(to: root.appendingPathComponent("visible.txt"))
        let result = try await StorageScanner.scan(root: root, excluding: [excluded], includeHiddenFiles: false)
        XCTAssertEqual(result.files, 1)
        XCTAssertEqual(result.largestFiles.first?.url.lastPathComponent, "visible.txt")
    }

    func testCommandEnvironmentOmitsTheSSHAgent() async throws {
        let output = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/printenv"), arguments: [])
        let text = String(decoding: output.data, as: UTF8.self)
        XCTAssertFalse(text.contains("SSH_AUTH_SOCK="))
        XCTAssertTrue(text.contains("HOMEBREW_NO_AUTO_UPDATE=1"))
        XCTAssertEqual(output.status, 0)
    }

    func testCommandRunnerExitAndCancellation() async throws {
        let output = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["hello"])
        XCTAssertEqual(String(data: output.data, encoding: .utf8), "hello")
        XCTAssertEqual(output.status, 0)
        let task = Task { try await CommandRunner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"]) }
        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
    }

    func testTimeoutKillsTheWholeProcessGroup() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("viper-pgroup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let marker = folder.appendingPathComponent("child-survived")
        let script = folder.appendingPathComponent("spawn")
        try "#!/bin/sh\n( trap '' TERM; sleep 1; touch \"\(marker.path)\" ) &\nsleep 60\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        do {
            _ = try await CommandRunner.run(script, arguments: [], timeout: 0.4)
            XCTFail("Expected a timeout")
        } catch CommandError.timeout {}
        // If only the parent was killed, the detached child finishes its sleep and writes the marker.
        try await Task.sleep(nanoseconds: 1_800_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "A surviving child means the process group was not killed")
    }

    func testTimeoutKillsAChildThatLeftTheProcessGroup() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("viper-setsid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pidfile = folder.appendingPathComponent("pid")
        let marker = folder.appendingPathComponent("survived")
        let script = folder.appendingPathComponent("escape.py")
        let source = """
        import os, sys, time
        pidfile, marker = sys.argv[1], sys.argv[2]
        pid = os.fork()
        if pid == 0:
            os.setsid()
            with open(pidfile, "w") as handle:
                handle.write(str(os.getpid()))
                handle.flush()
                os.fsync(handle.fileno())
            time.sleep(8)
            open(marker, "w").close()
            os._exit(0)
        time.sleep(60)
        """
        try source.write(to: script, atomically: true, encoding: .utf8)
        defer {
            if let text = try? String(contentsOf: pidfile, encoding: .utf8), let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                kill(pid, SIGKILL)
            }
        }
        do {
            _ = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/python3"), arguments: [script.path, pidfile.path, marker.path], timeout: 0.6)
            XCTFail("Expected a timeout")
        } catch CommandError.timeout {
        } catch CommandError.unsettled {
            XCTFail("A child that left the process group was still running")
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        let text = try String(contentsOf: pidfile, encoding: .utf8)
        let pid = try XCTUnwrap(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertNotEqual(kill(pid, 0), 0, "A child that left the process group was still alive")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testTimeoutKillsAGrandchildThatWasReparented() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("viper-orphan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pidfile = folder.appendingPathComponent("pid")
        let marker = folder.appendingPathComponent("survived")
        let script = folder.appendingPathComponent("orphan.py")
        let source = """
        import os, sys, time
        pidfile, marker = sys.argv[1], sys.argv[2]
        child = os.fork()
        if child == 0:
            os.setsid()
            grand = os.fork()
            if grand > 0:
                time.sleep(0.08)
                os._exit(0)
            with open(pidfile, "w") as handle:
                handle.write(str(os.getpid()))
                handle.flush()
                os.fsync(handle.fileno())
            time.sleep(8)
            open(marker, "w").close()
            os._exit(0)
        time.sleep(30)
        """
        try source.write(to: script, atomically: true, encoding: .utf8)
        defer {
            if let text = try? String(contentsOf: pidfile, encoding: .utf8), let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                kill(pid, SIGKILL)
            }
        }
        do {
            _ = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/python3"), arguments: [script.path, pidfile.path, marker.path], timeout: 0.7)
            XCTFail("Expected a timeout")
        } catch CommandError.timeout {
        } catch CommandError.unsettled {
            XCTFail("A reparented grandchild was still running")
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        let text = try String(contentsOf: pidfile, encoding: .utf8)
        let pid = try XCTUnwrap(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertNotEqual(kill(pid, 0), 0, "A reparented grandchild was still alive")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }
}
