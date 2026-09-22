import Foundation
import Darwin

// Discover → explain → select → preview → revalidate → execute → report. See PLAN.md "Safety architecture".

/// Identity and mutation metadata read without following links. Used to detect swapped or edited files before removal.
public struct FileIdentity: Hashable, Codable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let mode: UInt32
    public let byteCount: Int64
    public let modificationSeconds: Int64
    public let modificationNanoseconds: Int64
    public let changeSeconds: Int64
    public let changeNanoseconds: Int64

    public static func read(_ url: URL) -> FileIdentity? {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) != S_IFLNK else { return nil }
        return .init(device: UInt64(UInt32(bitPattern: info.st_dev)), inode: UInt64(info.st_ino), mode: UInt32(info.st_mode),
                     byteCount: Int64(info.st_size), modificationSeconds: Int64(info.st_mtimespec.tv_sec),
                     modificationNanoseconds: Int64(info.st_mtimespec.tv_nsec), changeSeconds: Int64(info.st_ctimespec.tv_sec),
                     changeNanoseconds: Int64(info.st_ctimespec.tv_nsec))
    }
}

/// A bounded recursive fingerprint of names and lstat metadata. File contents are never read.
public struct RemovalSignature: Hashable, Sendable {
    public static let defaultLimit = 200_000
    public let digest: UInt64
    public let entryCount: Int
    /// False when the tree is larger than the review limit. The root and the folders directly inside it are still covered.
    public let coversDescendants: Bool
    let descendantLimit: Int

    public static func read(_ url: URL, limit: Int = RemovalSignature.defaultLimit) throws -> RemovalSignature? {
        guard FileIdentity.read(url) != nil else { return nil }
        var digest: UInt64 = 1_469_598_103_934_665_603
        var count = 0
        var failed = false

        func mix(_ value: UInt64) {
            var value = value
            for _ in 0..<8 {
                digest ^= value & 0xff
                digest &*= 1_099_511_628_211
                value >>= 8
            }
        }
        func include(_ item: URL, relativePath: String) -> Bool {
            var info = stat()
            guard lstat(item.path, &info) == 0 else { return false }
            for byte in relativePath.utf8 {
                digest ^= UInt64(byte)
                digest &*= 1_099_511_628_211
            }
            mix(UInt64(info.st_mode)); mix(UInt64(UInt32(bitPattern: info.st_dev))); mix(UInt64(info.st_ino))
            mix(UInt64(bitPattern: Int64(info.st_size))); mix(UInt64(bitPattern: Int64(info.st_blocks)))
            mix(UInt64(bitPattern: Int64(info.st_mtimespec.tv_sec))); mix(UInt64(bitPattern: Int64(info.st_mtimespec.tv_nsec)))
            mix(UInt64(bitPattern: Int64(info.st_ctimespec.tv_sec))); mix(UInt64(bitPattern: Int64(info.st_ctimespec.tv_nsec)))
            return true
        }

        guard include(url, relativePath: ".") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .init(digest: digest, entryCount: 1, coversDescendants: true, descendantLimit: limit)
        }
        // Always fingerprint the outer shell, even when the deep walk is cut short.
        let shell = try shellEntries(url)
        var shellPaths = Set<String>()
        for entry in shell {
            guard include(entry.url, relativePath: entry.relative) else { return nil }
            shellPaths.insert(entry.url.path)
        }
        if shell.count > limit {
            return .init(digest: digest, entryCount: shell.count + 1, coversDescendants: false, descendantLimit: limit)
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in
            failed = true
            return false
        }) else { return nil }
        for case let child as URL in enumerator {
            if shellPaths.contains(child.path) { continue }
            count += 1
            if count % 2_000 == 0 { try Task.checkCancellation() }
            guard shell.count + count <= limit else {
                return .init(digest: digest, entryCount: shell.count + 1, coversDescendants: false, descendantLimit: limit)
            }
            let relative = String(child.path.dropFirst(url.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard include(child, relativePath: relative) else { return nil }
        }
        return failed ? nil : .init(digest: digest, entryCount: shell.count + count + 1, coversDescendants: true, descendantLimit: limit)
    }

    /// The app itself, its immediate children, and one level below those. Deeper files stay on the bounded walk.
    private static func shellEntries(_ root: URL) throws -> [(url: URL, relative: String)] {
        let children = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var entries: [(url: URL, relative: String)] = []
        let budget = 8_000
        for child in children {
            try Task.checkCancellation()
            guard entries.count < budget else { break }
            entries.append((child, child.lastPathComponent))
            var info = stat()
            guard lstat(child.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { continue }
            let grandchildren = ((try? FileManager.default.contentsOfDirectory(at: child, includingPropertiesForKeys: nil, options: [])) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for grandchild in grandchildren {
                guard entries.count < budget else { break }
                entries.append((grandchild, child.lastPathComponent + "/" + grandchild.lastPathComponent))
            }
        }
        return entries
    }
}

public enum RemovalKind: String, CaseIterable, Sendable {
    case application = "App", package = "Package", preferences = "Settings & preferences", appData = "App data"
    case caches = "Caches & web data", logs = "Logs & saved state", launchItems = "Background items", homeSettings = "Home folder settings"
    case temporary = "Temporary files", developer = "Developer caches", file = "Files"
}

public enum MatchConfidence: String, Sendable { case exact, likely }

public struct PackageUninstall: Hashable, Sendable {
    public enum Kind: String, Sendable { case formula, cask, npm }
    public let runtime: PackageRuntime
    public let kind: Kind
    public let package: String

    public init?(runtime: PackageRuntime, kind: Kind, package: String) {
        guard runtime.manager == (kind == .npm ? .npm : .homebrew), PackageRequest.isValidName(package, manager: runtime.manager) else { return nil }
        self.runtime = runtime
        self.kind = kind
        self.package = package
    }

    public var arguments: [String] {
        switch kind {
        case .formula: return ["uninstall", "--formula", package]
        case .cask: return ["uninstall", "--cask", package]
        case .npm: return ["uninstall", "--global", package]
        }
    }
    public var displayCommand: String { ([runtime.executable.path] + arguments).joined(separator: " ") }
}

public enum RemovalAction: Hashable, Sendable {
    case trash
    case packageUninstall(PackageUninstall)
}

public struct RemovalItem: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let kind: RemovalKind
    public let confidence: MatchConfidence
    public let reason: String
    public let warning: String?
    /// Allocated bytes; nil when too large to measure quickly or not readable.
    public let size: Int64?
    public let identity: FileIdentity?
    /// Recursive review-time metadata. Missing only for package-manager-owned targets that are not moved directly.
    public let signature: RemovalSignature?
    /// Canonical parent folder at review time. Execution refuses the item if this changes.
    public let parentPath: String
    public let action: RemovalAction
    /// The app bundle or package itself. Everything else depends on it being removed first.
    public let isRequired: Bool

    public var selectedByDefault: Bool { isRequired || confidence == .exact }

    public init(url: URL, kind: RemovalKind, confidence: MatchConfidence, reason: String, warning: String?, size: Int64?,
                identity: FileIdentity?, signature: RemovalSignature? = nil, parentPath: String, action: RemovalAction, isRequired: Bool) {
        self.url = url
        self.kind = kind
        self.confidence = confidence
        self.reason = reason
        self.warning = warning
        self.size = size
        self.identity = identity
        self.signature = signature
        self.parentPath = parentPath
        self.action = action
        self.isRequired = isRequired
    }
}

public struct KeptItem: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let reason: String
}

