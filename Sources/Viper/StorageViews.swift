import SwiftUI
import ViperCore

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        PageHeading("Overview")
        if let capacity = model.capacity {
            let used = Double(capacity.usedBytes) / Double(max(1, capacity.totalBytes))
            Card {
                HStack(alignment: .center, spacing: 20) {
                    stat("Available", value: bytes(capacity.availableBytes),
                         caption: capacity.purgeableBytes > 0 ? "Includes \(bytes(capacity.purgeableBytes)) purgeable" : "Ready for new files")
                    stat("Used", value: bytes(capacity.usedBytes), caption: "Includes macOS and apps")
                    stat("Volume", value: capacity.name, caption: "\(bytes(capacity.totalBytes)) total")
                    HStack(spacing: 10) {
                        RingGauge(fraction: used, size: 56, lineWidth: 6) { EmptyView() }
                        Text("\(Int((used * 100).rounded()))% used").font(.system(size: 13, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Palette.muted)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Int((used * 100).rounded())) percent of disk used")
                }
            }
        }
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Tools").font(.system(size: 20, weight: .medium)).tracking(-0.4)
            Text("Everything is reviewed before it changes.").font(.system(size: 12.5)).foregroundStyle(Palette.muted)
        }.padding(.top, 6)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            OverviewTile(index: 1, title: "Remove apps carefully", detail: "Review evidence-backed app, settings, cache, and package matches before removal.", icon: "app.badge", color: Palette.lavender, page: .uninstaller)
            OverviewTile(index: 2, title: "Clean junk and leftovers", detail: "Clear caches, logs, temporary files, and files from removed apps.", icon: "tray", color: Palette.yellow, page: .leftovers)
            OverviewTile(index: 3, title: "Set up your apps", detail: "Pick popular apps and install them together, with a clear review first.", icon: "plus.app", color: Palette.blue, page: .discover)
            OverviewTile(index: 4, title: "Stay up to date", detail: "See available app and tool updates, then choose what to update.", icon: "arrow.down.circle", color: Palette.mint, page: .updates)
            OverviewTile(index: 5, title: "Your privacy, clearly", detail: "Open the right permission setting, or reset an app’s permissions.", icon: "hand.raised", color: Palette.peach, page: .privacy)
            OverviewTile(index: 6, title: "Make space", detail: "Find the biggest files in a folder and move them to the Trash.", icon: "internaldrive", color: Palette.teal, page: .storage)
        }
        InfoLine(text: "Every change is shown to you first. Removed files go to the Trash so you can put them back.", icon: "hand.thumbsup")
    }

    private func stat(_ label: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 26, weight: .light)).tracking(-0.8).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OverviewTile: View {
    @EnvironmentObject private var model: AppModel
    let index: Int
    let title: String
    let detail: String
    let icon: String
    let color: Color
    let page: Page
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { model.page = page } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: icon).font(.system(size: 17, weight: .regular)).frame(width: 42, height: 42)
                        .glowTile(color, radius: 12, glow: hovering)
                    Spacer()
                    Text(String(format: "%02d", index)).font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 16.5, weight: .medium)).tracking(-0.2).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hovering ? Palette.ink : Palette.faint)
                        .offset(x: hovering && !reduceMotion ? 2 : 0, y: hovering && !reduceMotion ? -2 : 0)
                }
                Text(detail).font(.system(size: 12.5)).foregroundStyle(Palette.muted).lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
            .background(GlassBackground(tint: hovering ? color : nil, radius: 22, selected: hovering))
            .glassAura(color, color, intensity: hovering ? 0.35 : 0)
            .offset(y: hovering && !reduceMotion ? -3 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : Motion.smooth, value: hovering)
        .riseIn(delay: 0.04 * Double(index))
        .accessibilityLabel("\(title). \(detail)")
    }
}

