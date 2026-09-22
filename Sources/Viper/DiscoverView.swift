import AppKit
import SwiftUI
import ViperCore

struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var category: CatalogCategory?
    @State private var statusFilter = StatusFilter.all
    @State private var compatibleOnly = false
    @State private var detail: CatalogEntry?
    @AppStorage("viper.discover.layout") private var layout = CatalogLayout.grid

    enum StatusFilter: Hashable { case all, notInstalled, installed }
    enum CatalogLayout: String { case grid, list }

    var body: some View {
        PageHeading("Discover & Install", subtitle: model.catalog.map(heroDetail)) {
            Button { model.detectInstallations() } label: { Label("Check installed", systemImage: "app.badge.checkmark") }
                .buttonStyle(GlowButtonStyle(.secondary, compact: true)).disabled(model.detectingInstalls || model.installing || model.checkingUpdates || model.refreshingCatalog || model.reviewTask != nil)
                .help("Looks for apps and tools already on this Mac.")
            if model.refreshingCatalog {
                Button("Cancel") { model.cancelCatalogRefresh() }.buttonStyle(GlowButtonStyle(.danger, compact: true))
            } else {
                Button { model.refreshCatalogMetadata() } label: { Label("Check availability", systemImage: "arrow.clockwise") }
                    .buttonStyle(GlowButtonStyle(compact: true)).disabled(model.installEnvironment == nil || model.detectingInstalls || model.installing || model.checkingUpdates || model.reviewTask != nil)
                    .help("Asks Homebrew and npm for current versions and restrictions. Never installs anything.")
            }
        }
            .task { model.loadDiscover() }
            .sheet(item: $detail) { entry in CatalogDetailSheet(entry: entry).environmentObject(model) }
            .sheet(isPresented: Binding(get: { model.installReview != nil }, set: { if !$0 { model.cancelReview() } })) {
                InstallReviewSheet().environmentObject(model)
            }
            .sheet(item: Binding(get: { model.prerequisite }, set: { model.prerequisite = $0 })) { manager in
                PrerequisiteSheet(manager: manager).environmentObject(model)
            }
        if let catalog = model.catalog {
            if model.refreshingCatalog || model.detectingInstalls {
                HStack(spacing: 10) {
                    ScanPulse(color: Palette.lavender)
                    Text(model.refreshingCatalog ? model.catalogProgress : "Checking installed apps, Homebrew, and npm…").font(.system(size: 12))
                }
            }
            setupCard
            if !model.installQueue.isEmpty { InstallQueueCard() }
            CollectionCarousel(catalog: catalog)
            filters
            if !model.installSelection.isEmpty { selectionBar(catalog) }
            results(catalog)
            if !model.installJournal.isEmpty { history }
        } else if let message = model.catalogMessage {
            EmptyPanel(icon: "exclamationmark.triangle", title: "The catalog couldn’t be loaded.", detail: message + " No software was installed.")
        }
    }

    private func heroDetail(_ catalog: Catalog) -> String {
        let reviewed = (try? Date(catalog.reviewedAt, strategy: .iso8601.year().month().day())).map { $0.formatted(date: .abbreviated, time: .omitted) } ?? catalog.reviewedAt
        let checked: String
        if let refreshed = model.catalogMetadata.refreshedAt {
            checked = Date().timeIntervalSince(refreshed) > 86_400
                ? "availability stale — check again"
                : "availability checked \(RelativeDateTimeFormatter().localizedString(for: refreshed, relativeTo: Date()))"
        } else {
            checked = "availability not checked"
        }
        return "\(catalog.apps.count) curated apps · reviewed \(reviewed) · \(checked)"
    }

    @ViewBuilder private var setupCard: some View {
        if let environment = model.installEnvironment {
            let missing = [environment.homebrew.isEmpty ? PackageManager.homebrew : nil, environment.npm.isEmpty ? PackageManager.npm : nil].compactMap { $0 }
            let failed = environment.checks.contains { !$0.succeeded }
            if !missing.isEmpty || failed {
                Card(color: Palette.peach) {
                    ForEach(missing, id: \.self) { manager in
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox").font(.system(size: 18)).frame(width: 42, height: 42).glowTile(Palette.peach, radius: 12)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(manager == .homebrew ? "Homebrew isn’t set up yet" : "npm isn’t set up yet").font(.system(size: 14, weight: .semibold))
                                Text(manager == .homebrew ? "Most apps here install with Homebrew. You can still browse and open App Store or publisher links." : "Command-line AI agents and JavaScript tools install with npm, which comes with Node.js.")
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Button("How to set up") { model.prerequisite = manager }.buttonStyle(GlowButtonStyle(.secondary, compact: true))
                        }
                    }
                    Disclosure("What Viper checked") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(environment.checks) { check in
                                Label("\(check.name): \(check.detail)", systemImage: check.succeeded ? "checkmark.circle" : "exclamationmark.circle")
                            }
                        }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 6)
                    }.font(.system(size: 12))
                }
            } else if environment.npm.count > 1 {
                Card {
                    HStack {
                        Text("npm tools install into").font(.system(size: 12, weight: .semibold))
                        ViperSelect(title: "npm runtime", selection: Binding(get: { model.npmRuntime?.id ?? "" }, set: { model.npmRuntimeID = $0 }),
                                    options: environment.npm.map { ($0.location + ($0.isTerminalDefault == true ? "  ·  Terminal default" : ""), $0.id) }).frame(width: 320)
                        Spacer()
                    }.disabled(model.installing)
                }
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SearchField(placeholder: "Search apps, publishers, or tools", text: $search)
                ViperSelect(title: "Status", selection: $statusFilter, options: [("All apps", .all), ("Not installed", .notInstalled), ("Installed", .installed)]).frame(width: 150)
                Toggle("Compatible only", isOn: $compatibleOnly).toggleStyle(ViperCheckboxStyle()).fixedSize()
                LayoutToggle(layout: $layout)
            }
            FlowLayout(spacing: 8, lineSpacing: 8) {
                FilterChip(title: "All categories", selected: category == nil) { category = nil }
                ForEach(CatalogCategory.allCases) { item in
                    FilterChip(title: item.title, selected: category == item) { category = category == item ? nil : item }
                }
            }
        }
    }

    private func selectionBar(_ catalog: Catalog) -> some View {
        Card(color: Palette.mint) {
            HStack(spacing: 14) {
                HStack(spacing: -10) {
                    ForEach(model.installSelection.prefix(5).compactMap(catalog.entry)) { entry in CatalogIcon(entry: entry, appURL: nil, size: 32) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(model.installSelection.count) selected").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
                        .contentTransition(.numericText()).animation(Motion.snappy, value: model.installSelection.count)
                    Text(model.installSelection.compactMap { catalog.entry($0)?.name }.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer()
                Button("Clear") { model.installSelection.removeAll() }.buttonStyle(GlowButtonStyle(.secondary, compact: true))
                Button { model.reviewInstall() } label: { Label("Review selected", systemImage: "checklist") }
                    .buttonStyle(GlowButtonStyle()).disabled(model.installReview != nil || model.installing || model.checkingUpdates || model.refreshingCatalog || model.detectingInstalls)
            }
        }
    }

    private func results(_ catalog: Catalog) -> some View {
        let entries = catalog.apps.filter { entry in
            let status = model.status(for: entry)
            let matchesSearch = search.isEmpty || [entry.name, entry.publisher, entry.summary, entry.install.package ?? ""].contains { $0.localizedCaseInsensitiveContains(search) }
            let matchesStatus: Bool
            switch statusFilter {
            case .all: matchesStatus = true
            case .installed: matchesStatus = status?.isInstalled == true
            case .notInstalled: matchesStatus = status?.isInstalled == false
            }
            let compatible: Bool
            if case .incompatible = status { compatible = false } else { compatible = true }
            return matchesSearch && matchesStatus && (category == nil || entry.category == category) && (!compatibleOnly || compatible)
        }
        return VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "\(entries.count) \(entries.count == 1 ? "APP" : "APPS")\(category.map { " · \($0.title.uppercased())" } ?? "")")
            if entries.isEmpty {
                EmptyPanel(icon: "magnifyingglass", title: "No matching apps.", detail: "Try another search, category, or filter. This catalog is a curated selection, not every Mac app.")
            } else if layout == .grid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    ForEach(entries) { entry in CatalogCard(entry: entry) { detail = entry } }
                }
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(entries) { entry in
                        CatalogRow(entry: entry) { detail = entry }
                    }
                }
                .padding(6)
                .background(GlassBackground())
            }
        }
    }

    private var history: some View {
        Card {
            Disclosure("Install history") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.installJournal.suffix(20).reversed()) { item in
                        HStack(alignment: .top) {
                            Text(item.date.formatted(date: .abbreviated, time: .shortened)).frame(width: 150, alignment: .leading)
                            Text("\(item.appName) · \(item.outcome)\(item.version.map { " · \($0)" } ?? "")").fontWeight(.semibold)
                            Text("\(item.source) “\(item.package)”").foregroundStyle(Palette.muted)
                            Spacer()
                        }
                    }
                    Text("The history records outcomes only. Viper can’t roll back installs; use the Uninstaller or the package manager to remove software.").foregroundStyle(Palette.muted)
                }.font(.system(size: 11)).padding(.top, 8)
            }.font(.system(size: 13, weight: .semibold))
        }
    }
}

