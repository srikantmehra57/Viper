# Viper — product and build plan

## Product

A native Mac maintenance app for everyday users. Explain what occupies space, help remove unwanted software, identify likely leftovers, manage supported updates, guide privacy changes, and provide a Ninite-style Discover & Install catalog for Homebrew and npm. Use plain language and make every consequential action reviewable.

## Technical direction

- Swift and SwiftUI, with AppKit where native desktop behavior needs it.
- Proposed baseline: macOS 14+, Apple silicon and Intel where supported; validate on each supported release.
- Direct distribution as a signed, notarized app. Developer ID credentials are a release prerequisite.
- Separate UI, inventory/scanning, package providers, safety policy, and action execution modules.
- Package providers expose explicit inventory, install, update, and uninstall capabilities. Stable app identities, source mappings, dependency planning, and operation results are shared across the catalog and maintenance features.
- Async, cancellable work with bounded concurrency, incremental results, and a small local inventory cache.
- No resident daemon, login item, idle polling, or automatic background scans in v1. Closing the last window quits after any active operation is safely resolved.
- Start without a privileged helper. Unsupported administrative operations remain guided external actions until a narrowly scoped helper is justified.
- Local analysis; network requests only for explicitly initiated update checks, catalog metadata refreshes, and installations. No telemetry by default.

## Main navigation and behavior

| Page | Main experience | Boundaries |
| --- | --- | --- |
| Overview | Storage summary, last scan time, and clear shortcuts | No invented health score or alarming cleanup claims |
| Storage | Capacity bar, categories, largest files/folders, filters, Reveal in Finder | Protected OS space is informational; incomplete scans clearly marked |
| Uninstaller | Search installed apps/tools, select one, review app plus related data | Protected apps blocked; dependencies and shared data respected |
| Leftovers | Candidate files grouped by former app, evidence and confidence | Age or a similar filename alone never establishes ownership |
| Updates | Installed/current version, source, available action, progress | Direct package updates stay separate from app-specific App Store actions |
| Privacy | Installed apps plus permission-category guidance and Settings shortcuts | Unknown status is never displayed as denied; no direct permission database writes |
| Discover & Install | Browse categories, search popular apps, select a batch, and install with clear progress | Verified source mappings and compatibility checks; only supported apps/packages are directly installable |

Use “Leftovers” in the interface rather than “Orphans”. Put source labels such as Homebrew and npm behind friendly explanations without hiding the origin of an operation.

## Feature implementation

### 1. Storage

Read filesystem volume capacity independently from directory enumeration. Scan local user-selected scope and accessible app folders; offer Full Disk Access contextually for broader coverage. Show inaccessible paths and count excluded areas. Report progress without guessing a percentage when total work is unknown.

Distinguish logical file size from allocated size. Avoid double counting hard links, avoid following symlinks, skip cloud placeholders without downloading them, and keep external volumes opt-in. Explain that APFS sharing, snapshots, purgeable space, and access restrictions mean folder totals may not equal used capacity. Never label all unclassified space as removable junk.

### 2. Uninstaller

Discover application bundles, bundle identifiers, install source, global npm tools, and Homebrew formulae/casks. Account for multiple detected prefixes/runtimes and show inventory coverage. Do not recursively scan every project for dependencies.

Use source-specific providers for package operations. Review known support files, preferences, containers, caches, and launch items using reliable ownership evidence. Keep shared vendor folders, credentials, user documents, projects, and ambiguous data excluded by default. Prefer an official uninstaller for apps with drivers, extensions, or complex services. macOS components and unknown unmanaged toolchains are not generic deletion targets.

“Complete uninstall” means all confidently attributable supported components, with explicit reporting of exclusions and unsupported items; never promise universal removal.

### 3. Leftovers

Build candidates from known identifiers, supported cleanup rules, package metadata, and prior Viper inventory. Recheck whether the owner exists in all scanned locations. Apps on unmounted volumes or outside scan coverage make absence uncertain. Each candidate explains why it was identified and whether it can be recreated.

OS update payloads, snapshots, shared runtimes, and unknown system data remain informational or use Apple-supported management routes. No blanket deletion of Library folders, receipts, caches, or files based on age.

### 4. Updates

- Homebrew: inspect structured metadata; update selected supported formulae/casks with dependency and side-effect disclosure.
- npm: inventory and update selected global packages in a detected runtime/prefix; disclose major-version changes and package lifecycle scripts.
- App Store: list installed apps with a newer catalog version and open the matching app listing.
- Built-in Apple software: leave macOS updates to System Settings rather than mixing them into the app list.
- Independently installed apps: use a verified supported integration or open their updater/vendor route. Do not infer a safe download from a matching name.

Run mutating package operations serially. Display their real output as a friendly summary with optional details. Cancellation must respect package-manager transaction safety. Never promise rollback for package operations that cannot support it.

