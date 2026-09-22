import XCTest
@testable import ViperCore

final class CleanupTests: XCTestCase {
    private var home: URL!
    private let manager = FileManager.default

    override func setUpWithError() throws {
        home = manager.temporaryDirectory.appendingPathComponent("viper-cleanup-\(UUID().uuidString)").resolvingSymlinksInPath()
        try manager.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? manager.removeItem(at: home) }

    @discardableResult
    private func make(_ path: String, directory: Bool = false, bytes: Int = 4096, modified: Date? = nil) throws -> URL {
        let url = home.appendingPathComponent(path)
        if directory {
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 7, count: bytes).write(to: url)
        }
        if let modified { try manager.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    private func fixtureTrash() throws -> UninstallExecutor.Trasher {
        let trash = try make(".FixtureTrash", directory: true)
        return { url in
            let destination = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    func testJunkScanSelectsRebuildableItemsAndKeepsRunningAppsAndRecentTemp() throws {
        let now = Date()
        let old = now.addingTimeInterval(-10 * 24 * 3600)
        try make("Library/Caches/com.vendor.tool/blob")
        try make("Library/Caches/com.vendor.open/blob")
        try make("Library/Caches/Slack/blob")
        try make("Library/Caches/Codex/blob")
        try make("Library/Caches/BraveSoftware/blob")
        try make("Library/Caches/ms-playwright/chromium")
        try make("Library/Caches/Spotify/blob")
        try make("Library/Caches/com.apple.Safari/blob")
        try make("Library/Logs/Tool/log.txt")
        try make("Library/Developer/Xcode/DerivedData/App-abc/Build/x.o")
        try make("Library/Developer/Xcode/iOS DeviceSupport/17.0/symbols")
        try make(".npm/_cacache/index")
        let temp = try make("tmp", directory: true)
        try make("tmp/old-download.part", modified: old)
        try make("tmp/fresh.part")
        try make("tmp/viper-process-1/output", modified: old)

        let report = try JunkScanner.scan(.init(home: home, temporaryDirectory: temp, runningIdentifiers: ["com.vendor.open"], runningNames: ["Slack", "Brave Browser", "Codex"], displayNames: ["com.vendor.open": "Open Tool", "codex": "Codex"], now: now))
        let byName = Dictionary(report.items.map { ($0.url.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
        XCTAssertTrue(byName["com.vendor.tool"]?.selectedByDefault == true)
        XCTAssertEqual(byName["com.vendor.tool"]?.confidence, .exact)
        XCTAssertEqual(byName["Spotify"]?.confidence, .likely)
        XCTAssertFalse(byName["Spotify"]!.selectedByDefault, "A vendor folder name is not an exact cache match")
        XCTAssertNil(byName["com.vendor.open"])
        XCTAssertNil(byName["Slack"])
        XCTAssertNil(byName["Codex"])
        XCTAssertTrue(report.kept.contains { $0.url.lastPathComponent == "com.vendor.open" && $0.reason.hasPrefix("Open Tool") })
        XCTAssertNil(byName["BraveSoftware"], "Vendor cache folders of open apps are kept")
        XCTAssertFalse(byName["ms-playwright"]!.selectedByDefault)
        XCTAssertTrue(report.kept.contains { $0.url.lastPathComponent == "Slack" })
        XCTAssertNil(byName["com.apple.Safari"], "macOS caches are skipped")
        XCTAssertEqual(byName["Tool"]?.kind, .logs)
        XCTAssertEqual(byName["App-abc"]?.kind, .developer)
        XCTAssertFalse(byName["17.0"]!.selectedByDefault, "Slow-to-rebuild device symbols are not preselected")
        XCTAssertTrue(byName["_cacache"]?.selectedByDefault == true)
        XCTAssertEqual(byName["old-download.part"]?.kind, .temporary)
        XCTAssertNil(byName["fresh.part"], "Recent temporary files may be in use")
        XCTAssertNil(byName["viper-process-1"])
        let parents = JunkScanner.allowedParents(home: home, temporaryDirectory: temp)
        XCTAssertTrue(report.items.allSatisfy { parents.contains($0.parentPath) }, "Every offered item is inside a location the executor accepts")
    }

    func testBundleIdentifierPieceKeepsARunningAppsCache() {
        let owner = JunkScanner.runningOwner(name: "Codex", identifiers: ["com.openai.codex"], names: ["chatgpt"], displayNames: ["com.openai.codex": "ChatGPT"])
        XCTAssertEqual(owner, "ChatGPT")
        XCTAssertNil(JunkScanner.runningOwner(name: "Spotify", identifiers: ["com.openai.codex"], names: ["chatgpt"], displayNames: [:]))
    }

    func testOpenFileKeepsAFolderAProcessIsUsing() throws {
        let file = try make("Library/Caches/MysteryVendor/blob")
        let folder = file.deletingLastPathComponent()
        let handle = try FileHandle(forReadingFrom: file)
        XCTAssertTrue(OpenFiles.isInUse(folder))
        try handle.close()
        XCTAssertFalse(OpenFiles.isInUse(folder))
    }

    func testLeftoversRespectLaunchServicesAndPreselectOnlyRebuildableKinds() throws {
        let library = home.appendingPathComponent("Library")
        try make("Library/Preferences/com.gone.app.plist")
        try make("Library/Caches/com.gone.app/data")
        try make("Library/Containers/com.gone.app", directory: true)
        try make("Library/Group Containers/ABCDE12345.com.gone.app", directory: true)
        try make("Library/Caches/com.elsewhere.app.helper/data")
        try make("Library/Caches/com.installed.app.helper/data")
        try make("Library/Group Containers/group.com.installed.family", directory: true)
        try make("Library/Group Containers/group.com.installed.unclaimed", directory: true)
        try make("Library/Application Scripts/group.com.gone.shared", directory: true)
        let report = try LeftoverScanner.scan(library: library, installedIdentifiers: ["com.installed.app"],
                                              installedApplicationGroups: ["group.com.installed.family"],
                                              isKnownApp: { $0 == "com.elsewhere.app" })
        let paths = report.items.map { $0.url.deletingLastPathComponent().lastPathComponent + "/" + $0.url.lastPathComponent }
        XCTAssertEqual(Set(paths), ["Preferences/com.gone.app.plist", "Caches/com.gone.app", "Containers/com.gone.app", "Group Containers/ABCDE12345.com.gone.app", "Group Containers/group.com.installed.unclaimed", "Application Scripts/group.com.gone.shared"])
        XCTAssertTrue(report.kept.contains { $0.url.lastPathComponent == "group.com.installed.family" }, "An exact signed group entitlement keeps the shared container")
        XCTAssertTrue(report.items.contains { $0.url.lastPathComponent == "group.com.installed.unclaimed" }, "A broad vendor-name match is not ownership evidence")
        XCTAssertFalse(report.items.first { $0.url.lastPathComponent == "group.com.gone.shared" }!.selectedByDefault, "Shared groups are never preselected")
        XCTAssertTrue(report.items.first { $0.kind == .caches }!.selectedByDefault)
        XCTAssertFalse(report.items.first { $0.kind == .preferences }!.selectedByDefault)
        XCTAssertTrue(report.kept.contains { $0.url.lastPathComponent == "com.elsewhere.app.helper" }, "An app on another drive keeps its files")
        XCTAssertTrue(report.items.allSatisfy { LeftoverScanner.isAllowed($0, library: library) })
    }

    func testCleanupExecutorRechecksIdentityAndScopeAndCanPutBack() async throws {
        let library = home.appendingPathComponent("Library")
        let cache = try make("Library/Caches/com.gone.app/data").deletingLastPathComponent()
        let logs = try make("Library/Logs/com.gone.app/log").deletingLastPathComponent()
        let swapped = try make("Library/Caches/com.gone.other/data").deletingLastPathComponent()
        let report = try LeftoverScanner.scan(library: library, installedIdentifiers: [])
        try manager.removeItem(at: swapped)
        try make("Library/Caches/com.gone.other/replacement")

        let outcomes = await CleanupExecutor.trash(report.items, isAllowed: { item in
            item.url.lastPathComponent == logs.lastPathComponent && item.kind == .logs ? "App is back" : (LeftoverScanner.isAllowed(item, library: library) ? nil : "outside")
        }, trash: try fixtureTrash())
        func key(_ url: URL) -> String { url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent }
        let byName = Dictionary(uniqueKeysWithValues: outcomes.map { (key($0.item.url), $0.result) })
        XCTAssertTrue(byName[key(cache)]?.succeeded == true)
        XCTAssertEqual(byName[key(logs)], .skipped("App is back"))
        guard case .skipped? = byName[key(swapped)] else { return XCTFail("A replaced folder must be skipped") }
        XCTAssertFalse(manager.fileExists(atPath: cache.path))
        XCTAssertTrue(manager.fileExists(atPath: swapped.appendingPathComponent("replacement").path))

        XCTAssertEqual(UninstallExecutor.restore(outcomes).filter(\.restored).map { key($0.item.url) }, [key(cache)])
        XCTAssertTrue(manager.fileExists(atPath: cache.appendingPathComponent("data").path))
    }

    func testCleanupStopsWhenReviewedChangesTurnOff() async throws {
        let cache = try make("Library/Caches/com.gone.app/data").deletingLastPathComponent()
        let report = try LeftoverScanner.scan(library: home.appendingPathComponent("Library"), installedIdentifiers: [])
        XCTAssertFalse(report.items.isEmpty)
        let outcomes = await CleanupExecutor.trash(report.items, isAllowed: { _ in nil }, mayContinue: { false }, trash: try fixtureTrash())
        XCTAssertFalse(outcomes.contains { $0.result.succeeded })
        XCTAssertTrue(manager.fileExists(atPath: cache.path))
        XCTAssertTrue(outcomes.allSatisfy {
            if case .skipped(let reason) = $0.result { return reason.contains("Reviewed changes were turned off") }
            return false
        })
    }

    func testWaitingWorkStaysBlockedUntilChangesAndJournalsAreClear() {
        XCTAssertNil(ReviewedChangePolicy.waitingWorkBlocked(changesAllowed: true, journalNeedsReview: false))
        XCTAssertNotNil(ReviewedChangePolicy.waitingWorkBlocked(changesAllowed: false, journalNeedsReview: false))
        XCTAssertNotNil(ReviewedChangePolicy.waitingWorkBlocked(changesAllowed: true, journalNeedsReview: true))
    }

    func testStorageCleanupBlocksAppsAndProtectedLocationsAndChangedFiles() throws {
        let movie = try make("Movies/big.mov", bytes: 8192)
        let size = try XCTUnwrap(StorageCleanup.currentAllocatedBytes(movie))
        let file = StorageFile(url: movie, logicalBytes: 8192, allocatedBytes: size, category: .video)
        XCTAssertNotNil(StorageCleanup.item(for: file, home: home))
        XCTAssertNotNil(StorageCleanup.blockedReason(home.appendingPathComponent("Applications/Editor.app/Contents/big.bin"), home: home))
        XCTAssertNotNil(StorageCleanup.blockedReason(home.appendingPathComponent("Library/Mail/data"), home: home))
        XCTAssertNotNil(StorageCleanup.blockedReason(URL(fileURLWithPath: "/usr/local/bin/tool"), home: home))
        try Data(repeating: 1, count: 100_000).write(to: movie)
        XCTAssertNil(StorageCleanup.item(for: file, home: home), "A file that changed since the scan isn't offered")
    }

    func testPackageUpgradeCommandsAndValidation() {
        let brew = URL(fileURLWithPath: "/opt/homebrew/bin/brew"), npm = URL(fileURLWithPath: "/opt/homebrew/bin/npm")
        func update(_ source: UpdateSource, _ package: String, _ available: String, cask: Bool = false, executable: URL?) -> AvailableUpdate {
            .init(name: package, package: package, installed: "1.0.0", available: available, source: source, executable: executable, isCask: cask, storeURL: nil)
        }
        XCTAssertEqual(PackageUpgrade(update(.homebrew, "git", "2.0", executable: brew))?.arguments, ["upgrade", "--formula", "git"])
        XCTAssertEqual(PackageUpgrade(update(.homebrew, "firefox", "140.0", cask: true, executable: brew))?.arguments, ["upgrade", "--cask", "firefox"])
        XCTAssertEqual(PackageUpgrade(update(.npm, "@deepseek-ai/dsh", "0.2.0", executable: npm))?.arguments, ["install", "--global", "@deepseek-ai/dsh@0.2.0"])
        XCTAssertNil(PackageUpgrade(update(.npm, "tool", "latest", executable: npm)), "npm updates pin an exact version")
        XCTAssertNil(PackageUpgrade(update(.homebrew, "--force", "2.0", executable: brew)))
        XCTAssertNil(PackageUpgrade(update(.appStore, "com.vendor.app", "2.0", executable: nil)))
        XCTAssertTrue(PackageProvider.versionMatches("1.2", "1.1, 1.2"))
        XCTAssertFalse(PackageProvider.versionMatches("1.3", "1.1, 1.2"))
    }

    func testBrewDependenciesReadsFormulaeAndCasks() {
        let data = Data(#"{"formulae":[{"name":"node","dependencies":["brotli","simdutf"]}],"casks":[{"token":"gcloud-cli","depends_on":{"formula":["python@3.13"],"cask":["docker"]}},{"token":"plain","depends_on":{}}]}"#.utf8)
        XCTAssertEqual(UpdateChecker.parseBrewDependencies(data), ["node": ["brotli", "simdutf"], "gcloud-cli": ["python@3.13", "docker"], "plain": []])
    }

    func testPermissionResetOnlyAcceptsBundleIdentifiers() {
        XCTAssertEqual(PermissionReset.arguments(bundleIdentifier: "com.vendor.App"), ["reset", "All", "com.vendor.App"])
        XCTAssertNil(PermissionReset.arguments(bundleIdentifier: "All"))
        XCTAssertNil(PermissionReset.arguments(bundleIdentifier: "com.vendor.app; rm"))
        XCTAssertNil(PermissionReset.arguments(bundleIdentifier: "-h"))
    }
}