public struct UninstallPlan: Sendable {
    public let name: String
    public let bundleIdentifier: String?
    public let items: [RemovalItem]
    public let kept: [KeptItem]
    /// Hard stops. Nothing can be removed while any exist.
    public let blockers: [String]
    public let createdAt: Date

    public var canProceed: Bool { blockers.isEmpty && items.contains(where: \.isRequired) }
    public var required: RemovalItem? { items.first(where: \.isRequired) }
}

public struct UninstallContext: Sendable {
    public let home: URL
    public let applications: [InstalledApplication]
    public let tools: [CommandLinePackage]
    public let protectedBundleIdentifiers: Set<String>
    public let homebrewPrefixes: [URL]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, applications: [InstalledApplication], tools: [CommandLinePackage],
                protectedBundleIdentifiers: Set<String>, homebrewPrefixes: [URL] = UpdateChecker.brewExecutables().map { $0.deletingLastPathComponent().deletingLastPathComponent() }) {
        self.home = home
        self.applications = applications
        self.tools = tools
        self.protectedBundleIdentifiers = protectedBundleIdentifiers
        self.homebrewPrefixes = homebrewPrefixes
    }

    var library: URL { home.appendingPathComponent("Library") }
}

public enum UninstallPlanner {
    struct Scope {
        let folder: String
        let kind: RemovalKind
        var matchesNames = false
        var warning: String?
    }

    static let scopes: [Scope] = [
        .init(folder: "Preferences", kind: .preferences),
        .init(folder: "Preferences/ByHost", kind: .preferences),
        .init(folder: "Application Support", kind: .appData, matchesNames: true),
        .init(folder: "Containers", kind: .appData, warning: "Everything this app saved in its sandbox, which can include documents you created in it."),
        .init(folder: "Group Containers", kind: .appData, warning: "Data an app shares with its extensions or other apps from the same developer."),
        .init(folder: "Application Scripts", kind: .appData),
        .init(folder: "Caches", kind: .caches, matchesNames: true),
        .init(folder: "HTTPStorages", kind: .caches),
        .init(folder: "WebKit", kind: .caches),
        .init(folder: "Cookies", kind: .caches),
        .init(folder: "Logs", kind: .logs, matchesNames: true),
        .init(folder: "Saved Application State", kind: .logs),
        .init(folder: "LaunchAgents", kind: .launchItems, warning: "A background item. If it is running, it stops after you log out or restart.")
    ]
    static let systemScopes = ["/Library/Application Support", "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools", "/Library/Preferences"]
    static let genericNames: Set<String> = ["app", "apps", "data", "cache", "caches", "logs", "support", "helper", "updater", "electron", "google", "microsoft", "apple", "adobe", "node", "npm", "config"]
    static let homeWarning = "Settings kept in your home folder. Command-line tools and other apps sometimes share these, and they can hold sign-in details."