### 5. Privacy

Build a version-aware category catalog for camera, microphone, location, screen/system-audio recording, accessibility, input monitoring, automation, files/folders, Full Disk Access, notifications, and other categories available on the running macOS version. Validate Settings destinations and provide navigation instructions if a deep link is unavailable.

macOS does not expose a universal supported API for enumerating every permission granted to every app. Start with a useful Settings navigator and honest per-app availability states. Declared permissions are not proof of granted permissions. Full Disk Access does not make universal public permission enumeration available. Do not rely on private TCC schemas or disable system protection. There is no assumed universal “display over other apps” permission corresponding to other platforms.

### 6. Discover & Install

Provide a Ninite-style setup experience for a fresh or existing Mac. Users browse a curated catalog of popular software, select what they want, review the batch, and choose “Install selected”. No terminal knowledge is required.

**Categories:** IDEs & Developer Tools, AI Agents & Assistants, Music & Audio, Video, Gaming, Browsers, Images & Design, Utilities, Productivity, and Communication. Support search and filters for category, installed status, and compatibility. “Popular” starts as an editorial collection with a review date; do not claim measured usage rankings without a documented source.

**App cards and details:** recognizable icon, app name, publisher, short plain-language description, category, official website, source, compatibility, and free/paid/account requirements where verified. Clearly distinguish desktop apps from command-line tools. Show available version and download/storage estimates only when reliable; otherwise say unavailable.

**Install flow:**

1. Browse or search; add apps to a selection. Offer optional curated starter collections without automatically selecting software.
2. Detect existing installations and their source, architecture, macOS compatibility, required runtimes, package-manager availability, and conflicts. Offer Open for installed apps and route newer versions into the existing update flow. Never silently replace or adopt an installation from another source.
3. Review exact apps, verified package identifiers, dependencies, source, available size estimates, and any setup or administrator steps. Missing Homebrew or Node/npm gets a plain-language prerequisite flow using the official installation route and explicit user consent; do not silently bootstrap tools or change shell configuration.
4. Install via the appropriate Homebrew cask/formula or npm global package in an explicit detected runtime/prefix. Serialize mutations through the shared operation queue; show per-app queued, downloading, installing, installed, failed, or needs-attention states when the provider can actually distinguish them.
5. Let users cancel pending items, safely handle an active installation, retry failed items, and open installed apps. Verify installed state after completion; report partial success without claiming the entire batch succeeded.
6. Register source and installed version in the shared inventory so Updates, Uninstaller, and Leftovers can manage the same software consistently.

**Catalog and execution safety:** maintain a versioned catalog mapping a stable app identity to reviewed publisher/source/package identifiers, supported platforms, and source preference. Validate catalog integrity and schema; never execute arbitrary commands supplied by catalog content. Avoid package-name guessing, ambiguous lookalikes, and automatic custom-tap or registry additions. Explain material lifecycle-script and installer side effects in the review; provider availability is not a guarantee of software safety. An installation journal records outcomes, but does not promise atomic batch rollback.

**Coverage:** the long-term ambition is broad app discovery. Direct installation covers supported Homebrew and npm packages, not literally every Mac app. Apps requiring the App Store, vendor installers, licenses, sign-in, or interactive setup receive a clearly labeled external action when listed. Unavailable or incompatible packages cannot be selected for automatic installation.

**Resource behavior:** load the catalog on demand, cache metadata locally, and refresh only on user request. No continuous popularity tracking, catalog polling, or background installation service.

## Safety architecture

Every removal follows: discover → explain → user selection → preview → revalidate → execute → report.

1. A shared policy engine classifies items as protected, review required, or eligible. Rules are applied again at execution time.
2. Canonical paths and file identity are checked; reject symlink escapes, swapped targets, volume roots, protected OS locations, and out-of-scope files. Execution must prevent time-of-check/time-of-use races.
3. Preview lists exact targets, purpose, source, estimated space, shared dependencies, and recovery limitations. Nothing is preselected merely because it is large.
4. Use Finder Trash for eligible standalone files where supported. Explain that disk space is not necessarily reclaimed until Trash is emptied. Viper does not silently empty Trash.
5. App/package uninstallers use their own supported mechanisms; disclose irreversible settings loss and external side effects before execution.
6. Recheck running apps, file identity, ownership confidence, and dependencies before mutation. Fail closed when evidence changes.
7. Keep a minimal local action journal with partial-failure reporting. Restore is offered only where actually possible.
8. No cleaning real user data during development. Use temporary fixtures and disposable test environments for destructive integration checks.

## Visual direction

Pastel brutalism: warm ivory background, ink-black typography, clear rectangular borders, small corner radii, offset shadows, and restrained mint, lavender, butter-yellow, and peach accents. Large readable headings, concise labels, spacious rows, and a consistent sidebar.