extension PackageManager: Identifiable {
    public var id: String { rawValue }
}

private struct LayoutToggle: View {
    @Binding var layout: DiscoverView.CatalogLayout
    var body: some View {
        HStack(spacing: 2) {
            option(.grid, icon: "square.grid.2x2", label: "Grid")
            option(.list, icon: "list.bullet", label: "List")
        }
        .padding(3)
        .fixedSize()
        .background(SegmentTrack(radius: 11))
    }
    @Namespace private var indicator
    private func option(_ value: DiscoverView.CatalogLayout, icon: String, label: String) -> some View {
        Button { withAnimation(Motion.snappy) { layout = value } } label: {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).frame(width: 34, height: 30)
                .foregroundStyle(layout == value ? Palette.ink : Palette.muted)
                .background {
                    if layout == value {
                        GlassThumb(radius: 8).matchedGeometryEffect(id: "layout", in: indicator)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("\(label) view").accessibilityLabel("\(label) view").accessibilityAddTraits(layout == value ? .isSelected : [])
    }
}

// MARK: - Collections

private struct CollectionCarousel: View {
    @EnvironmentObject private var model: AppModel
    let catalog: Catalog
    @State private var index = 0
    private let tints = [Palette.mint, Palette.lavender, Palette.blue, Palette.peach, Palette.yellow]

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Starter collections").font(.system(size: 19, weight: .semibold)).foregroundStyle(Palette.titleGradient)
                    Text("Nothing is selected until you add it.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Spacer()
                    arrow("chevron.left", enabled: index > 0) { move(-1, proxy) }
                    arrow("chevron.right", enabled: index < catalog.collections.count - 1) { move(1, proxy) }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(catalog.collections.enumerated()), id: \.element.id) { offset, collection in
                            card(collection, tint: tints[offset % tints.count]).id(collection.id)
                        }
                    }.padding(.bottom, 4).padding(.trailing, 2)
                }
            }
        }
    }

    private func move(_ step: Int, _ proxy: ScrollViewProxy) {
        index = min(max(0, index + step), catalog.collections.count - 1)
        withAnimation(Motion.smooth) { proxy.scrollTo(catalog.collections[index].id, anchor: .leading) }
    }

    private func arrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
        }
        .buttonStyle(GlowButtonStyle(.secondary, compact: true)).disabled(!enabled)
        .accessibilityLabel(icon == "chevron.left" ? "Previous collection" : "Next collection")
    }

    private func card(_ collection: StarterCollection, tint: Color) -> some View {
        let entries = collection.apps.compactMap(catalog.entry)
        let addable = entries.filter { !model.installSelection.contains($0.id) && model.status(for: $0)?.isSelectable == true }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: -10) {
                ForEach(entries.prefix(6)) { entry in CatalogIcon(entry: entry, appURL: model.installedAppURL(for: entry), size: 42) }
                if entries.count > 6 {
                    Text("+\(entries.count - 6)").font(.system(size: 12, weight: .bold)).frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.elevated))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                }
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name).font(.system(size: 16, weight: .semibold))
                Text(collection.summary).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2).frame(height: 32, alignment: .topLeading)
            }
            Text(entries.map(\.name).joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
            HStack {
                Button { model.addCollection(collection) } label: { Label(addable.isEmpty ? "All added" : "Add \(addable.count)", systemImage: addable.isEmpty ? "checkmark" : "plus") }
                    .buttonStyle(GlowButtonStyle(addable.isEmpty ? .secondary : .primary, compact: true)).disabled(addable.isEmpty)
                    .accessibilityLabel(addable.isEmpty ? "\(collection.name): nothing new to add" : "Add \(addable.count) apps from \(collection.name)")
                Spacer()
                Eyebrow(text: "\(entries.count) APPS")
            }
        }
        .padding(20).frame(width: 330, alignment: .leading)
        .background(GlassBackground(tint: tint, radius: 22))
        .padding(.vertical, 12)
    }
}

