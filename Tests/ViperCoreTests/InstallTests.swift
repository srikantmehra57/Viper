import XCTest
@testable import ViperCore

final class CatalogTests: XCTestCase {
    func testBuiltInCatalogIsValidAndCoversEveryCategory() throws {
        let catalog = try Catalog.builtIn()
        XCTAssertEqual(catalog.schemaVersion, Catalog.supportedSchemaVersion)
        for category in CatalogCategory.allCases {
            XCTAssertTrue(catalog.apps.contains { $0.category == category }, "\(category) has no apps")
        }
        XCTAssertTrue(catalog.apps.contains { $0.install.method == .npm })
        XCTAssertTrue(catalog.apps.contains { !$0.install.method.isDirect })
    }

    func testCatalogRejectsUnsafeOrAmbiguousContent() throws {
        let unsafe: [(String, String)] = [
            ("tap", #""install":{"method":"homebrewCask","package":"someone/tap/app"}"#),
            ("flag", #""install":{"method":"homebrewCask","package":"--force"}"#),
            ("command", #""install":{"method":"homebrewCask","package":"app;rm"}"#),
            ("url-package", #""install":{"method":"homebrewCask","package":"app","url":"https://example.com"}"#),
            ("missing-package", #""install":{"method":"homebrewCask"}"#),
            ("app-store-web", #""install":{"method":"appStore","url":"https://example.com/app/id1"}"#),
            ("vendor-http", #""install":{"method":"vendor","url":"http://example.com"}"#)
        ]
        for (name, route) in unsafe {
            XCTAssertThrowsError(try Catalog.decode(catalogJSON(app: entryJSON(route: route))), "Accepted \(name)")
        }
        XCTAssertThrowsError(try Catalog.decode(catalogJSON(app: entryJSON(route: #""install":{"method":"npm","package":"tool@1.0.0"}"#, kind: "commandLine"))))
        XCTAssertThrowsError(try Catalog.decode(catalogJSON(app: entryJSON(route: #""install":{"method":"homebrewFormula","package":"tool"}"#, kind: "app"))), "Kind must match the package type")
        XCTAssertThrowsError(try Catalog.decode(catalogJSON(app: entryJSON(website: "http://example.com"))))
        XCTAssertThrowsError(try Catalog.decode(catalogJSON(app: entryJSON() + "," + entryJSON())), "Duplicate identities")
        XCTAssertThrowsError(try Catalog.decode(catalogJSON(app: entryJSON(), collectionApps: #"["missing"]"#)))
        XCTAssertThrowsError(try Catalog.decode(catalogJSON(app: entryJSON(), schema: 99)))
        XCTAssertNoThrow(try Catalog.decode(catalogJSON(app: entryJSON(), collectionApps: #"["sample"]"#)))
    }

    func testPackageRequestsUseExactArgumentArrays() throws {
        let brew = PackageRuntime(manager: .homebrew, executable: URL(fileURLWithPath: "/opt/homebrew/bin/brew"))
        let npm = PackageRuntime(manager: .npm, executable: URL(fileURLWithPath: "/opt/homebrew/bin/npm"))
        XCTAssertEqual(PackageRequest(method: .homebrewCask, package: "firefox", runtime: brew)?.installArguments, ["install", "--cask", "firefox"])
        XCTAssertEqual(PackageRequest(method: .homebrewFormula, package: "python@3.13", runtime: brew)?.installArguments, ["install", "--formula", "python@3.13"])
        XCTAssertEqual(PackageRequest(method: .npm, package: "@vendor/tool", runtime: npm)?.installArguments, ["install", "--global", "@vendor/tool"])
        XCTAssertNil(PackageRequest(method: .npm, package: "tool", runtime: brew), "Runtime must match the provider")
        XCTAssertNil(PackageRequest(method: .appStore, package: "tool", runtime: brew))
        for name in ["--cask", "user/tap/app", "../x", "app name", "App;x", "git+https://x"] {
            XCTAssertNil(PackageRequest(method: .homebrewCask, package: name, runtime: brew), name)
        }
    }

    private func entryJSON(route: String = #""install":{"method":"homebrewCask","package":"sample"}"#, kind: String = "app", website: String = "https://example.com") -> String {
        #"{"id":"sample","name":"Sample","publisher":"Vendor","summary":"Does things.","category":"utilities","kind":"\#(kind)","website":"\#(website)","pricing":"free",\#(route)}"#
    }

    private func catalogJSON(app: String, collectionApps: String? = nil, schema: Int = 1) -> Data {
        let collections = collectionApps.map { #"[{"id":"c","name":"C","summary":"S","apps":\#($0)}]"# } ?? "[]"
        return Data(#"{"schemaVersion":\#(schema),"catalogVersion":"1","reviewedAt":"2026-09-15","apps":[\#(app)],"collections":\#(collections)}"#.utf8)
    }
}

final class PackageProviderTests: XCTestCase {
    func testBrewCaskMetadataDetectsInstallerPackagesArchitectureAndMinimumMacOS() throws {
        let zoom = Data(#"{"formulae":[],"casks":[{"token":"zoom","version":"7.1.5","deprecated":false,"disabled":false,"depends_on":{},"artifacts":[{"uninstall":[]},{"pkg":["zoomusInstallerFull.pkg"]},{"postflight_steps":null},{"zap":[]}]}]}"#.utf8)
        let metadata = try PackageProvider.parseBrewInfo(zoom, key: "homebrewCask:zoom", cask: true)
        XCTAssertTrue(metadata.requiresAdministrator)
        XCTAssertTrue(metadata.appNames.isEmpty)

        let studio = Data(#"{"formulae":[],"casks":[{"token":"lm-studio","version":"0.4.24,1","deprecated":false,"disabled":false,"depends_on":{"macos":{">=":["12"]},"arch":[{"type":"arm","bits":64}],"formula":["jq"]},"artifacts":[{"app":["LM Studio.app"]},{"app":["Other.app",{"target":"Renamed.app"}]}]}]}"#.utf8)
        let arm = try PackageProvider.parseBrewInfo(studio, key: "homebrewCask:lm-studio", cask: true)
        XCTAssertTrue(arm.appleSiliconOnly)
        XCTAssertFalse(arm.requiresAdministrator)
        XCTAssertEqual(arm.minimumMacOS, "12")
        XCTAssertEqual(arm.appNames, ["LM Studio.app", "Other.app"])
        XCTAssertEqual(arm.dependencies, ["jq"])
        XCTAssertEqual(arm.canonicalName, "lm-studio")
    }

    func testBrewFormulaMetadataAndDisabledState() throws {
        let data = Data(#"{"formulae":[{"name":"gh","versions":{"stable":"2.80.0","head":"HEAD","bottle":true},"dependencies":["go"],"deprecated":false,"disabled":true}],"casks":[]}"#.utf8)
        let metadata = try PackageProvider.parseBrewInfo(data, key: "homebrewFormula:gh", cask: false)
        XCTAssertEqual(metadata.version, "2.80.0")
        XCTAssertEqual(metadata.dependencies, ["go"])
        XCTAssertTrue(metadata.disabled)
        XCTAssertThrowsError(try PackageProvider.parseBrewInfo(Data(#"{"formulae":[],"casks":[]}"#.utf8), key: "k", cask: true))
    }

    func testNpmViewHandlesEnginesScriptsMissingAndFailures() throws {
        let data = Data(#"{"name":"@anthropic-ai/claude-code","version":"2.1.272","engines":{"node":">=22.0.0"},"scripts":{"postinstall":"node install.js"}}"#.utf8)
        let metadata = try PackageProvider.parseNpmView(data, key: "npm:@anthropic-ai/claude-code")
        XCTAssertEqual(metadata.nodeRequirement, ">=22.0.0")
        XCTAssertTrue(metadata.runsInstallScripts)
        XCTAssertFalse(try PackageProvider.parseNpmView(Data(#"{"name":"a","version":"1","scripts":{"test":"x"}}"#.utf8), key: "npm:a").runsInstallScripts)
        XCTAssertFalse(try PackageProvider.parseNpmView(Data(#"{"error":{"code":"E404","summary":"Not Found"}}"#.utf8), key: "npm:x").found)
        XCTAssertThrowsError(try PackageProvider.parseNpmView(Data(#"{"error":{"code":"ENOTFOUND"}}"#.utf8), key: "npm:x"), "Offline is not the same as missing")
    }

    func testNpmRegistryMustBeExplicitAndSecure() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("viper-registry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let executable = folder.appendingPathComponent("npm")
        func write(_ registry: String) throws {
            try Data("#!/bin/sh\nprintf '%s\\n' '\(registry)'\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }
        let runtime = PackageRuntime(manager: .npm, executable: executable)
        try write("https://registry.npmjs.org/")
        let registry = try await PackageProvider.npmRegistry(for: runtime)
        XCTAssertEqual(registry.absoluteString, "https://registry.npmjs.org/")
        try write("http://registry.example.com/")
        do {
            _ = try await PackageProvider.npmRegistry(for: runtime)
            XCTFail("An insecure remote registry must be rejected")
        } catch {}
    }

    func testInstalledPackageListsRejectUnexpectedNames() throws {
        let brew = PackageProvider.parseBrewList(Data("firefox 155.0.1\ngit 2.54.0 2.55.0\n--bad 1\nca-certificates 2026-08-13\n".utf8))
        XCTAssertEqual(brew, ["firefox": "155.0.1", "git": "2.55.0", "ca-certificates": "2026-08-13"])
        let npm = try PackageProvider.parseNpmList(Data(#"{"name":"lib","dependencies":{"npm":{"version":"11.19.1"},"@deepseek-ai/dsh":{"version":"0.1.5-rc.1"},"Bad Name":{"version":"1"}}}"#.utf8))
        XCTAssertEqual(npm, ["npm": "11.19.1", "@deepseek-ai/dsh": "0.1.5-rc.1"])
        XCTAssertEqual(try PackageProvider.parseNpmList(Data(#"{"name":"lib"}"#.utf8)), [:])
    }

    func testCommandRunnerKeepsDiagnosticsSeparateFromStructuredOutput() async throws {
        let output = try await CommandRunner.run(URL(fileURLWithPath: "/bin/ls"), arguments: ["/viper-missing-path"], includeErrors: true)
        XCTAssertNotEqual(output.status, 0)
        XCTAssertTrue(output.data.isEmpty)
        XCTAssertFalse(output.errors.isEmpty)
        let quiet = try await CommandRunner.run(URL(fileURLWithPath: "/bin/ls"), arguments: ["/viper-missing-path"])
        XCTAssertTrue(quiet.errors.isEmpty)
    }

    func testFailureSummariesAreSpecificWithoutOverclaiming() {
        XCTAssertTrue(PackageProvider.failureSummary("Error: It seems there is already an App at '/Applications/Firefox.app'.").contains("didn’t replace"))
        XCTAssertTrue(PackageProvider.failureSummary("npm error code EACCES").contains("permissions"))
        XCTAssertTrue(PackageProvider.failureSummary("curl: (6) Could not resolve host: example.com").contains("connection"))
        XCTAssertTrue(PackageProvider.failureSummary("==> Downloading https://example.com\nError: something odd").contains("See details"))
    }

    func testNodeRequirementSupportsOnlyUnambiguousRanges() {
        XCTAssertEqual(InstallPlanner.nodeSatisfies(">=22.0.0", version: "26.8.2"), true)
        XCTAssertEqual(InstallPlanner.nodeSatisfies(">= 22", version: "20.11.1"), false)
        XCTAssertNil(InstallPlanner.nodeSatisfies("^18 || ^20", version: "20.0.0"))
        XCTAssertNil(InstallPlanner.nodeSatisfies(">=18 <21", version: "20.0.0"))
    }
}

final class InstallPlannerTests: XCTestCase {
    private let brew = PackageRuntime(manager: .homebrew, executable: URL(fileURLWithPath: "/opt/homebrew/bin/brew"))
    private let intelBrew = PackageRuntime(manager: .homebrew, executable: URL(fileURLWithPath: "/usr/local/bin/brew"))
    private let npm = PackageRuntime(manager: .npm, executable: URL(fileURLWithPath: "/opt/homebrew/bin/npm"))

    private func entry(_ id: String, method: InstallMethod = .homebrewCask, package: String? = nil, url: URL? = nil, bundles: [String]? = nil,
                       commands: [String]? = nil, minimum: String? = nil, arm: Bool? = nil) -> CatalogEntry {
        CatalogEntry(id: id, name: id.capitalized, publisher: "Vendor", summary: "Summary", category: .utilities,
                     kind: method == .homebrewCask || !method.isDirect ? .app : .commandLine, website: URL(string: "https://example.com")!,
                     pricing: .free, requiresAccount: false, install: InstallRoute(method: method, package: method.isDirect ? (package ?? id) : nil, url: url),
                     bundleIdentifiers: bundles, appNames: nil, commands: commands, minimumMacOS: minimum, appleSiliconOnly: arm, notes: nil)
    }

    private func environment(homebrew: [PackageRuntime]? = nil, npm npmRuntimes: [PackageRuntime]? = nil, casks: [String: String] = [:], formulae: [String: String] = [:],
                             npmPackages: [String: String] = [:], apps: [InstalledApplication] = [], commands: [String: [String]] = [:],
                             system: SystemProfile = .init(macOSVersion: "15.1.0", appleSilicon: true), node: String? = "22.1.0") -> InstallEnvironment {
        let brews = homebrew ?? [brew]
        let npms = npmRuntimes ?? [npm]
        var packages = InstalledPackages()
        for runtime in brews { packages.casks[runtime.id] = casks; packages.formulae[runtime.id] = formulae }
        for runtime in npms { packages.npm[runtime.id] = npmPackages }
        return InstallEnvironment(system: system, homebrew: brews, npm: npms, packages: packages, applications: apps, commands: commands,
                                  nodeVersions: node.map { [npm.id: $0] } ?? [:], checks: [])
    }

    private func metadata(_ key: String, name: String, version: String = "1.0", admin: Bool = false, found: Bool = true, deprecated: Bool = false,
                          minimum: String? = nil, node: String? = nil, dependencies: [String] = []) -> PackageMetadata {
        PackageMetadata(key: key, found: found, canonicalName: found ? name : nil, version: version, minimumMacOS: minimum, appleSiliconOnly: false, appNames: [],
                        requiresAdministrator: admin, deprecated: deprecated, disabled: false, dependencies: dependencies, nodeRequirement: node,
                        runsInstallScripts: false, checkedAt: Date())
    }

    private func app(_ name: String, bundle: String) -> InstalledApplication {
        InstalledApplication(name: name, bundleIdentifier: bundle, version: "3.0", url: URL(fileURLWithPath: "/Applications/\(name).app"), isSystem: false, isAppStore: false)
    }

    func testInstalledStateAndOtherSourcesAreNeverReinstalled() {
        let firefox = entry("firefox", bundles: ["org.mozilla.firefox"])
        XCTAssertEqual(InstallPlanner.status(for: firefox, in: environment(casks: ["firefox": "155.0"]), metadata: nil), .installed(source: brew.label, version: "155.0"))
        guard case .installedElsewhere(_, let url) = InstallPlanner.status(for: firefox, in: environment(apps: [app("Firefox", bundle: "org.mozilla.firefox")]), metadata: nil) else {
            return XCTFail("A manually installed app must not be replaced")
        }
        XCTAssertEqual(url?.lastPathComponent, "Firefox.app")
        let claude = entry("claude-code", method: .npm, package: "@anthropic-ai/claude-code", commands: ["claude"])
        guard case .installedElsewhere = InstallPlanner.status(for: claude, in: environment(commands: ["claude": ["/Users/me/.local/bin/claude"]]), metadata: nil) else {
            return XCTFail("An existing command from another source must not be replaced")
        }
        XCTAssertEqual(InstallPlanner.status(for: claude, in: environment(npmPackages: ["@anthropic-ai/claude-code": "2.0"], commands: ["claude": ["/opt/homebrew/bin/claude"]]), metadata: nil),
                       .installed(source: npm.label, version: "2.0"))
    }

    func testPrerequisitesAndHomebrewPrefixes() {
        XCTAssertEqual(InstallPlanner.status(for: entry("firefox"), in: environment(homebrew: []), metadata: nil), .needsSetup(.homebrew))
        XCTAssertEqual(InstallPlanner.status(for: entry("tool", method: .npm), in: environment(npm: []), metadata: nil), .needsSetup(.npm))
        guard case .needsAttention = InstallPlanner.status(for: entry("firefox"), in: environment(homebrew: [intelBrew]), metadata: nil) else {
            return XCTFail("A non-native Homebrew prefix must not be used silently")
        }
        var unreadable = environment()
        unreadable = InstallEnvironment(system: unreadable.system, homebrew: [brew], npm: [npm], packages: InstalledPackages(), applications: [], commands: [:], nodeVersions: [:], checks: [])
        guard case .needsAttention = InstallPlanner.status(for: entry("firefox"), in: unreadable, metadata: nil) else {
            return XCTFail("Unknown inventory must not be treated as not installed")
        }
    }

    func testMetadataBlocksRenamedMissingAdministratorAndIncompatiblePackages() {
        let env = environment()
        let zoom = entry("zoom")
        guard case .unavailable = InstallPlanner.status(for: zoom, in: env, metadata: metadata("homebrewCask:zoom", name: "zoom-app")) else { return XCTFail("Renamed") }
        guard case .unavailable = InstallPlanner.status(for: zoom, in: env, metadata: metadata("homebrewCask:zoom", name: "zoom", found: false)) else { return XCTFail("Missing") }
        guard case .needsAttention = InstallPlanner.status(for: zoom, in: env, metadata: metadata("homebrewCask:zoom", name: "zoom", admin: true)) else { return XCTFail("Admin") }
        guard case .needsAttention = InstallPlanner.status(for: zoom, in: env, metadata: metadata("homebrewCask:zoom", name: "zoom", deprecated: true)) else { return XCTFail("Deprecated") }
        guard case .incompatible = InstallPlanner.status(for: zoom, in: env, metadata: metadata("homebrewCask:zoom", name: "zoom", minimum: "26")) else { return XCTFail("macOS") }
        guard case .incompatible = InstallPlanner.status(for: entry("studio", arm: true), in: environment(homebrew: [intelBrew], system: .init(macOSVersion: "15.0", appleSilicon: false)), metadata: nil) else {
            return XCTFail("Architecture")
        }
        let agent = entry("agent", method: .npm)
        guard case .incompatible = InstallPlanner.status(for: agent, in: environment(node: "20.0.0"), metadata: metadata("npm:agent", name: "agent", node: ">=22")) else { return XCTFail("Node") }
        XCTAssertEqual(InstallPlanner.status(for: agent, in: environment(node: nil), metadata: metadata("npm:agent", name: "agent", node: ">=22")), .available, "Unknown Node versions are disclosed, not guessed")
        XCTAssertEqual(InstallPlanner.status(for: zoom, in: env, metadata: metadata("homebrewCask:zoom", name: "zoom")), .available)
    }

    func testExternalRoutesAreOpenedNotInstalled() {
        let xcode = entry("xcode", method: .appStore, url: URL(string: "macappstore://itunes.apple.com/app/id497799835"), bundles: ["com.apple.dt.Xcode"])
        XCTAssertEqual(InstallPlanner.status(for: xcode, in: environment(), metadata: nil), .external(.appStore))
        XCTAssertEqual(InstallPlanner.status(for: xcode, in: environment(apps: [app("Xcode", bundle: "com.apple.dt.Xcode")]), metadata: nil), .installed(source: "Application folder", version: "3.0"))
        let plan = InstallPlanner.plan(selection: [xcode], environment: environment(), metadata: [:], npmRuntime: nil)
        guard case .skip = plan.first?.decision else { return XCTFail("External apps are never queued") }
    }

    func testPlanRequiresFreshMetadataDeduplicatesAndOrdersFormulaeFirst() throws {
        let firefox = entry("firefox")
        let git = entry("git", method: .homebrewFormula)
        let agent = entry("agent", method: .npm)
        let duplicate = entry("firefox-copy", package: "firefox")
        let unverified = entry("vlc")
        let data = [
            "homebrewCask:firefox": metadata("homebrewCask:firefox", name: "firefox", version: "155.0"),
            "homebrewFormula:git": metadata("homebrewFormula:git", name: "git", dependencies: ["gettext", "pcre2"]),
            "npm:agent": metadata("npm:agent", name: "agent")
        ]
        let plan = InstallPlanner.plan(selection: [agent, firefox, firefox, git, duplicate, unverified], environment: environment(formulae: ["pcre2": "10"]), metadata: data, npmRuntime: nil)
        XCTAssertEqual(plan.map(\.id), ["git", "firefox", "firefox-copy", "vlc", "agent"])
        guard case .install(let gitRequest) = plan[0].decision else { return XCTFail("Git should install") }
        XCTAssertEqual(gitRequest.runtime, brew)
        XCTAssertTrue(plan[0].details.contains { $0.contains("gettext") && !$0.contains("pcre2") })
        guard case .install = plan[1].decision else { return XCTFail("Firefox should install") }
        XCTAssertEqual(plan[1].version, "155.0")
        guard case .skip = plan[2].decision else { return XCTFail("Duplicate package mapping must be skipped") }
        guard case .blocked = plan[3].decision else { return XCTFail("Unverified packages must not install") }
        guard case .install(let npmRequest) = plan[4].decision else { return XCTFail("npm package should install") }
        XCTAssertEqual(npmRequest.runtime, npm)
    }
}

final class InstallJournalTests: XCTestCase {
    func testJournalKeepsNewestEntriesAndCacheRoundTrips() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ViperJournal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = folder.appendingPathComponent("install-journal.json")
        for index in 1...5 {
            try InstallJournal.append(.init(appID: "app\(index)", appName: "App", source: "Homebrew", package: "app", runtime: "/opt/homebrew/bin/brew", outcome: "Installed", version: "1", detail: ""), to: journal, limit: 3)
        }
        XCTAssertEqual(InstallJournal.load(from: journal).map(\.appID), ["app3", "app4", "app5"])
        let attributes = try FileManager.default.attributesOfItem(atPath: journal.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertTrue(InstallJournal.load(from: folder.appendingPathComponent("missing.json")).isEmpty)

        let cacheURL = folder.appendingPathComponent("catalog-metadata.json")
        let item = try PackageProvider.parseNpmView(Data(#"{"name":"a","version":"1.2"}"#.utf8), key: "npm:a")
        try CatalogMetadataCache(refreshedAt: Date(), items: ["npm:a": item]).save(to: cacheURL)
        XCTAssertEqual(CatalogMetadataCache.load(from: cacheURL).items["npm:a"]?.version, "1.2")
        try Data("not json".utf8).write(to: cacheURL)
        XCTAssertNil(CatalogMetadataCache.load(from: cacheURL).refreshedAt, "Corrupt cache data is ignored")
    }
}

final class ExternalLinkTests: XCTestCase {
    func testOnlySecureWebAndAppStoreLinksOpen() {
        XCTAssertEqual(ExternalLink.webOrAppStore("https://example.com/app")?.host, "example.com")
        XCTAssertEqual(ExternalLink.webOrAppStore("macappstore://itunes.apple.com/app/id497799835")?.path, "/app/id497799835")
        XCTAssertNil(ExternalLink.webOrAppStore("http://example.com"))
        XCTAssertNil(ExternalLink.webOrAppStore("https://user:secret@example.com"))
        XCTAssertNil(ExternalLink.webOrAppStore("file:///etc/passwd"))
        XCTAssertNil(ExternalLink.webOrAppStore("macappstore://evil.example/app/id1"))
        XCTAssertNil(ExternalLink.webOrAppStore("macappstore://itunes.apple.com/app/not-a-number"))
        XCTAssertNotNil(ExternalLink.systemSettings("com.apple.preference.security?Privacy_Camera"))
        XCTAssertNotNil(ExternalLink.systemSettings("com.apple.Notifications-Settings.extension"))
        XCTAssertNil(ExternalLink.systemSettings("https://example.com"))
        XCTAssertNil(ExternalLink.systemSettings("com.apple.preference.security?Privacy_Camera&open=file"))
    }
}