Controls have hover, pressed, keyboard-focus, disabled, loading, selected, success, and error states. Use short transitions, respect Reduce Motion, provide VoiceOver labels, and maintain text contrast. Never communicate risk through color alone. Show a friendly summary first; paths and technical evidence expand on demand.

The main action on analysis pages is “Scan” or “Review selected”, followed by a specific action such as “Move 3 files to Trash”. Avoid ambiguous “Fix everything” buttons. Include empty, partial-access, cancelled, stale-results, offline, and partial-failure states from the beginning.

## Delivery sequence

1. **Foundation and visual shell:** native app package/project, navigation, design tokens, reusable interactive controls, clearly labeled preview data, and accessibility basics.
2. **Read-only vertical slice:** real capacity reporting, cancellable folder scan, largest-file list, app inventory, permission/coverage notices, Reveal in Finder. No deletion controls until policy tests pass.
3. **Safe file removal:** policy engine, exact selection review, execution revalidation, Trash integration, and journal.
4. **Uninstaller:** ordinary app bundles first, then Homebrew/npm adapters, associated-data evidence, dependency checks, and official-uninstaller handoffs.
5. **Leftovers:** conservative evidence rules, coverage/confidence presentation, and shared review workflow.
6. **Updates and Privacy:** source-specific update flows and validated System Settings navigation with honest status limitations.
7. **Release hardening:** failure recovery, compatibility checks, accessibility review, Instruments profiling, signing/notarization, packaging, and onboarding.
8. **Discover & Install:** curated categorized catalog, search and starter collections, reviewed Homebrew/npm mappings, prerequisite setup, batch review and install queue, per-app recovery, and shared inventory/update/uninstall integration.

Each milestone should produce a runnable increment. The first useful build is the read-only storage and app-inventory slice; demonstration data must never look like a completed real scan.

## Validation and completion criteria

- Unit/fixture tests cover protected paths, symlink escapes, identity changes, ambiguous ownership, incomplete inventory, shared dependencies, and package argument handling.
- Filesystem fixtures cover inaccessible folders, hard links, cloud placeholders, huge directories, cancellation, and partial results.
- Provider tests use recorded structured output and simulated failures; destructive integration tests run in disposable environments.
- No shell interpolation of file paths/package names; invoke trusted binaries with validated argument arrays and controlled environment.
- UI remains responsive during scans. Profile cold launch, peak memory, scan I/O, energy, and idle CPU on recorded reference hardware. Proposed target: effectively 0% CPU at settled idle, no recurring disk/network activity, and a visible window within one second on the reference machine. These are targets, not measured claims.
- Verify navigation and coverage behavior on each supported macOS release, with and without Full Disk Access, Homebrew, and npm.
- Final release requires validated signing/notarization and a user-facing explanation of supported versus guided operations.
- Installer acceptance: test missing package managers, multiple runtimes/prefixes, existing apps from another source, duplicate selections, incompatible apps, unavailable packages, invalid catalog data, dependency conflicts, offline failures, partial batches, cancellation, retries, and post-install inventory verification. Test actual installs only in disposable environments.

## Current environment

The workspace was empty at planning time. The user accepted the Xcode/Apple SDK license on 2026-09-15; compilation is now available.

### Build progress — 2026-09-16

- The SwiftUI shell, real storage scans, application and command-line inventory, custom controls, settings, light/dark themes, Dock presence, and menu-bar controls are implemented.
- Junk, leftovers, large-file cleanup, and app/package uninstall have review, execution-time revalidation, Trash recovery where supported, and local journals.
- Updates list available Homebrew, npm, and installed App Store app updates. Homebrew and npm updates run serially after confirmation; App Store results open the matching listing.
- Privacy provides category shortcuts and per-app permission reset through Apple's supported tools; macOS does not provide a public API for reading every app's current grants.
- Debug tests and the release build pass. `dist/Viper.app` is an arm64 local development build with an ad-hoc signature; Developer ID signing, notarization, Intel packaging, and supported-version testing remain.
- Discover & Install has a validated built-in catalog, provider inventory and metadata checks, revalidating batch review, serial install queue, journal, and prerequisite guidance. Catalog refresh is limited to provider metadata; there is no remote catalog source yet.
- See `VALIDATION.md` for actual checks and remaining validation work. Do not interpret a preview screen as completion of its planned feature.

## Reference constraints

- Apple System Integrity Protection: https://support.apple.com/en-us/102149
- Apple Privacy & Security settings: https://support.apple.com/en-ca/guide/mac-help/mchl211c911f/mac
- Apple developer privacy discussion: https://developer.apple.com/forums/tags/privacy?sortBy=oldest
- Apple update routes: https://support.apple.com/en-gb/guide/mac-help/mh35618/mac
- Homebrew operations and caveats: https://docs.brew.sh/Manpage
- npm uninstall behavior: https://docs.npmjs.com/cli/uninstall/