// MARK: - Cards and rows

private struct CatalogCard: View {
    @EnvironmentObject private var model: AppModel
    let entry: CatalogEntry
    let showDetails: () -> Void
    @State private var hovering = false

    var body: some View {
        let status = model.status(for: entry)
        let selected = model.installSelection.contains(entry.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                CatalogIcon(entry: entry, appURL: model.installedAppURL(for: entry), size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(entry.publisher).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Palette.onAccent).frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white))
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Selected")
                }
            }
            Text(entry.summary).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 12)
            MetaTags(entry: entry).padding(.top, 10)
            GlowDivider().padding(.vertical, 14)
            HStack(spacing: 8) {
                StatusBadge(entry: entry, status: status, queued: model.queueItem(for: entry)?.state, progress: model.queueItem(for: entry)?.progress, stale: model.catalogAvailabilityIsStale(entry))
                Spacer(minLength: 6)
                CatalogPrimaryAction(entry: entry, status: status, selected: selected, compact: true, showDetails: showDetails)
            }
            if let item = model.queueItem(for: entry), item.state == .installing {
                ActivityBar(fraction: item.progress?.overallFraction ?? 0.04, height: 5)
                    .padding(.top, 12)
                    .transition(.opacity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassBackground(tint: selected ? Palette.mint : (hovering ? Palette.catalog(entry.category) : nil), selected: selected))
        .offset(y: hovering ? -2 : 0)
        .animation(Motion.snappy, value: hovering)
        .animation(Motion.snappy, value: selected)
        .contentShape(Rectangle())
        .onTapGesture(perform: showDetails)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Show details", showDetails)
    }
}