struct CapacityCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Card {
            HStack {
                Label(model.capacity?.name ?? "Disk capacity", systemImage: "internaldrive").font(.system(size: 13.5, weight: .medium))
                Spacer()
                Eyebrow(text: "VOLUME")
            }
            if let capacity = model.capacity {
                let used = min(1, max(0, Double(capacity.usedBytes) / Double(max(1, capacity.totalBytes))))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(bytes(capacity.availableBytes)).font(.system(size: 36, weight: .light)).tracking(-1.2).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("available of \(bytes(capacity.totalBytes))").font(.system(size: 13)).foregroundStyle(Palette.muted)
                    Spacer()
                    Text("\(Int((used * 100).rounded()))% used").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Palette.muted)
                }
                GlowMeter(fraction: used, height: 10)
                    .accessibilityLabel("\(bytes(capacity.usedBytes)) used, \(bytes(capacity.availableBytes)) available")
                HStack {
                    Text("Used · \(bytes(capacity.usedBytes))").foregroundStyle(Palette.muted)
                    Spacer()
                    Text(capacity.purgeableBytes > 0 ? "Available includes \(bytes(capacity.purgeableBytes)) macOS can free automatically" : "Includes macOS and data outside your scan").foregroundStyle(Palette.faint)
                }.font(.system(size: 11))
            } else {
                InfoLine(text: model.capacityError ?? "Capacity is unavailable.")
            }
        }
    }
}

