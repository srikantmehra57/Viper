import XCTest
@testable import ViperCore

final class UninstallerTests: XCTestCase {
    private var home: URL!
    private let manager = FileManager.default

    override func setUpWithError() throws {
        home = manager.temporaryDirectory.appendingPathComponent("viper-uninstall-\(UUID().uuidString)").resolvingSymlinksInPath()
        try manager.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? manager.removeItem(at: home) }

    @discardableResult
    private func make(_ path: String, directory: Bool = false, bytes: Int = 10) throws -> URL {
        let url = home.appendingPathComponent(path)
        if directory {
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: bytes).write(to: url)
        }
        return url
    }

    private func app(_ name: String, id: String?) throws -> InstalledApplication {
        let url = try make("Applications/\(name).app/Contents", directory: true).deletingLastPathComponent()
        var info: [String: Any] = ["CFBundleName": name, "CFBundleExecutable": name]
        if let id { info["CFBundleIdentifier"] = id }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
        return InstalledApplication(name: name, bundleIdentifier: id, version: "1.0", url: url, isSystem: false, isAppStore: false)
    }

    /// Moves into a fixture Trash so tests never touch the real one.
    private func fixtureTrash() throws -> UninstallExecutor.Trasher {
        let trash = try make(".FixtureTrash", directory: true)
        return { url in
            let destination = trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    private func context(_ apps: [InstalledApplication], tools: [CommandLinePackage] = []) -> UninstallContext {
        UninstallContext(home: home, applications: apps, tools: tools, protectedBundleIdentifiers: ["com.viper.app"], homebrewPrefixes: [])
    }

    func testFindsExactAndLikelyFilesAndKeepsOtherAppsData() throws {
        let target = try app("Editor", id: "com.vendor.editor")
        let helper = try app("Editor Helper", id: "com.vendor.editor.helper")
        try make("Library/Preferences/com.vendor.editor.plist")
        try make("Library/Preferences/ByHost/com.vendor.editor.1234-ABCD.plist")
        try make("Library/Caches/com.vendor.editor", directory: true)
        try make("Library/Caches/com.vendor.editor.ShipIt/update.zip", bytes: 4096)
        try make("Library/Containers/com.vendor.editor", directory: true)
        try make("Library/Group Containers/ABCDE12345.com.vendor.editor", directory: true)
        try make("Library/Application Support/Editor/settings.json")
        try make("Library/Application Support/com.vendor.editor.helper", directory: true)
        try make("Library/Application Support/com.vendor.editorial", directory: true)
        try make("Library/Preferences/com.other.app.plist")
        try make(".editor/credentials.yaml")
        try make("Library/Logs", directory: true)
        try manager.createSymbolicLink(at: home.appendingPathComponent("Library/Logs/com.vendor.editor"), withDestinationURL: home.appendingPathComponent("Documents"))

        let plan = try UninstallPlanner.plan(for: target, context: context([target, helper]))
        XCTAssertTrue(plan.canProceed)
        let byName = Dictionary(plan.items.map { ($0.url.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
        XCTAssertTrue(byName["Editor.app"]!.isRequired)
        for exact in ["com.vendor.editor.plist", "com.vendor.editor.1234-ABCD.plist", "com.vendor.editor", "com.vendor.editor.ShipIt"] {
            XCTAssertEqual(byName[exact]?.confidence, .exact, exact)
            XCTAssertTrue(byName[exact]?.selectedByDefault == true, exact)
        }
        XCTAssertTrue(plan.items.contains { $0.url.path.hasSuffix("Containers/com.vendor.editor") && $0.warning?.contains("documents") == true })
        XCTAssertEqual(byName["ABCDE12345.com.vendor.editor"]?.confidence, .likely)
        XCTAssertEqual(byName["Editor"]?.confidence, .likely)
        XCTAssertFalse(byName["Editor"]!.selectedByDefault)
        XCTAssertEqual(byName[".editor"]?.kind, .homeSettings)
        XCTAssertTrue(byName[".editor"]?.warning?.contains("credentials.yaml") == true)
        XCTAssertNil(byName["com.vendor.editorial"], "A longer identifier that merely shares a prefix is unrelated")
        XCTAssertNil(byName["com.other.app.plist"])
        XCTAssertFalse(plan.items.contains { $0.url.path.contains("/Logs/") }, "Symbolic links are never offered")
        XCTAssertTrue(plan.kept.contains { $0.url.lastPathComponent == "com.vendor.editor.helper" && $0.reason.contains("Editor Helper") })
        XCTAssertGreaterThanOrEqual(byName["com.vendor.editor.ShipIt"]?.size ?? 0, 4096)
    }

    func testBlocksSystemAppsViperAndAppsOutsideApplicationFolders() throws {
        let viper = try app("Viper", id: "com.viper.app")
        XCTAssertFalse(try UninstallPlanner.plan(for: viper, context: context([viper])).canProceed)
        let system = InstalledApplication(name: "Mail", bundleIdentifier: "com.apple.mail", version: "1", url: URL(fileURLWithPath: "/System/Applications/Mail.app"), isSystem: true, isAppStore: false)
        XCTAssertFalse(try UninstallPlanner.plan(for: system, context: context([system])).canProceed)
        let stray = try make("Downloads/Stray.app", directory: true)
        let outside = InstalledApplication(name: "Stray", bundleIdentifier: "com.stray", version: "1", url: stray, isSystem: false, isAppStore: false)
        XCTAssertFalse(try UninstallPlanner.plan(for: outside, context: context([outside])).canProceed)
    }

    func testDuplicateCopyKeepsSharedSettings() throws {
        let first = try app("Editor", id: "com.vendor.editor")
        let copy = InstalledApplication(name: "Editor", bundleIdentifier: "com.vendor.editor", version: "0.9", url: URL(fileURLWithPath: "/Applications/Editor.app"), isSystem: false, isAppStore: false)
        try make("Library/Preferences/com.vendor.editor.plist")
        let plan = try UninstallPlanner.plan(for: first, context: context([first, copy]))
        XCTAssertEqual(plan.items.count, 1)
        XCTAssertEqual(plan.kept.first?.url, copy.url)
    }

    func testExecutionMovesSelectedItemsAndCanPutThemBack() async throws {
        let target = try app("Editor", id: "com.vendor.editor")
        let preferences = try make("Library/Preferences/com.vendor.editor.plist")
        let support = try make("Library/Application Support/Editor/settings.json").deletingLastPathComponent()
        let plan = try UninstallPlanner.plan(for: target, context: context([target]))
        let selected = Set(plan.items.filter(\.selectedByDefault).map(\.id))
        let outcomes = await UninstallExecutor.execute(plan, selected: selected, home: home, isRunning: { false }, trash: try fixtureTrash())
        XCTAssertEqual(outcomes.count, 2)
        XCTAssertTrue(outcomes.allSatisfy { $0.result.succeeded })
        XCTAssertFalse(manager.fileExists(atPath: target.url.path))
        XCTAssertFalse(manager.fileExists(atPath: preferences.path))
        XCTAssertTrue(manager.fileExists(atPath: support.path), "Unselected likely matches stay")

        let restored = UninstallExecutor.restore(outcomes)
        XCTAssertTrue(restored.allSatisfy(\.restored))
        XCTAssertTrue(manager.fileExists(atPath: target.url.appendingPathComponent("Contents/Info.plist").path))
        XCTAssertTrue(manager.fileExists(atPath: preferences.path))
    }

    func testTurningOffReviewedChangesStopsBeforeAnythingMoves() async throws {
        let target = try app("Editor", id: "com.vendor.editor")
        let preferences = try make("Library/Preferences/com.vendor.editor.plist")
        let plan = try UninstallPlanner.plan(for: target, context: context([target]))
        let outcomes = await UninstallExecutor.execute(plan, selected: Set(plan.items.map(\.id)), home: home, isRunning: { false }, mayContinue: { false }, trash: try fixtureTrash())
        XCTAssertFalse(outcomes.contains { $0.result.succeeded })
        XCTAssertTrue(manager.fileExists(atPath: target.url.path))
        XCTAssertTrue(manager.fileExists(atPath: preferences.path))
    }

    func testPutBackRefusesWhenTheOriginalPathIsASymlink() async throws {
        let target = try app("Editor", id: "com.vendor.editor")
        let plan = try UninstallPlanner.plan(for: target, context: context([target]))
        let outcomes = await UninstallExecutor.execute(plan, selected: Set(plan.items.filter(\.isRequired).map(\.id)), home: home, isRunning: { false }, trash: try fixtureTrash())
        XCTAssertTrue(outcomes[0].result.succeeded)
        try Data("other".utf8).write(to: home.appendingPathComponent("decoy"))
        try manager.createSymbolicLink(at: target.url, withDestinationURL: home.appendingPathComponent("decoy"))
        let restored = UninstallExecutor.restore(outcomes)
        XCTAssertFalse(restored[0].restored)
        XCTAssertEqual(try manager.destinationOfSymbolicLink(atPath: target.url.path), home.appendingPathComponent("decoy").path)
    }

    func testRunningOrReplacedAppKeepsEverything() async throws {
        let target = try app("Editor", id: "com.vendor.editor")
        let preferences = try make("Library/Preferences/com.vendor.editor.plist")
        let plan = try UninstallPlanner.plan(for: target, context: context([target]))
        let all = Set(plan.items.map(\.id))

        let running = await UninstallExecutor.execute(plan, selected: all, home: home, isRunning: { true }, trash: try fixtureTrash())
        XCTAssertFalse(running.contains { $0.result.succeeded })
        XCTAssertTrue(manager.fileExists(atPath: preferences.path))

        // Replace the bundle with a different one at the same path.
        try manager.removeItem(at: target.url)
        _ = try app("Editor", id: "com.vendor.editor")
        let swapped = await UninstallExecutor.execute(plan, selected: all, home: home, isRunning: { false }, trash: try fixtureTrash())
        guard case .skipped = swapped[0].result else { return XCTFail("A replaced app must be skipped") }
        XCTAssertTrue(manager.fileExists(atPath: target.url.path))
        XCTAssertTrue(manager.fileExists(atPath: preferences.path), "Related files are kept when the app wasn't removed")
    }

    func testRevalidationRejectsSwappedFilesSymlinksAndMovedParents() throws {
        let target = try app("Editor", id: "com.vendor.editor")
        let cache = try make("Library/Caches/com.vendor.editor/data.bin")
        let plan = try UninstallPlanner.plan(for: target, context: context([target]))
        let item = try XCTUnwrap(plan.items.first { $0.url.lastPathComponent == "com.vendor.editor" })
        XCTAssertNil(UninstallExecutor.revalidate(item, home: home, bundleIdentifier: nil))

        try manager.removeItem(at: cache.deletingLastPathComponent())
        try manager.createSymbolicLink(at: item.url, withDestinationURL: home.appendingPathComponent("Documents"))
        XCTAssertNotNil(UninstallExecutor.revalidate(item, home: home, bundleIdentifier: nil))

        try manager.removeItem(at: item.url)
        try make("Library/Caches/com.vendor.editor", directory: true)
        XCTAssertNotNil(UninstallExecutor.revalidate(item, home: home, bundleIdentifier: nil), "A recreated folder is a different file")

        let outside = RemovalItem(url: home.appendingPathComponent("Documents/report.txt"), kind: .caches, confidence: .exact, reason: "", warning: nil, size: nil,
                                  identity: FileIdentity.read(try make("Documents/report.txt")), parentPath: home.appendingPathComponent("Documents").path, action: .trash, isRequired: false)
        XCTAssertNotNil(UninstallExecutor.revalidate(outside, home: home, bundleIdentifier: nil), "Only supported Library and settings folders are allowed")
    }

    func testRevalidationRejectsChangedDescendantMetadata() throws {
        let target = try app("Editor", id: "com.vendor.editor")
        let nested = try make("Library/Caches/com.vendor.editor/deep/data.bin", bytes: 32)
        let plan = try UninstallPlanner.plan(for: target, context: context([target]))
        let item = try XCTUnwrap(plan.items.first { $0.url.lastPathComponent == "com.vendor.editor" })
        XCTAssertNil(UninstallExecutor.revalidate(item, home: home, bundleIdentifier: nil))
        try manager.setAttributes([.modificationDate: Date().addingTimeInterval(30)], ofItemAtPath: nested.path)
        XCTAssertNotNil(UninstallExecutor.revalidate(item, home: home, bundleIdentifier: nil), "A descendant changed after review and must invalidate the whole target")
    }

    func testCommandLineToolPlanUsesPackageManagerAndOffersSettingsUnselected() async throws {
        let runtime = PackageRuntime(manager: .npm, executable: URL(fileURLWithPath: "/opt/homebrew/bin/npm"))
        let tool = CommandLinePackage(name: "@vendor/dsh", package: "@vendor/dsh", version: "1.0.0", summary: nil, source: .npm, runtime: runtime, commands: ["dsh"],
                                      location: nil, isDependency: false, isBundledWithRuntime: false)
        try make(".dsh/.credentials.yaml")
        let plan = try UninstallPlanner.plan(for: tool, context: context([], tools: [tool]))
        XCTAssertTrue(plan.canProceed)
        guard case .packageUninstall(let request) = plan.required?.action else { return XCTFail("Expected a package uninstall") }
        XCTAssertEqual(request.arguments, ["uninstall", "--global", "@vendor/dsh"])
        let settings = try XCTUnwrap(plan.items.first { $0.url.lastPathComponent == ".dsh" })
        XCTAssertFalse(settings.selectedByDefault)
        XCTAssertTrue(settings.warning?.contains(".credentials.yaml") == true)

        let failed = await UninstallExecutor.execute(plan, selected: Set(plan.items.map(\.id)), home: home, isRunning: { false }, trash: try fixtureTrash(),
                                                     uninstallPackage: { _ in .failed("nope") })
        XCTAssertEqual(failed[0].result, .failed("nope"))
        XCTAssertTrue(manager.fileExists(atPath: settings.url.path))

        let done = await UninstallExecutor.execute(plan, selected: Set(plan.items.map(\.id)), home: home, isRunning: { false }, trash: try fixtureTrash(),
                                                   uninstallPackage: { _ in .removed })
        XCTAssertTrue(done.allSatisfy { $0.result.succeeded })
        XCTAssertFalse(manager.fileExists(atPath: settings.url.path))
    }

    func testBundledAndDependencyToolsAreBlockedAndNamesValidated() throws {
        let npm = PackageRuntime(manager: .npm, executable: URL(fileURLWithPath: "/opt/homebrew/bin/npm"))
        let bundled = CommandLinePackage(name: "npm", package: "npm", version: "11", summary: nil, source: .npm, runtime: npm, commands: ["npm"], location: nil, isDependency: false, isBundledWithRuntime: true)
        XCTAssertFalse(try UninstallPlanner.plan(for: bundled, context: context([])).canProceed)
        let brew = PackageRuntime(manager: .homebrew, executable: URL(fileURLWithPath: "/opt/homebrew/bin/brew"))
        let dependency = CommandLinePackage(name: "libuv", package: "libuv", version: "1", summary: nil, source: .homebrewFormula, runtime: brew, commands: [], location: nil, isDependency: true, isBundledWithRuntime: false)
        XCTAssertFalse(try UninstallPlanner.plan(for: dependency, context: context([])).canProceed)
        XCTAssertNil(PackageUninstall(runtime: brew, kind: .formula, package: "--force"))
        XCTAssertNil(PackageUninstall(runtime: npm, kind: .formula, package: "git"))
        XCTAssertEqual(PackageUninstall(runtime: brew, kind: .cask, package: "firefox")?.arguments, ["uninstall", "--cask", "firefox"])
        XCTAssertTrue(PackageProvider.uninstallFailureSummary("Error: Refusing to uninstall /opt/homebrew/Cellar/libuv because it is required by node", status: 1, unknown: false).contains("still need"))
    }

    func testHomebrewCaskOwnershipRoutesAppThroughHomebrew() throws {
        let prefix = try make("brew", directory: true)
        let brew = try make("brew/bin/brew")
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        try Data(#"{"artifacts":[{"app":["Editor.app"]}]}"#.utf8).write(to: try make("brew/Caskroom/editor/.metadata/1.0/20260101/Casks/editor.json"))
        let target = try app("Editor", id: "com.vendor.editor")
        let plan = try UninstallPlanner.plan(for: target, context: UninstallContext(home: home, applications: [target], tools: [], protectedBundleIdentifiers: [], homebrewPrefixes: [prefix]))
        guard case .packageUninstall(let request) = plan.required?.action else { return XCTFail("Expected Homebrew to own the app") }
        XCTAssertEqual(request.arguments, ["uninstall", "--cask", "editor"])
        XCTAssertEqual(UninstallPlanner.homebrewAppNames(prefixes: [prefix]), ["Editor.app"])
    }

    func testJournalRecordsOutcomes() throws {
        let target = try app("Editor", id: "com.vendor.editor")
        let plan = try UninstallPlanner.plan(for: target, context: context([target]))
        let journal = home.appendingPathComponent("journal.json")
        try RemovalJournal.append(.init(name: "Editor", outcomes: [.init(item: plan.items[0], result: .failed("denied"))]), to: journal)
        let entries = RemovalJournal.load(from: journal)
        XCTAssertEqual(entries.first?.items.first?.outcome, "Failed")
        XCTAssertEqual(try manager.attributesOfItem(atPath: journal.path)[.posixPermissions] as? Int, 0o600)
    }

    func testWriteAheadRemovalTransactionPersistsPlanAndProgress() async throws {
        let target = try app("Editor", id: "com.vendor.editor")
        let plan = try UninstallPlanner.plan(for: target, context: context([target]))
        let journal = home.appendingPathComponent("transactions.json")
        let recorder = try RemovalTransactionRecorder(name: "Editor", items: plan.items, url: journal)
        var entries = RemovalTransactionJournal.load(from: journal)
        XCTAssertEqual(entries.first?.state, .inProgress)
        XCTAssertEqual(entries.first?.targets.first?.path, plan.items.first?.url.path)
        XCTAssertNil(entries.first?.targets.first?.outcome)

        try await recorder.record(.init(item: plan.items[0], result: .failed("denied")))
        try await recorder.complete()
        entries = RemovalTransactionJournal.load(from: journal)
        XCTAssertEqual(entries.first?.state, .completed)
        XCTAssertEqual(entries.first?.targets.first?.outcome, "Failed")
        XCTAssertEqual(try manager.attributesOfItem(atPath: journal.path)[.posixPermissions] as? Int, 0o600)
    }

    func testHomebrewCaskOwnershipIgnoresMentionsAndRefusesAmbiguousCasks() throws {
        let prefix = try make("brew", directory: true)
        let brew = try make("brew/bin/brew")
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        let caveats = #"{"caveats":"Remove \"Editor.app\" first","artifacts":[{"zap":[{"trash":"~/Library"}]}]}"#
        try Data(caveats.utf8).write(to: try make("brew/Caskroom/other/.metadata/config.json"))
        try Data("app \"Helper.app\"\n# app \"Editor.app\"\n".utf8).write(to: try make("brew/Caskroom/other/.metadata/other.rb"))
        try Data("app \"Editor.app\", target: \"Applications/Editor.app\"\n".utf8).write(to: try make("brew/Caskroom/editor/.metadata/editor.rb"))
        let target = try app("Editor", id: "com.vendor.editor")
        let context = UninstallContext(home: home, applications: [target], tools: [], protectedBundleIdentifiers: [], homebrewPrefixes: [prefix])
        let plan = try UninstallPlanner.plan(for: target, context: context)
        guard case .packageUninstall(let request) = plan.required?.action else { return XCTFail("Expected the cask that declares the app") }
        XCTAssertEqual(request.package, "editor")

        try Data(#"{"artifacts":[{"app":["Editor.app"]}]}"#.utf8).write(to: try make("brew/Caskroom/editor-beta/.metadata/editor-beta.json"))
        let blocked = try UninstallPlanner.plan(for: target, context: context)
        XCTAssertFalse(blocked.canProceed)
        XCTAssertTrue(blocked.blockers.contains { $0.contains("editor-beta") && $0.contains("editor") })
        XCTAssertNil(blocked.required)
    }

    func testRelatedFilesStayWhenACaskReportsRemovalButTheAppRemains() async throws {
        let prefix = try make("brew", directory: true)
        let brew = try make("brew/bin/brew")
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        try Data(#"{"artifacts":[{"app":["Editor.app"]}]}"#.utf8).write(to: try make("brew/Caskroom/editor/.metadata/editor.json"))
        let target = try app("Editor", id: "com.vendor.editor")
        try make("Library/Preferences/com.vendor.editor.plist")
        let context = UninstallContext(home: home, applications: [target], tools: [], protectedBundleIdentifiers: [], homebrewPrefixes: [prefix])
        let plan = try UninstallPlanner.plan(for: target, context: context)
        let kept = await UninstallExecutor.execute(plan, selected: Set(plan.items.map(\.id)), home: home, isRunning: { false }, trash: try fixtureTrash(),
                                                   uninstallPackage: { _ in .removed })
        XCTAssertFalse(kept[0].result.succeeded)
        XCTAssertTrue(manager.fileExists(atPath: home.appendingPathComponent("Library/Preferences/com.vendor.editor.plist").path))

        let removed = await UninstallExecutor.execute(plan, selected: Set(plan.items.map(\.id)), home: home, isRunning: { false }, trash: try fixtureTrash(),
                                                      uninstallPackage: { _ in
            try? FileManager.default.removeItem(at: target.url)
            return .removed
        })
        XCTAssertTrue(removed[0].result.succeeded)
        XCTAssertFalse(manager.fileExists(atPath: home.appendingPathComponent("Library/Preferences/com.vendor.editor.plist").path))
    }

    func testOversizedAppCanStillBeRemoved() throws {
        let target = try app("Editor", id: "com.vendor.editor")
        try make("Library/Preferences/com.vendor.editor.plist")
        let signature = try XCTUnwrap(RemovalSignature.read(target.url, limit: 1))
        XCTAssertFalse(signature.coversDescendants)
        try Data("changed".utf8).write(to: target.url.appendingPathComponent("Contents/Info.plist"))
        XCTAssertNotEqual(signature, try RemovalSignature.read(target.url, limit: 1), "A change inside the app invalidates a truncated review")
        let plan = try UninstallPlanner.plan(for: target, context: context([target]), signatureLimit: 1)
        XCTAssertTrue(plan.canProceed)
        XCTAssertEqual(plan.required?.signature?.coversDescendants, false)
        XCTAssertTrue(plan.required?.warning?.contains("too many files") == true)
        XCTAssertNotNil(plan.items.first { $0.url.lastPathComponent == "com.vendor.editor.plist" })
    }

    func testUnreadableJournalIsPreservedInsteadOfReplaced() async throws {
        let journal = home.appendingPathComponent("transactions.json")
        try Data("not-json".utf8).write(to: journal)
        XCTAssertThrowsError(try RemovalTransactionRecorder(name: "Editor", items: [], url: journal))
        XCTAssertFalse(manager.fileExists(atPath: journal.path))
        let preserved = try XCTUnwrap(try manager.contentsOfDirectory(at: home, includingPropertiesForKeys: nil).first { $0.lastPathComponent.contains("unreadable") })
        XCTAssertEqual(try Data(contentsOf: preserved), Data("not-json".utf8))
        let recorder = try RemovalTransactionRecorder(name: "Editor", items: [], url: journal)
        try await recorder.complete()
        XCTAssertEqual(RemovalTransactionJournal.load(from: journal).count, 1)
        XCTAssertEqual(try Data(contentsOf: preserved), Data("not-json".utf8))
    }

    func testInProgressTransactionsAreNotEvicted() {
        let unfinished = RemovalTransaction(name: "Old", items: [])
        var done = (0..<5).map { RemovalTransaction(name: "Done \($0)", items: []) }
        for index in done.indices { done[index].state = .completed }
        let kept = RemovalTransactionJournal.trimmed([unfinished] + done, limit: 3)
        XCTAssertEqual(kept.count, 3)
        XCTAssertTrue(kept.contains { $0.id == unfinished.id })
    }

    func testInterruptedTransactionStaysFlaggedForRecovery() async throws {
        let target = try app("Editor", id: "com.vendor.editor")
        let plan = try UninstallPlanner.plan(for: target, context: context([target]))
        let journal = home.appendingPathComponent("transactions.json")
        let recorder = try RemovalTransactionRecorder(name: "Editor", items: plan.items, url: journal)
        try await recorder.record(.init(item: plan.items[0], result: .removed(trashURL: nil)))
        // Never completed — simulates a crash mid-operation.
        let entries = RemovalTransactionJournal.load(from: journal)
        XCTAssertEqual(entries.first?.state, .inProgress)
        XCTAssertEqual(entries.first?.targets.first?.outcome, "Removed")
    }
}