private struct CatalogRow: View {
    @EnvironmentObject private var model: AppModel
    let entry: CatalogEntry
    let showDetails: () -> Void
    @State private var hovering = false

    var body: some View {
        let status = model.status(for: entry)
        let selected = model.installSelection.contains(entry.id)
        HStack(spacing: 14) {
            CatalogIcon(entry: entry, appURL: model.installedAppURL(for: entry), size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(entry.publisher).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Text(entry.summary).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.tail)
            }.padding(.trailing, 16).frame(maxWidth: .infinity, alignment: .leading)
            MetaTags(entry: entry, showPrice: false).frame(width: 215, alignment: .leading)
            StatusBadge(entry: entry, status: status, queued: model.queueItem(for: entry)?.state, progress: model.queueItem(for: entry)?.progress, stale: model.catalogAvailabilityIsStale(entry)).frame(width: 165, alignment: .leading)
            CatalogPrimaryAction(entry: entry, status: status, selected: selected, compact: true, showDetails: showDetails).frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .rowHighlight(hovering: hovering, selected: selected)
        .contentShape(Rectangle())
        .onTapGesture(perform: showDetails)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Show details", showDetails)
    }
}

private struct MetaTags: View {
    let entry: CatalogEntry
    var showPrice = true
    var body: some View {
        HStack(spacing: 6) {
            tag(entry.kind == .app ? "App" : "Command line", icon: entry.kind == .app ? "macwindow" : "terminal")
            tag(entry.install.method.sourceLabel == "Publisher website" ? "Website" : entry.install.method.sourceLabel, icon: nil)
            if showPrice && entry.pricing != .unverified { tag(entry.pricing == .freemium ? "Free + paid" : entry.pricing.label, icon: nil) }
        }
    }
    private func tag(_ text: String, icon: String?) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .semibold)) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .fixedSize()
    }
}

/// Loads reviewed catalog icons shipped in the app bundle. There is no runtime download.
@MainActor private enum CatalogIconStore {
    private static var cache: [String: NSImage] = [:]
    private static var missing = Set<String>()

    static func image(_ id: String) -> NSImage? {
        if let image = cache[id] { return image }
        guard !missing.contains(id) else { return nil }
        var url = Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "CatalogIcons")
        #if DEBUG
        // `swift run` has no app bundle; use the reviewed icons from the source tree.
        if url == nil {
            let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            url = source.appendingPathComponent("Resources/CatalogIcons/\(id).png")
        }
        #endif
        guard let url, let image = NSImage(contentsOf: url) else { missing.insert(id); return nil }
        cache[id] = image
        return image
    }
}

struct CatalogIcon: View {
    let entry: CatalogEntry
    let appURL: URL?
    var size: CGFloat = 46

    var body: some View {
        let radius = size * 0.24
        Group {
            if let appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path)).resizable().interpolation(.high).scaledToFit().padding(size * 0.02)
                    .background(Color.white)
            } else if let image = CatalogIconStore.image(entry.id) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(size * 0.08)
                    .background(Color.white)
            } else {
                Text(String(entry.name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.44, weight: .black, design: .rounded)).foregroundStyle(Palette.catalog(entry.category))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient(colors: [Palette.catalog(entry.category).opacity(0.3), Palette.elevated], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(Color.black.opacity(0.35)).offset(y: 1.5))
        .accessibilityHidden(true)
    }
}

private struct StatusBadge: View {
    let entry: CatalogEntry
    let status: CatalogStatus?
    let queued: InstallState?
    var progress: OperationProgress? = nil
    var stale = false