    // MARK: Applications

    public static let partialReviewWarning = "This app has too many files to review one by one. Viper rechecks the app and the folders directly inside it. A change there cancels the removal. Files added deeper inside can still be removed with it."

    public static func plan(for app: InstalledApplication, context: UninstallContext, signatureLimit: Int = RemovalSignature.defaultLimit) throws -> UninstallPlan {
        var blockers: [String] = []
        let bundlePath = app.url.standardizedFileURL.path
        if app.isSystem || bundlePath.hasPrefix("/System/") { blockers.append("\(app.name) is part of macOS. Viper doesn’t remove protected system apps.") }
        if let id = app.bundleIdentifier, context.protectedBundleIdentifiers.contains(id) { blockers.append("Viper can’t uninstall itself.") }
        guard isInApplicationFolder(app.url, home: context.home) else {
            return .init(name: app.name, bundleIdentifier: app.bundleIdentifier, items: [], kept: [], blockers: blockers + ["\(app.name) isn’t in a supported application folder."], createdAt: Date())
        }
        guard let identity = FileIdentity.read(app.url) else {
            return .init(name: app.name, bundleIdentifier: app.bundleIdentifier, items: [], kept: [], blockers: blockers + ["\(app.name) couldn’t be read, or it is a link to an app stored elsewhere."], createdAt: Date())
        }
        guard let signature = try RemovalSignature.read(app.url, limit: signatureLimit) else {
            return .init(name: app.name, bundleIdentifier: app.bundleIdentifier, items: [], kept: [], blockers: blockers + ["\(app.name) couldn’t be completely reviewed. Viper won’t offer a partial removal."], createdAt: Date())
        }
        let reviewWarning = signature.coversDescendants ? nil : partialReviewWarning

        var items: [RemovalItem] = []
        var kept: [KeptItem] = []
        let parent = canonicalParent(app.url)
        switch homebrewCaskOwnership(for: app.url, prefixes: context.homebrewPrefixes) {
        case .ambiguous(let tokens):
            let list = tokens.sorted().joined(separator: ", ")
            blockers.append("More than one Homebrew cask claims \(app.name) (\(list)). Viper won’t choose one. Remove the right cask with Homebrew, then review again.")
            return .init(name: app.name, bundleIdentifier: app.bundleIdentifier, items: [], kept: [], blockers: blockers, createdAt: Date())
        case .unique(let cask):
            items.append(.init(url: app.url, kind: .package, confidence: .exact, reason: "Installed by Homebrew as the “\(cask.package)” cask, so Homebrew removes it.",
                               warning: reviewWarning, size: try allocatedSize(app.url), identity: identity, signature: signature, parentPath: parent, action: .packageUninstall(cask), isRequired: true))
        case .none:
            let writable = access(app.url.path, W_OK) == 0 && access(app.url.deletingLastPathComponent().path, W_OK) == 0
            let ownership = writable ? nil : "This app is owned by the system. macOS may ask for your password, or you can drag it to the Trash in Finder."
            let warning = [ownership, reviewWarning].compactMap { $0 }.joined(separator: " ")
            items.append(.init(url: app.url, kind: .application, confidence: .exact, reason: "The app itself.",
                               warning: warning.isEmpty ? nil : warning, size: try allocatedSize(app.url), identity: identity, signature: signature, parentPath: parent, action: .trash, isRequired: true))
        }

        let others = context.applications.filter { $0.url.standardizedFileURL.path != bundlePath }
        if let id = app.bundleIdentifier, let copy = others.first(where: { $0.bundleIdentifier?.lowercased() == id.lowercased() }) {
            // Another copy shares every setting. Only the selected bundle is offered.
            return .init(name: app.name, bundleIdentifier: id, items: items, kept: [.init(url: copy.url, reason: "Another copy of \(app.name) is installed here and uses the same settings, so related files are kept.")],
                         blockers: blockers, createdAt: Date())
        }
        let names = appNames(app)
        let otherNames = Set(others.flatMap(appNames)).union(context.tools.flatMap(toolNames))
        var seen = Set<String>()

        for scope in scopes {
            try Task.checkCancellation()
            let folder = context.library.appendingPathComponent(scope.folder)
            for entry in children(of: folder) {
                try Task.checkCancellation()
                let name = entry.lastPathComponent
                var confidence: MatchConfidence?
                var reason = ""
                if scope.folder == "Group Containers" {
                    let group = name.lowercased()
                    if let owner = others.first(where: { $0.applicationGroups.contains(group) }) {
                        kept.append(.init(url: entry, reason: "\(owner.name)’s signed entitlement uses this exact shared container."))
                        continue
                    }
                    if app.applicationGroups.contains(group) {
                        confidence = .exact
                        reason = "\(app.name)’s signed application-group entitlement names this exact shared container."
                    }
                }
                if let id = app.bundleIdentifier {
                    let (base, grouped) = identifierBase(name)
                    if confidence == nil, belongs(base, to: id) {
                        if let owner = others.first(where: { other in other.bundleIdentifier.map { $0.count > id.count && belongs(base, to: $0) } ?? false }) {
                            kept.append(.init(url: entry, reason: "Belongs to \(owner.name), which is still installed."))
                            continue
                        }
                        confidence = grouped ? .likely : .exact
                        reason = grouped ? "Shared group named after \(app.name)’s identifier (\(id))." : "Named with \(app.name)’s identifier (\(id))."
                    }
                }
                if confidence == nil, scope.matchesNames, names.contains(name.lowercased()) {
                    if otherNames.contains(name.lowercased()) {
                        kept.append(.init(url: entry, reason: "The name also matches another installed app or tool."))
                        continue
                    }
                    confidence = .likely
                    reason = "Folder has the same name as the app. Other software from the same developer can use it too."
                }
                guard let confidence, seen.insert(entry.path).inserted, let item = try makeItem(entry, kind: scope.kind, confidence: confidence, reason: reason, warning: scope.warning) else { continue }
                items.append(item)
            }
        }
        for variant in names.flatMap(dotVariants) {
            let entry = context.home.appendingPathComponent("." + variant)
            guard FileIdentity.read(entry) != nil, seen.insert(entry.path).inserted else { continue }
            if otherNames.contains(variant) {
                kept.append(.init(url: entry, reason: "The name also matches another installed app or tool."))
                continue
            }
            if let item = try makeItem(entry, kind: .homeSettings, confidence: .likely, reason: "Hidden folder in your home named after the app.", warning: homeWarning) { items.append(item) }
        }
        kept += systemItems(identifier: app.bundleIdentifier, names: names)
        return .init(name: app.name, bundleIdentifier: app.bundleIdentifier, items: items, kept: kept, blockers: blockers, createdAt: Date())
    }