struct StorageView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter: StorageCategory?
    @State private var search = ""
    var body: some View {
        PageHeading("Storage", subtitle: model.selectedFolder.path) {
            Button("Choose folder") { model.chooseFolder() }.buttonStyle(GlowButtonStyle(.secondary)).disabled(model.scanning)
            if model.scanning {
                Button("Cancel scan") { model.cancelScan() }.buttonStyle(GlowButtonStyle(.danger))
            } else {
                Button { filter = nil; model.startScan() } label: { Label(model.scan == nil ? "Scan folder" : "Scan again", systemImage: "viewfinder") }
                    .buttonStyle(GlowButtonStyle())
            }
        }
        if model.scanning {
            HStack(spacing: 12) {
                ScanPulse()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Looking through your files…").font(.system(size: 13, weight: .semibold))
                    if let progress = model.progress {
                        Text("\(progress.files.formatted()) files · \(bytes(progress.allocatedBytes)) on disk · \(progress.currentFolder)")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    } else { Text("Preparing the scan. You can cancel at any time.").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                }
            }
        } else if let message = model.scanMessage {
            InfoLine(text: message, icon: model.scan == nil ? "info.circle" : "checkmark.circle")
        } else {
            InfoLine(text: "Scans stay on this volume. Cloud-only files and symbolic links are skipped. Your exclusions and hidden-file preference apply.")
        }
        if let result = model.scan {
            scanSummary(result)
            if !model.storageCleanup.outcomes.isEmpty { CleanupResultCard(target: .storage) }
            if !model.storageSelection.isEmpty || model.storageCleanup.working {
                let selected = result.largestFiles.filter { model.storageSelection.contains($0.id) }
                CleanupActionBar(target: .storage, count: selected.count, size: selected.reduce(0) { $0 + $1.allocatedBytes }) { model.cleanSelected(.storage) }
            }
            fileList(result)
        } else if !model.scanning {
            CapacityCard()
            if let summary = model.scanSummary, summary.root == model.selectedFolder.path {
                savedSummary(summary)
            }
            EmptyPanel(icon: "magnifyingglass", title: "Your files have a story.", detail: "Scan a folder to see its categories and up to \(model.settings.storageResultLimit.formatted()) largest files. Try Downloads for a quick first look.")
        }
    }

    private func savedSummary(_ summary: StoredScanSummary) -> some View {
        Card {
            HStack {
                Text("Last scan").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(summary.completedAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Text("\(summary.files.formatted()) files · \(bytes(summary.allocatedBytes)) allocated. This is an estimate kept from the last scan. Scan again to see the largest files.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            if !summary.largestFolders.isEmpty {
                ForEach(summary.largestFolders, id: \.path) { folder in
                    HStack {
                        Text(folder.name).lineLimit(1)
                        Spacer()
                        Text(bytes(folder.allocatedBytes)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
                        Button("Look inside") { model.lookInside(URL(fileURLWithPath: folder.path)) }
                            .buttonStyle(GlowButtonStyle(.secondary, compact: true))
                    }.font(.system(size: 12))
                }
            }
        }
    }

    private func scanSummary(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                metric("ALLOCATED", value: bytes(result.allocatedBytes), color: Palette.lavender)
                metric("FILES COUNTED", value: result.files.formatted(), color: Palette.mint)
                metric("COVERAGE", value: result.hasLimitedCoverage ? "Partial" : "Accessible files", color: result.hasLimitedCoverage ? Palette.yellow : Palette.blue)
            }
            Card {
                HStack {
                    Text("Inside this folder").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text("Scanned \(RelativeDateTimeFormatter().localizedString(for: result.completedAt, relativeTo: Date()))")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).help(result.completedAt.formatted(date: .abbreviated, time: .standard))
                }
                if Date().timeIntervalSince(result.completedAt) > 1_800 {
                    InfoLine(text: "This scan is over 30 minutes old. Sizes and contents may have changed; scan again for current numbers.", icon: "clock.badge.exclamationmark")
                }
                CategoryBar(result: result).accessibilityHidden(true)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    ForEach(StorageCategory.allCases) { category in
                        if let size = result.categories[category] {
                            HStack(spacing: 8) {
                                Circle().fill(Palette.category(category)).frame(width: 8, height: 8)
                                    .shadow(color: Palette.category(category).opacity(0.8), radius: 4)
                                Text(category.rawValue)
                                Spacer()
                                Text(bytes(size)).font(.system(size: 12, weight: .medium, design: .monospaced))
                            }.font(.system(size: 12)).padding(.trailing, 12)
                        }
                    }
                }
                if !result.largestFolders.isEmpty {
                    Text("Largest folders").font(.system(size: 13, weight: .semibold)).padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        ForEach(result.largestFolders, id: \.name) { folder in
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                Text(folder.name).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("\(bytes(folder.allocatedBytes)) · \(folder.files.formatted()) files")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                Button("Look inside") { model.lookInside(folder.url) }
                                    .buttonStyle(GlowButtonStyle(.secondary, compact: true))
                                    .disabled(model.scanning)
                            }.font(.system(size: 12)).padding(.trailing, 12)
                        }
                    }
                }
                Disclosure("How this is counted") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("File contents: \(bytes(result.logicalBytes)). Allocated disk space: \(bytes(result.allocatedBytes)). APFS clones, compression, snapshots, and purgeable storage can make these totals differ from your disk’s used space. These are not reclaimable-space estimates.")
                        Text("Skipped: \(result.skippedLinks) symbolic links, \(result.skippedCloudItems) cloud-only items, \(result.duplicateHardLinks) duplicate hard links, and \(result.omittedVolumes) entries on other volumes.")
                        Text("Unreadable items: \(result.unreadableCount). Categories are estimates based on file extensions and locations; system files are not independently classified.")
                        ForEach(result.unreadableExamples, id: \.self) { Text($0).textSelection(.enabled) }
                    }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 8)
                }.font(.system(size: 12))
                if result.unreadableCount > 0 {
                    HStack {
                        InfoLine(text: "Some locations couldn’t be read. You can allow broader access, then scan again.", icon: "exclamationmark.circle")
                        Spacer()
                        Button("Access settings") { model.openSettings("com.apple.preference.security?Privacy_AllFiles") }.buttonStyle(.link)
                    }
                }
            }
        }
    }

    private func metric(_ title: String, value: String, color: Color) -> some View {
        Card(color: color) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 4)
                Eyebrow(text: title)
            }
            Text(value).font(.system(size: 24, weight: .medium)).tracking(-0.6).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(Palette.titleGradient)
            if title == "ALLOCATED" {
                Text("Estimate, not reclaimable space").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }
    }

    private func fileList(_ result: ScanResult) -> some View {
        let removed = Set(model.storageCleanup.outcomes.filter { $0.result.succeeded && !$0.restored }.map(\.id))
        let files = result.largestFiles.filter {
            !removed.contains($0.id) && (filter == nil || $0.category == filter) && (search.isEmpty || $0.url.path.localizedCaseInsensitiveContains(search))
        }
        return Card {
            HStack {
                Text("The biggest files").font(.system(size: 18, weight: .semibold))
                Spacer()
                Tag(text: "TOP \(result.largestFiles.count) · ON DISK")
            }
            HStack {
                SearchField(placeholder: "Search largest files", text: $search)
                ViperSelect(title: "Category", selection: $filter, options: [("All categories", Optional<StorageCategory>.none)] + StorageCategory.allCases.map { ($0.rawValue, Optional($0)) }).frame(width: 180)
            }
            if files.isEmpty {
                Text(result.files == 0 ? "No accessible regular files were found in this folder." : "No files match these filters within the \(result.largestFiles.count) retained results.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted).padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(files) { file in
                        FileRow(file: file)
                    }
                }
            }
            InfoLine(text: "Large doesn’t mean unnecessary. Select files you’re sure about; each is re-checked (best effort) before it moves to the Trash. Files inside apps and system locations can’t be selected.")
        }
    }
}