    var body: some View {
        let (icon, text, color) = summary
        HStack(spacing: 5) {
            if queued == .installing { ScanPulse(color: color).scaleEffect(0.6).frame(width: 12, height: 12) } else { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
        .help(stale ? "Availability was checked more than a day ago. Check again before adding it." : (status.map { StatusLine.describe($0, entry: entry).1 } ?? ""))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.map { StatusLine.describe($0, entry: entry).1 } ?? text)
    }

    private var summary: (String, String, Color) {
        switch queued {
        case .queued: return ("clock", "Queued", Palette.lavender)
        case .installing:
            guard let progress else { return ("arrow.down.circle", "Starting…", Palette.lavender) }
            if progress.phase == .downloading, let percent = progress.downloadFraction {
                return ("arrow.down.circle", "Downloading \(Int((percent * 100).rounded()))%", Palette.lavender)
            }
            if progress.phase == .downloading, let bytes = progress.downloadedBytes {
                return ("arrow.down.circle", "Downloading · " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file), Palette.lavender)
            }
            return ("arrow.down.circle", progress.phase.title + "…", Palette.lavender)
        default: break
        }
        switch status {
        case nil: return ("hourglass", "Checking…", Palette.slate)
        case .available: return stale ? ("clock", "Checked earlier", Palette.yellow) : ("checkmark.seal", "Ready to install", Palette.mint)
        case .installed(_, let version): return ("checkmark.circle.fill", version.isEmpty ? "Installed" : "Installed · \(version)", Palette.blue)
        case .installedElsewhere: return ("checkmark.circle", "Installed separately", Palette.blue)
        case .needsSetup(let manager): return ("shippingbox", "Needs \(manager.rawValue)", Palette.yellow)
        case .unavailable: return ("xmark.octagon", "Unavailable", Palette.peach)
        case .incompatible: return ("nosign", "Not compatible", Palette.peach)
        case .needsAttention: return ("exclamationmark.triangle", "Needs attention", Palette.yellow)
        case .external(let method): return ("arrow.up.right.square", method == .appStore ? "App Store" : "Publisher site", Palette.slate)
        }
    }
}

enum StatusLine {
    static func describe(_ status: CatalogStatus, entry: CatalogEntry) -> (String, String) {
        switch status {
        case .available: return ("checkmark.seal", "Ready to install with \(entry.install.method.sourceLabel)")
        case .installed(let source, let version): return ("checkmark.circle.fill", "Installed\(version.isEmpty ? "" : " · \(version)") · \(source)")
        case .installedElsewhere(let reason, _): return ("checkmark.circle", reason)
        case .needsSetup(let manager): return ("shippingbox", "Needs \(manager.rawValue) set up first")
        case .unavailable(let reason): return ("xmark.octagon", reason)
        case .incompatible(let reason): return ("nosign", reason)
        case .needsAttention(let reason): return ("exclamationmark.triangle", reason)
        case .external(let method): return ("arrow.up.right.square", method == .appStore ? "Get it from the App Store" : "Download from the publisher’s website")
        }
    }
}

private struct CatalogPrimaryAction: View {
    @EnvironmentObject private var model: AppModel
    let entry: CatalogEntry
    let status: CatalogStatus?
    let selected: Bool
    var compact = false
    var showDetails: (() -> Void)?

    var body: some View {
        if let state = model.queueItem(for: entry)?.state, !state.isFinished {
            EmptyView()
        } else {
            switch status {
            case nil:
                EmptyView()
            case .available:
                if model.catalogAvailabilityIsStale(entry) {
                    Button(compact ? "Check" : "Check again") { model.refreshCatalogMetadata() }
                        .buttonStyle(GlowButtonStyle(.secondary, compact: compact))
                        .accessibilityLabel("Check availability for \(entry.name) again before adding it")
                } else {
                    Button { model.toggleSelection(entry) } label: { Label(selected ? "Added" : "Add", systemImage: selected ? "checkmark" : "plus") }
                        .buttonStyle(GlowButtonStyle(selected ? .primary : .secondary, compact: compact))
                        .accessibilityLabel(selected ? "Remove \(entry.name) from selection" : "Add \(entry.name) to selection")
                }
            case .installed, .installedElsewhere:
                if let url = model.installedAppURL(for: entry) {
                    Button { model.openApplication(url) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                        .buttonStyle(GlowButtonStyle(.secondary, compact: compact)).accessibilityLabel("Open \(entry.name)")
                }
            case .needsSetup(let manager):
                Button(compact ? "Set up" : "Set up \(manager.rawValue)") { model.prerequisite = manager }
                    .buttonStyle(GlowButtonStyle(.danger, compact: compact)).accessibilityLabel("Set up \(manager.rawValue)")
            case .external(let method):
                Button { model.openExternal((entry.install.url ?? entry.website).absoluteString) } label: { Label("Get", systemImage: "arrow.up.right") }
                    .buttonStyle(GlowButtonStyle(.secondary, compact: compact)).accessibilityLabel("Get \(entry.name) from the \(method.sourceLabel)")
            case .unavailable, .incompatible, .needsAttention:
                if let showDetails {
                    Button("Why?", action: showDetails).buttonStyle(GlowButtonStyle(.secondary, compact: compact))
                        .accessibilityLabel("Why \(entry.name) can’t be installed")
                } else {
                    Button { model.openExternal(entry.website.absoluteString) } label: { Label("Website", systemImage: "arrow.up.right") }
                        .buttonStyle(GlowButtonStyle(.secondary, compact: compact)).accessibilityLabel("Visit the \(entry.name) website")
                }
            }
        }
    }
}

// MARK: - Details

private struct CatalogDetailSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: CatalogEntry