    // MARK: Command-line tools

    public static func plan(for tool: CommandLinePackage, context: UninstallContext) throws -> UninstallPlan {
        var blockers: [String] = []
        if tool.isBundledWithRuntime { blockers.append("\(tool.name) ships with Node.js. Remove Node.js instead if you no longer need it.") }
        if tool.isDependency { blockers.append("Homebrew installed \(tool.name) for other formulae. Remove those first; Homebrew can then clean it up with “brew autoremove”.") }
        let kind: PackageUninstall.Kind = tool.source == .npm ? .npm : (tool.source == .homebrewCask ? .cask : .formula)
        guard let request = PackageUninstall(runtime: tool.runtime, kind: kind, package: tool.package) else {
            return .init(name: tool.name, bundleIdentifier: nil, items: [], kept: [], blockers: blockers + ["This package name can’t be passed safely to its package manager."], createdAt: Date())
        }
        let target = tool.location ?? tool.runtime.executable
        let prefix = tool.runtime.executable.deletingLastPathComponent().deletingLastPathComponent().path + "/"
        let npmTools = context.tools.filter { $0.source == .npm && !$0.isBundledWithRuntime && $0.runtime.executable.path.hasPrefix(prefix) }
        let runtimeWarning = tool.source == .homebrewFormula && (tool.package == "node" || tool.package.hasPrefix("node@")) && !npmTools.isEmpty
            ? "Global npm tools installed with this Node.js stop working: \(npmTools.map(\.name).joined(separator: ", "))." : nil
        var items = [RemovalItem(url: target, kind: .package, confidence: .exact, reason: "Removed by \(tool.runtime.manager.rawValue) with “\(request.displayCommand)”.",
                                 warning: runtimeWarning, size: tool.location.flatMap { try? allocatedSize($0) }, identity: nil, parentPath: canonicalParent(target),
                                 action: .packageUninstall(request), isRequired: true)]
        var kept: [KeptItem] = []
        let names = Set(toolNames(tool))
        let otherTools = context.tools.filter { $0.id != tool.id }
        let otherNames = Set(otherTools.flatMap(toolNames)).union(context.applications.flatMap(appNames))
        let candidates = names.flatMap { name -> [(URL, RemovalKind)] in
            [(context.home.appendingPathComponent("." + name), .homeSettings), (context.home.appendingPathComponent(".config/" + name), .homeSettings),
             (context.library.appendingPathComponent("Application Support/" + name), .appData), (context.library.appendingPathComponent("Caches/" + name), .caches),
             (context.library.appendingPathComponent("Logs/" + name), .logs)]
        }
        var seen = Set<String>()
        for (url, kind) in candidates where seen.insert(url.path).inserted {
            try Task.checkCancellation()
            guard FileIdentity.read(url) != nil else { continue }
            if otherNames.contains(url.lastPathComponent.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
                kept.append(.init(url: url, reason: "The name also matches another installed app or tool."))
                continue
            }
            if let item = try makeItem(url, kind: kind, confidence: .likely, reason: "Named after the “\(url.lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: ".")))” command.", warning: homeWarning) {
                items.append(item)
            }
        }
        return .init(name: tool.name, bundleIdentifier: nil, items: items, kept: kept, blockers: blockers, createdAt: Date())
    }