private struct FileRow: View {
    @EnvironmentObject private var model: AppModel
    let file: StorageFile
    @State private var hovering = false
    var body: some View {
        let blocked = StorageCleanup.blockedReason(file.url)
        HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { model.storageSelection.contains(file.id) }, set: { on in
                if on { model.storageSelection.insert(file.id) } else { model.storageSelection.remove(file.id) }
            })) { EmptyView() }
                .toggleStyle(ViperCheckboxStyle()).disabled(blocked != nil || model.storageCleanup.working)
                .help(blocked ?? "Select to move to the Trash").accessibilityLabel("Select \(file.url.lastPathComponent)")
            Image(systemName: "doc.fill").font(.system(size: 15)).frame(width: 36, height: 36)
                .glowTile(Palette.category(file.category), radius: 10, glow: hovering)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.url.lastPathComponent).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(blocked.map { "Can’t be removed here · " + $0 } ?? file.url.deletingLastPathComponent().path).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.middle)
            }.help(file.url.path)
            Spacer(minLength: 8)
            Text(bytes(file.allocatedBytes)).font(.system(size: 12, weight: .semibold, design: .monospaced))
            Button { model.reveal(file.url) } label: { Image(systemName: "arrow.up.right.square").font(.system(size: 15)) }
                .buttonStyle(IconButtonStyle()).help("Reveal in Finder").accessibilityLabel("Reveal \(file.url.lastPathComponent) in Finder")
        }.padding(.vertical, 10).padding(.horizontal, 10)
            .rowHighlight(hovering: hovering, selected: model.storageSelection.contains(file.id))
            .onHover { hovering = $0 }
    }
}

private struct CategoryBar: View {
    let result: ScanResult
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                ForEach(StorageCategory.allCases) { category in
                    if let size = result.categories[category], size > 0 {
                        let color = Palette.category(category)
                        Capsule().fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                            .frame(width: max(4, (geometry.size.width - 30) * Double(size) / Double(max(1, result.allocatedBytes)) * (shown ? 1 : 0)))
                            .shadow(color: color.opacity(0.55), radius: 6)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 14)
        .onAppear { if reduceMotion { shown = true } else { withAnimation(.spring(response: 1, dampingFraction: 0.85).delay(0.1)) { shown = true } } }
    }
}

/// A radar-style pulse shown while a scan runs.
struct ScanPulse: View {
    var color: Color = Palette.mint
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().strokeBorder(color.opacity(0.18), lineWidth: 2)
            Circle().trim(from: 0, to: 0.3)
                .stroke(AngularGradient(colors: [color.opacity(0), color], center: .center), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
            Circle().fill(color).frame(width: 5, height: 5).shadow(color: color, radius: 4)
        }
        .frame(width: 22, height: 22)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
        }
        .accessibilityLabel("Working")
    }
}