    var body: some View {
        let status = model.status(for: entry)
        let metadata = entry.metadataKey.flatMap { model.catalogMetadata.items[$0] }
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                CatalogIcon(entry: entry, appURL: model.installedAppURL(for: entry), size: 60)
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.name).font(.system(size: 26, weight: .medium)).tracking(-0.6).foregroundStyle(Palette.titleGradient)
                    Text(entry.publisher).foregroundStyle(Palette.muted)
                }
                Spacer()
                Tag(text: entry.kind == .app ? "DESKTOP APP" : "COMMAND-LINE TOOL", color: Palette.lavender)
            }
            Text(entry.summary).font(.system(size: 14))
            if let status {
                let (icon, text) = StatusLine.describe(status, entry: entry)
                Card(color: Palette.blue, interactive: false) {
                    Label(text, systemImage: icon).font(.system(size: 13, weight: .semibold))
                    if status.isInstalled { InfoLine(text: "Newer versions from Homebrew, npm, and the App Store appear in Updates.") }
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 14) {
                detail("CATEGORY", entry.category.title)
                detail("SOURCE", sourceDescription)
                detail("PRICE", entry.pricing.label)
                detail("ACCOUNT", entry.requiresAccount.map { $0 ? "Required to use" : "Not required" } ?? "Not verified")
                detail("COMPATIBILITY", compatibility(metadata))
                detail("AVAILABLE VERSION", metadata?.version ?? (entry.install.method.isDirect ? "Unavailable until you check availability" : "Shown by the \(entry.install.method.sourceLabel)"))
                if entry.install.method == .npm { detail("NPM REGISTRY", metadata?.registryURL?.absoluteString ?? "Not checked") }
                detail("DOWNLOAD SIZE", "Unavailable")
                detail("LAST CHECKED", metadata.map { "\($0.checkedAt.formatted(date: .abbreviated, time: .shortened)) · \(RelativeDateTimeFormatter().localizedString(for: $0.checkedAt, relativeTo: Date()))" } ?? "Not checked")
            }
            if let notes = entry.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(notes, id: \.self) { InfoLine(text: $0, icon: "exclamationmark.circle") }
                }
            }
            HStack {
                Button { model.openExternal(entry.website.absoluteString) } label: { Label("Official website", systemImage: "arrow.up.right") }
                    .buttonStyle(GlowButtonStyle(.secondary))
                CatalogPrimaryAction(entry: entry, status: status, selected: model.installSelection.contains(entry.id))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(GlowButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 600).background(SheetBackground(tint: Palette.catalog(entry.category))).foregroundStyle(Palette.ink).environment(\.colorScheme, .dark)
    }

    private var sourceDescription: String {
        switch entry.install.method {
        case .homebrewCask: return "Homebrew cask “\(entry.install.package ?? "")”"
        case .homebrewFormula: return "Homebrew formula “\(entry.install.package ?? "")”"
        case .npm: return "npm package “\(entry.install.package ?? "")”"
        case .appStore: return "Mac App Store"
        case .vendor: return "Publisher’s website"
        }
    }

    private func compatibility(_ metadata: PackageMetadata?) -> String {
        var parts: [String] = []
        if let minimum = entry.minimumMacOS ?? metadata?.minimumMacOS { parts.append("macOS \(minimum) or later") }
        if entry.appleSiliconOnly == true || metadata?.appleSiliconOnly == true { parts.append("Apple silicon only") }
        if let node = metadata?.nodeRequirement { parts.append("Node.js \(node)") }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return metadata == nil && entry.install.method.isDirect ? "Not checked yet" : "No known restrictions"
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Review

private struct InstallReviewSheet: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Tag(text: "REVIEW BEFORE INSTALLING", color: Palette.yellow)
            Text("Here’s exactly what will happen.").font(.system(size: 28, weight: .medium)).tracking(-0.8).foregroundStyle(Palette.titleGradient)
            if let review = model.installReview, let items = review.items {
                let installs = review.installable
                let others = items.filter { item in !installs.contains { $0.id == item.id } }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !installs.isEmpty {
                            section("WILL INSTALL · \(installs.count)")
                            ForEach(installs) { item in installRow(item) }
                        }
                        if !others.isEmpty {
                            section("WON’T INSTALL · \(others.count)")
                            ForEach(others) { item in skippedRow(item) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 160, maxHeight: 440)
                InfoLine(text: "Installs run one at a time using the exact packages listed. Homebrew and npm download from their own sources; being available there isn’t a guarantee that software is safe. If one install fails, earlier ones stay installed.", icon: "shield")
                if !model.settings.allowReviewedChanges && !installs.isEmpty {
                    // The model refuses installs in read-only mode; say so here, where the button is, instead of failing silently behind the sheet.
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.shield").font(.system(size: 16)).frame(width: 34, height: 34).glowTile(Palette.yellow, radius: 10, glow: false)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Read-only mode is on").font(.system(size: 13, weight: .semibold))
                            Text("Installing turns on reviewed changes, which lets Viper run Homebrew or npm for items you confirm. You can switch back in Settings.")
                                .font(.system(size: 11.5)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).noticeBackground(Palette.yellow)
                }
                HStack {
                    Button("Cancel") { model.cancelReview() }.buttonStyle(GlowButtonStyle(.secondary)).keyboardShortcut(.cancelAction)
                    Spacer()
                    Button {
                        if !model.settings.allowReviewedChanges { model.settings.allowReviewedChanges = true }
                        withAnimation(Motion.smooth) { model.confirmInstall() }
                    } label: {
                        Label(installs.isEmpty ? "Nothing to install"
                              : (model.settings.allowReviewedChanges ? "" : "Turn on changes and ") + "Install \(installs.count) \(installs.count == 1 ? "item" : "items")",
                              systemImage: "arrow.down.circle")
                    }.buttonStyle(GlowButtonStyle()).disabled(installs.isEmpty)
                }
            } else {
                HStack(spacing: 12) {
                    ScanPulse(color: Palette.yellow)
                    Text(model.installReview?.progress ?? "").font(.system(size: 13))
                }.padding(.vertical, 30)
                InfoLine(text: "Viper rechecks installed apps and asks each package manager for current details before anything is queued.")
                HStack { Spacer(); Button("Cancel") { model.cancelReview() }.buttonStyle(GlowButtonStyle(.secondary)).keyboardShortcut(.cancelAction) }
            }
        }.padding(30).frame(width: 640).background(SheetBackground(tint: Palette.yellow)).foregroundStyle(Palette.ink).environment(\.colorScheme, .dark)
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
    }

    private func installRow(_ item: InstallPlanItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(item.entry.name).font(.system(size: 14, weight: .semibold))
                Tag(text: item.entry.install.method.sourceLabel.uppercased(), color: Palette.mint)
                Spacer()
                Text(item.version ?? "Version unknown").font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            ForEach(item.details, id: \.self) { Label($0, systemImage: "circle.fill").font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true) }
            GlowDivider()
        }
    }

    private func skippedRow(_ item: InstallPlanItem) -> some View {
        let reason: String
        let blocked: Bool
        switch item.decision {
        case .skip(let text): reason = text; blocked = false
        case .blocked(let text): reason = text; blocked = true
        case .install: reason = ""; blocked = false
        }
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                Image(systemName: blocked ? "exclamationmark.triangle.fill" : "arrow.uturn.right").foregroundStyle(blocked ? Palette.yellow : Palette.muted)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.entry.name).font(.system(size: 14, weight: .semibold))
                    Text(reason).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !item.entry.install.method.isDirect {
                    Button(item.entry.install.method == .appStore ? "App Store" : "Website") { model.openExternal((item.entry.install.url ?? item.entry.website).absoluteString) }
                        .buttonStyle(GlowButtonStyle(.secondary))
                } else if blocked {
                    Button("Website") { model.openExternal(item.entry.website.absoluteString) }.buttonStyle(GlowButtonStyle(.secondary))
                }
            }
            GlowDivider()
        }
    }
}