    // MARK: Matching helpers

    public static func identifierBase(_ name: String) -> (base: String, grouped: Bool) {
        var base = name
        for suffix in [".plist", ".savedState", ".binarycookies"] where base.hasSuffix(suffix) {
            base.removeLast(suffix.count)
            break
        }
        if base.hasPrefix("group.") { return (String(base.dropFirst(6)), true) }
        // Team-identifier prefix, e.g. 2DC432GLL2.com.vendor.app
        if base.range(of: "^[A-Z0-9]{10}\\.", options: .regularExpression) != nil { return (String(base.dropFirst(11)), true) }
        return (base, false)
    }

    public static func belongs(_ base: String, to identifier: String) -> Bool {
        let base = base.lowercased(), identifier = identifier.lowercased()
        guard identifier.split(separator: ".").count >= 2 else { return false }
        return base == identifier || base.hasPrefix(identifier + ".")
    }

    static func appNames(_ app: InstalledApplication) -> [String] {
        let bundle = Bundle(url: app.url)
        let values = [app.name, app.url.deletingPathExtension().lastPathComponent, bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
                      bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String].compactMap { $0.map(cleanName) }
        return Array(Set(values.filter { $0.count >= 3 && !genericNames.contains($0) && !$0.contains("/") }))
    }

    /// Some bundles pad their names with invisible direction marks.
    static func cleanName(_ name: String) -> String {
        String(String.UnicodeScalarView(name.unicodeScalars.filter { $0.properties.generalCategory != .format })).trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func toolNames(_ tool: CommandLinePackage) -> [String] {
        let values = tool.commands + [String(tool.package.split(separator: "/").last ?? Substring(tool.package))]
        return Array(Set(values.map { $0.lowercased() }.filter { $0.count >= 2 && !genericNames.contains($0) && !$0.contains("/") && !$0.hasPrefix(".") }))
    }

    static func dotVariants(_ name: String) -> [String] {
        Array(Set([name, name.replacingOccurrences(of: " ", with: "-"), name.replacingOccurrences(of: " ", with: "")]))
    }

    static func children(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    public static func makeItem(_ url: URL, kind: RemovalKind, confidence: MatchConfidence, reason: String, warning: String?) throws -> RemovalItem? {
        guard let identity = FileIdentity.read(url), let signature = try RemovalSignature.read(url), signature.coversDescendants else { return nil }
        let secrets = credentialHint(url)
        let combined = [warning, secrets].compactMap { $0 }.joined(separator: " ")
        return .init(url: url, kind: kind, confidence: confidence, reason: reason, warning: combined.isEmpty ? nil : combined,
                     size: try allocatedSize(url), identity: identity, signature: signature, parentPath: canonicalParent(url), action: .trash, isRequired: false)
    }

    /// Names only, one level deep. File contents are never read.
    static func credentialHint(_ url: URL) -> String? {
        let pattern = "(?i)(credential|token|secret|password|oauth|auth\\.json|\\.pem$|\\.key$|\\.env$)"
        let names = [url.lastPathComponent] + ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).prefix(300)
        guard let match = names.first(where: { $0.range(of: pattern, options: .regularExpression) != nil }) else { return nil }
        return "Contains “\(match)”, which looks like saved sign-in details."
    }

    static func systemItems(identifier: String?, names: [String]) -> [KeptItem] {
        systemScopes.flatMap { folder in
            children(of: URL(fileURLWithPath: folder)).filter { entry in
                let name = entry.lastPathComponent
                if let identifier, belongs(identifierBase(name).base, to: identifier) { return true }
                return folder == "/Library/Application Support" && names.contains(name.lowercased())
            }.map { KeptItem(url: $0, reason: "System-wide item. Removing it needs an administrator, which Viper doesn’t do yet.") }
        }
    }

    static func isInApplicationFolder(_ url: URL, home: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard url.pathExtension.lowercased() == "app" else { return false }
        return applicationRoots(home: home).contains { path.hasPrefix($0 + "/") }
    }

    static func applicationRoots(home: URL) -> [String] { ["/Applications", home.standardizedFileURL.path + "/Applications"] }

    public static func canonicalParent(_ url: URL) -> String { url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path }

    /// Folders whose direct children may be moved to the Trash.
    static func allowedParents(home: URL) -> Set<String> {
        let home = home.resolvingSymlinksInPath().standardizedFileURL
        let library = scopes.map { home.appendingPathComponent("Library").appendingPathComponent($0.folder).resolvingSymlinksInPath().path }
        return Set(library + [home.path, home.appendingPathComponent(".config").resolvingSymlinksInPath().path])
    }

    public static func allocatedSize(_ url: URL, limit: Int = 200_000) throws -> Int64? {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        if values.isSymbolicLink == true { return 0 }
        var total = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return total }
        var count = 0
        for case let child as URL in enumerator {
            count += 1
            if count % 2_000 == 0 { try Task.checkCancellation() }
            guard count <= limit else { return nil }
            let values = try? child.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { continue }
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    enum CaskOwnership: Equatable {
        case unique(PackageUninstall)
        case ambiguous([String])
        case none
    }

    /// A cask owns the app only when its declared `app` artifact is exactly the bundle filename.
    /// Mentions in caveats or conflicts do not count. More than one declaring cask is left for the user to choose.
    static func homebrewCaskOwnership(for app: URL, prefixes: [URL]) -> CaskOwnership {
        let bundleName = app.lastPathComponent
        var matches: [(brew: URL, token: String)] = []
        for prefix in prefixes {
            let brew = prefix.appendingPathComponent("bin/brew")
            guard FileManager.default.isExecutableFile(atPath: brew.path) else { continue }
            for cask in children(of: prefix.appendingPathComponent("Caskroom")) {
                let metadata = cask.appendingPathComponent(".metadata")
                guard let files = FileManager.default.enumerator(at: metadata, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
                var declared = Set<String>()
                for case let file as URL in files where ["json", "rb"].contains(file.pathExtension) {
                    guard (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max < 2_000_000,
                          let data = try? Data(contentsOf: file) else { continue }
                    declared.formUnion(declaredAppNames(in: data, pathExtension: file.pathExtension))
                }
                if declared.contains(bundleName) { matches.append((brew, cask.lastPathComponent)) }
            }
        }
        let tokens = Array(Set(matches.map(\.token))).sorted()
        guard let first = matches.first, tokens.count == 1, let request = PackageUninstall(runtime: .init(manager: .homebrew, executable: first.brew), kind: .cask, package: tokens[0]) else {
            return tokens.count > 1 ? .ambiguous(tokens) : .none
        }
        return .unique(request)
    }

    /// Bundle filenames declared by installed Homebrew casks. Used to tell those apps apart from software Viper cannot update.
    public static func homebrewAppNames(prefixes: [URL]) -> Set<String> {
        var names = Set<String>()
        for prefix in prefixes {
            for cask in children(of: prefix.appendingPathComponent("Caskroom")) {
                let metadata = cask.appendingPathComponent(".metadata")
                guard let files = FileManager.default.enumerator(at: metadata, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
                for case let file as URL in files where ["json", "rb"].contains(file.pathExtension) {
                    guard (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max < 2_000_000,
                          let data = try? Data(contentsOf: file) else { continue }
                    names.formUnion(declaredAppNames(in: data, pathExtension: file.pathExtension))
                }
            }
        }
        return names
    }

    /// App names from a cask artifact, not from caveats, conflicts, or other prose.
    static func declaredAppNames(in data: Data, pathExtension: String) -> Set<String> {
        switch pathExtension.lowercased() {
        case "json":
            guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
            var names = Set<String>()
            collectDeclaredApps(object, into: &names)
            return names
        case "rb":
            return rubyAppDirectives(String(decoding: data, as: UTF8.self))
        default:
            return []
        }
    }

    private static func collectDeclaredApps(_ value: Any, into names: inout Set<String>) {
        if let dict = value as? [String: Any] {
            if let apps = dict["app"] { names.formUnion(appTokens(apps)) }
            for (key, child) in dict where key == "artifacts" || child is [Any] {
                collectDeclaredApps(child, into: &names)
            }
        } else if let array = value as? [Any] {
            for child in array { collectDeclaredApps(child, into: &names) }
        }
    }

    private static func appTokens(_ value: Any) -> Set<String> {
        switch value {
        case let name as String where name.hasSuffix(".app") && !name.contains("/") && !name.contains("\\"):
            return [name]
        case let array as [Any]:
            return Set(array.flatMap { appTokens($0) })
        default:
            return []
        }
    }

    private static func rubyAppDirectives(_ source: String) -> Set<String> {
        let pattern = #"^\s*app\s+["']([^"']+\.app)["']"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        var names = Set<String>()
        for line in source.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard !text.trimmingCharacters(in: .whitespaces).hasPrefix("#") else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[capture])
            if !name.contains("/") && !name.contains("\\") { names.insert(name) }
        }
        return names
    }
}

// MARK: - Execution

public enum RemovalResult: Hashable, Sendable {
    case removed(trashURL: URL?)
    case skipped(String)
    case failed(String)

    public var succeeded: Bool { if case .removed = self { return true } else { return false } }
}

public struct RemovalOutcome: Identifiable, Hashable, Sendable {
    public var id: String { item.id }
    public let item: RemovalItem
    public var result: RemovalResult
    public var restored = false
}

public enum UninstallExecutor {
    public typealias Trasher = @Sendable (URL) throws -> URL?
    public typealias OutcomeRecorder = @Sendable (RemovalOutcome) async -> Bool

    public static let systemTrash: Trasher = { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    /// Fails closed: anything that changed since the review is left alone.
    public static func revalidate(_ item: RemovalItem, home: URL, bundleIdentifier: String?) -> String? {
        if case .packageUninstall = item.action, item.kind == .package, item.identity == nil { return nil }
        if let changed = identityChanged(item) { return changed }
        let parent = item.parentPath
        if item.isRequired {
            guard UninstallPlanner.isInApplicationFolder(URL(fileURLWithPath: parent).appendingPathComponent(item.url.lastPathComponent), home: home) else { return "The app is no longer in a supported application folder." }
            if let bundleIdentifier, Bundle(url: item.url)?.bundleIdentifier != bundleIdentifier { return "It changed since the review, so Viper left it alone. Review again to include it." }
        } else {
            guard UninstallPlanner.allowedParents(home: home).contains(parent), !["", ".", ".."].contains(item.url.lastPathComponent) else {
                return "This location isn’t one Viper removes files from."
            }
        }
        return nil
    }

    /// Same file, same place, still not a link. Shared by every removal in Viper.
    public static func identityChanged(_ item: RemovalItem) -> String? {
        let changed = "It changed since the review, so Viper left it alone. Scan again to include it."
        guard let identity = item.identity, let signature = item.signature,
              FileIdentity.read(item.url) == identity,
              (try? RemovalSignature.read(item.url, limit: signature.descendantLimit)) == signature,
              UninstallPlanner.canonicalParent(item.url) == item.parentPath else { return changed }
        return nil
    }

    /// The app or package goes first. If it isn’t removed, its settings and data are kept so a still-installed app keeps working.
    public static func execute(_ plan: UninstallPlan, selected: Set<String>, home: URL,
                               isRunning: @Sendable () async -> Bool,
                               mayContinue: @Sendable () async -> Bool = { true },
                               trash: Trasher = systemTrash,
                               uninstallPackage: @Sendable (PackageUninstall) async -> PackageProvider.UninstallOutcome = { await PackageProvider.uninstall($0) },
                               record: OutcomeRecorder = { _ in true },
                               progress: @Sendable (String) async -> Void = { _ in }) async -> [RemovalOutcome] {
        guard plan.canProceed, let required = plan.required else { return [] }
        let rest = plan.items.filter { !$0.isRequired && selected.contains($0.id) }
        var outcomes: [RemovalOutcome] = []

        await progress("Removing \(plan.name)…")
        let first: RemovalResult
        if !(await mayContinue()) {
            first = .skipped("Reviewed changes were turned off before removal started, so nothing was changed.")
        } else if await isRunning() {
            first = .skipped("\(plan.name) is open. Quit it and try again.")
        } else if let reason = revalidate(required, home: home, bundleIdentifier: plan.bundleIdentifier) {
            first = .skipped(reason)
        } else {
            switch required.action {
            case .trash: first = move(required, trash: trash)
            case .packageUninstall(let request):
                switch await uninstallPackage(request) {
                case .removed:
                    var info = stat()
                    if required.url.pathExtension.lowercased() == "app", lstat(required.url.path, &info) == 0 {
                        first = .failed("The package manager finished, but \(plan.name) is still on disk. Related files were kept.")
                    } else {
                        first = .removed(trashURL: nil)
                    }
                case .failed(let reason): first = .failed(reason)
                }
            }
        }
        let firstOutcome = RemovalOutcome(item: required, result: first)
        outcomes.append(firstOutcome)
        guard await record(firstOutcome) else {
            return outcomes + rest.map { .init(item: $0, result: .skipped("The recovery journal could not be updated, so Viper stopped before changing anything else.")) }
        }
        guard first.succeeded else {
            let skipped = rest.map { RemovalOutcome(item: $0, result: .skipped("Kept because \(plan.name) itself wasn’t removed.")) }
            for outcome in skipped { _ = await record(outcome) }
            return outcomes + skipped
        }
        for (index, item) in rest.enumerated() {
            await progress("Moving related files to the Trash (\(index + 1) of \(rest.count))…")
            let outcome: RemovalOutcome
            if !(await mayContinue()) {
                outcome = .init(item: item, result: .skipped("Reviewed changes were turned off, so this related item was kept."))
            } else if let reason = revalidate(item, home: home, bundleIdentifier: nil) {
                outcome = .init(item: item, result: .skipped(reason))
            } else {
                outcome = .init(item: item, result: move(item, trash: trash))
            }
            outcomes.append(outcome)
            guard await record(outcome) else { break }
        }
        return outcomes
    }

    public static func move(_ item: RemovalItem, trash: Trasher) -> RemovalResult {
        do { return .removed(trashURL: try trash(item.url)) }
        catch {
            let code = (error as NSError).code
            if [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(code) || (error as NSError).domain == NSPOSIXErrorDomain {
                return .failed("macOS didn’t allow this to be moved. Reveal it in Finder and drag it to the Trash; Finder can ask for your password.")
            }
            return .failed("It couldn’t be moved to the Trash: \(error.localizedDescription)")
        }
    }

    /// Puts trashed items back where they were, when both the Trash copy exists and the original spot is still free.
    public static func restore(_ outcomes: [RemovalOutcome], fileManager: FileManager = .default) -> [RemovalOutcome] {
        outcomes.map { outcome in
            var outcome = outcome
            guard case .removed(let trashURL?) = outcome.result, !outcome.restored else { return outcome }
            // lstat sees a symlink even when its target is missing. fileExists would follow it and look empty.
            var info = stat()
            guard lstat(trashURL.path, &info) == 0, lstat(outcome.item.url.path, &info) != 0 else { return outcome }
            do {
                try fileManager.moveItem(at: trashURL, to: outcome.item.url)
                outcome.restored = true
            } catch {}
            return outcome
        }
    }
}

// MARK: - Journal

public struct RemovalJournalEntry: Codable, Identifiable, Sendable {
    public struct Item: Codable, Sendable {
        public let path: String
        public let kind: String
        public let outcome: String
        public let trashPath: String?
        public let detail: String
    }
    public var id = UUID()
    public let date: Date
    public let name: String
    public let items: [Item]

    public init(date: Date = Date(), name: String, outcomes: [RemovalOutcome]) {
        self.date = date
        self.name = name
        items = outcomes.map { outcome in
            switch outcome.result {
            case .removed(let trash): return .init(path: outcome.item.url.path, kind: outcome.item.kind.rawValue, outcome: outcome.restored ? "Put back" : "Removed", trashPath: trash?.path, detail: "")
            case .skipped(let reason): return .init(path: outcome.item.url.path, kind: outcome.item.kind.rawValue, outcome: "Skipped", trashPath: nil, detail: reason)
            case .failed(let reason): return .init(path: outcome.item.url.path, kind: outcome.item.kind.rawValue, outcome: "Failed", trashPath: nil, detail: reason)
            }
        }
    }
}

public enum RemovalJournal {
    public static func load(from url: URL) -> [RemovalJournalEntry] {
        guard let data = try? Data(contentsOf: url), let entries = try? InstallJournal.decoder.decode([RemovalJournalEntry].self, from: data) else { return [] }
        return entries
    }

    public static func append(_ entry: RemovalJournalEntry, to url: URL, limit: Int = 100) throws {
        let entries = try JournalStore.existingArray(RemovalJournalEntry.self, from: url)
        try InstallJournal.write(Array((entries + [entry]).suffix(limit)), to: url)
    }
}

/// A write-ahead record of exactly what Viper intends to change and what happened to each item.
public struct RemovalTransaction: Codable, Identifiable, Sendable {
    public enum State: String, Codable, Equatable, Sendable { case inProgress, completed }
    public struct Target: Codable, Sendable {
        public let path: String
        public let kind: String
        public let identity: FileIdentity?
        public var outcome: String?
        public var trashPath: String?
        public var detail: String?
    }

    public let id: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public let name: String
    public var state: State
    public var targets: [Target]

    public init(name: String, items: [RemovalItem], now: Date = Date()) {
        id = UUID()
        createdAt = now
        updatedAt = now
        self.name = name
        state = .inProgress
        targets = items.map { .init(path: $0.url.path, kind: $0.kind.rawValue, identity: $0.identity, outcome: nil, trashPath: nil, detail: nil) }
    }
}

public enum RemovalTransactionJournal {
    public static func load(from url: URL) -> [RemovalTransaction] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? InstallJournal.decoder.decode([RemovalTransaction].self, from: data) else { return [] }
        return entries
    }

    static func write(_ transaction: RemovalTransaction, to url: URL, limit: Int = 100) throws {
        var entries = try JournalStore.existingArray(RemovalTransaction.self, from: url)
        if let index = entries.firstIndex(where: { $0.id == transaction.id }) { entries[index] = transaction }
        else { entries.append(transaction) }
        try InstallJournal.write(trimmed(entries, limit: limit), to: url)
    }

    /// Drops the oldest completed records first. An in-progress plan is never evicted.
    static func trimmed(_ entries: [RemovalTransaction], limit: Int) -> [RemovalTransaction] {
        guard entries.count > limit else { return entries }
        let inProgress = entries.filter { $0.state == .inProgress }
        let completed = entries.filter { $0.state != .inProgress }
        let keptCompleted = Set(completed.suffix(max(0, limit - inProgress.count)).map(\.id))
        let keptProgress = Set(inProgress.map(\.id))
        return entries.filter { keptProgress.contains($0.id) || keptCompleted.contains($0.id) }
    }
}

public actor RemovalTransactionRecorder {
    private let url: URL
    private var transaction: RemovalTransaction

    public init(name: String, items: [RemovalItem], url: URL) throws {
        self.url = url
        transaction = RemovalTransaction(name: name, items: items)
        try RemovalTransactionJournal.write(transaction, to: url)
    }

    public func record(_ outcome: RemovalOutcome) throws {
        guard let index = transaction.targets.firstIndex(where: { $0.path == outcome.item.url.path }) else { return }
        switch outcome.result {
        case .removed(let trashURL):
            transaction.targets[index].outcome = "Removed"
            transaction.targets[index].trashPath = trashURL?.path
            transaction.targets[index].detail = nil
        case .skipped(let reason):
            transaction.targets[index].outcome = "Skipped"
            transaction.targets[index].detail = reason
        case .failed(let reason):
            transaction.targets[index].outcome = "Failed"
            transaction.targets[index].detail = reason
        }
        transaction.updatedAt = Date()
        try RemovalTransactionJournal.write(transaction, to: url)
    }

    public func complete() throws {
        transaction.state = .completed
        transaction.updatedAt = Date()
        try RemovalTransactionJournal.write(transaction, to: url)
    }
}