// MARK: - Queue

private struct InstallQueueCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let queue = model.installQueue
        let installed = queue.filter { if case .installed = $0.state { return true } else { return false } }.count
        let problems = queue.filter { if case .failed = $0.state { return true }; if case .needsAttention = $0.state { return true }; return false }.count
        let waiting = queue.filter { $0.state == .queued }.count
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        if model.installing { ScanPulse() }
                        Text(model.installing ? "Installing your apps" : "Install queue finished").font(.system(size: 18, weight: .semibold))
                    }
                    Text("\(installed) installed · \(problems) need\(problems == 1 ? "s" : "") a look · \(waiting) waiting").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if waiting > 0 {
                    Button("Cancel waiting items") { model.cancelPendingInstalls() }.buttonStyle(GlowButtonStyle(.danger))
                }
                if !model.installing {
                    Button("Clear list") { model.clearFinishedInstalls() }.buttonStyle(GlowButtonStyle(.secondary))
                }
            }
            if model.installing {
                let active = queue.filter { $0.state != .cancelled }
                QueueSummaryBar(finished: active.filter { $0.state.isFinished }.count, total: active.count,
                                current: active.first { $0.state == .installing }?.progress, title: "Overall progress")
            }
            if !model.installing && problems > 0 && installed > 0 {
                InfoLine(text: "Some installs finished and some didn’t. The ones marked installed are ready to use.", icon: "exclamationmark.circle")
            }
            LazyVStack(spacing: 0) {
                ForEach(queue) { item in
                    QueueRow(item: item)
                    if item.id != queue.last?.id { GlowDivider() }
                }
            }
            InfoLine(text: "One install runs at a time. Cancelling stops items that haven’t started; an install already in progress is allowed to finish safely.")
        }
    }
}

private struct QueueRow: View {
    @EnvironmentObject private var model: AppModel
    let item: InstallQueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                CatalogIcon(entry: item.entry, appURL: model.installedAppURL(for: item.entry), size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.entry.name).font(.system(size: 13, weight: .semibold))
                    Text("\(item.request.method.sourceLabel) “\(item.request.package)”").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Tag(text: item.state.label, color: color, pulse: item.state == .installing)
                switch item.state {
                case .installed:
                    if let url = model.installedAppURL(for: item.entry) {
                        Button("Open") { model.openApplication(url) }.buttonStyle(GlowButtonStyle(.secondary))
                    }
                case .failed, .needsAttention, .cancelled:
                    Button("Retry") { model.reviewInstall([item.entry.id]) }.buttonStyle(GlowButtonStyle(.secondary))
                        .disabled(model.installReview != nil || model.installing || model.checkingUpdates || model.refreshingCatalog || model.detectingInstalls).accessibilityLabel("Review \(item.entry.name) again")
                default: EmptyView()
                }
            }
            if item.state == .installing {
                OperationProgressView(progress: item.progress ?? OperationProgress(phase: .preparing, detail: "Starting…"), startedAt: item.startedAt)
            } else if item.state == .queued {
                QueueWaitingLine(position: model.installQueue.filter { $0.state == .queued || $0.state == .installing }.firstIndex { $0.id == item.id } ?? 1)
            }
            if let message {
                Text(message).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            if !item.log.isEmpty {
                Disclosure("Package manager output") {
                    Text(item.log).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.4)))
                        .foregroundStyle(Palette.mint.opacity(0.85))
                }.font(.system(size: 11))
            }
        }.padding(.vertical, 10)
        .animation(Motion.smooth, value: item.state)
    }

    private var color: Color {
        switch item.state {
        case .installed: return Palette.mint
        case .failed: return Palette.peach
        case .needsAttention: return Palette.yellow
        case .installing: return Palette.lavender
        default: return Palette.slate
        }
    }

    private var message: String? {
        switch item.state {
        case .installed(let version): return "Installed version \(version) and confirmed with \(item.request.runtime.manager.rawValue)."
        case .failed(let reason), .needsAttention(let reason): return reason
        case .cancelled: return "Cancelled before it started. Nothing was changed."
        default: return nil
        }
    }
}

// MARK: - Prerequisites

private struct PrerequisiteSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let manager: PackageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Tag(text: "ONE-TIME SETUP", color: Palette.peach)
            Text(manager == .homebrew ? "Set up Homebrew" : "Set up Node.js and npm").font(.system(size: 28, weight: .medium)).tracking(-0.8).foregroundStyle(Palette.titleGradient)
            Text(manager == .homebrew
                 ? "Homebrew is a free, widely used package manager for Mac. Viper uses it to install apps and tools without dragging disk images around."
                 : "npm is the package manager that comes with Node.js. Viper uses it to install command-line tools such as AI coding agents.")
                .font(.system(size: 13)).foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 10) {
                step(1, manager == .homebrew
                     ? "Open brew.sh and follow the official instructions. The installer runs in Terminal and asks for your Mac password."
                     : "Download the official installer from nodejs.org. If Homebrew is already set up, you can add Node.js from this catalog instead.")
                step(2, manager == .homebrew
                     ? "When it finishes, follow any “Next steps” it shows. Viper doesn’t run the installer or change your shell settings for you."
                     : "Viper doesn’t install Node.js silently or change your shell settings for you.")
                step(3, "Come back to Viper and choose Check installed apps.")
            }
            HStack {
                Button { model.openExternal(manager == .homebrew ? "https://brew.sh" : "https://nodejs.org/en/download") } label: {
                    Label(manager == .homebrew ? "Open brew.sh" : "Open nodejs.org", systemImage: "arrow.up.right")
                }.buttonStyle(GlowButtonStyle())
                Button("Check installed apps") { model.detectInstallations(); dismiss() }.buttonStyle(GlowButtonStyle(.secondary))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(GlowButtonStyle(.secondary)).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 560).background(SheetBackground(tint: Palette.peach)).foregroundStyle(Palette.ink).environment(\.colorScheme, .dark)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)").font(.system(size: 12, weight: .bold, design: .monospaced)).frame(width: 26, height: 26)
                .glowTile(Palette.mint, radius: 13)
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
