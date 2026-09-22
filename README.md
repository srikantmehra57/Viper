# Viper

A native SwiftUI Mac maintenance app with a dark, luminous glass interface. Version **1.0**: it scans, uninstalls, cleans, updates, and installs, and every change is reviewed before it happens. See [PLAN.md](PLAN.md) for the design.

## Run

Requires macOS 14+ and a working Xcode Swift toolchain with its license accepted.

```sh
swift test
bash scripts/build-app.sh
open dist/Viper.app
```

For a development build, use `bash scripts/build-app.sh debug`. You can also open `Package.swift` in Xcode and run the Viper executable scheme. Normal builds create a locally signed `.app`. A universal Developer ID build can be signed and notarized with `bash scripts/build-app.sh release --distribution` after setting `VIPER_SIGN_IDENTITY` and `VIPER_NOTARY_PROFILE`.

## What it does

- **Storage** — scan a folder for category totals and its 100, 500, or 1,000 largest files, then select files and move them to the Trash. Files inside apps and protected locations (system folders, `~/Library`, credentials folders) can't be selected; each file is fingerprinted and rechecked immediately before it moves.
- **Uninstaller** — apps in `/Applications` and `~/Applications`, Homebrew formulae and app-less casks, and global npm packages for every detected runtime. Select one to review the app or package plus its preferences, Application Support, containers, group containers, caches, HTTP/WebKit storage, logs, saved state, LaunchAgents, and hidden home folders, each with size, evidence, and warnings. Identifier matches are selected; name-only matches are unselected; items used by other installed apps and system-wide `/Library` items are kept. The app or package goes first (Homebrew and npm remove their own packages), and related files move to the Trash only if it succeeded.
- **Junk & Leftovers** — *Junk files*: app caches, logs, old temporary files, Xcode DerivedData, simulator caches, device symbols, and npm's download cache, with anything belonging to an open app kept. *App leftovers*: files named for app identifiers that no installed app, running app, Launch Services record, or exact signed application-group entitlement owns. Nothing is preselected by default. Move reviewed selections to the Trash, put them back, or open the Trash in Finder for a separate permanent-delete action.
- **Updates** — check Homebrew, global npm, and installed App Store apps, then review the apps and tools with updates available. Homebrew and npm packages update individually or all at once; App Store results open that app's own listing. Package updates run one at a time with `brew upgrade --formula|--cask <name>` or `npm install --global <name>@<exact version>`, are rechecked before starting, and verified afterwards.
- **Privacy** — shortcuts to each Privacy & Security category, and a per-app **Reset permissions** that runs Apple's `tccutil reset All <bundle id>` so macOS asks again.
- **Discover & Install** — a validated catalog of 60 apps and tools with starter collections, installed-state detection, a revalidating review, and a serial Homebrew/npm install queue. App Store and publisher-only apps open externally.
- **Settings** — read-only/file-change safety mode, cleanup preselection, storage result depth, saved scan folders, exclusions, hidden files, appearance, menu-bar visibility, close behaviour, and update sources.

Viper starts in read-only mode. After file-changing actions are explicitly enabled, removals and cleanups write their full plan to `removal-transactions.json` before the first mutation and record each outcome as it happens; summaries and package changes are kept in `removal-journal.json` and `install-journal.json`. A header tag appears only while Viper is changing something, and quitting waits for an active change to finish. Turning reviewed changes off cancels installs and updates that have not started. The one already running finishes, and later cleanup or uninstall items are left in place.

## Limits

Viper doesn't use administrator rights: system-wide `/Library` items, root-owned apps that Finder must remove, and installer-package casks are reported rather than forced. macOS doesn't let apps read or grant individual privacy permissions, so Privacy can only open Settings or reset an app. Tools installed outside Homebrew and npm (curl scripts, pipx, cargo) aren't listed. There is no remotely refreshed catalog or download-size estimate.

## Storage accuracy and access

Scans read metadata; they do not read file contents or intentionally download cloud files. File categories use extensions and path hints. Allocated sizes are filesystem estimates, not a promise of reclaimable space: APFS clones, snapshots, compression, and purgeable data affect actual storage. macOS/system data is not separately classified yet. A scan is a point-in-time traversal; files can change while it runs.

macOS may ask for access to protected user folders. Inaccessible items are counted and a few paths are shown locally. Full Disk Access is optional and must be granted by the user in System Settings; Viper never changes that setting. Cloud-only entries, symlinks, and mounted volumes inside the scope are skipped. Coverage is not a claim to have inventoried the whole Mac.

Settings deep links are best-effort and must be verified across supported macOS versions. The interface provides a manual navigation fallback. Viper does not read or write the private TCC permission database.

## Uninstaller safety

Discover → explain → select → preview → journal → revalidate → execute → report. Viper starts read-only, automatic cleanup selection is off, and filesystem items carry a bounded recursive metadata fingerprint so changed descendants invalidate the review. Files move to the Trash with `FileManager.trashItem`; Viper only opens the Trash and leaves permanent deletion to Finder. Homebrew casks, formulae, and global npm packages are removed by their own package manager with fixed argument arrays and no force flags, then verified against the provider's inventory; that step can't be put back from the Trash. Homebrew apps are detected through the Caskroom so `brew` state stays consistent. Viper never removes macOS apps, itself, apps outside `/Applications` or `~/Applications`, Homebrew dependency formulae, or tools bundled with Node.js. File contents are never read; names that look like credentials only produce a warning. Running-app state and installed ownership are refreshed for every cleanup item. Removal is mutually exclusive with installs, update checks, and catalog refreshes, and quitting waits for an active removal.

## Discover & Install safety

The catalog is compiled into the app and validated at load: exact Homebrew tokens (no taps) and npm names (no versions, URLs, or registries), HTTPS websites, `macappstore://` links, and consistent app/command-line types. Catalog content never supplies commands; installs use fixed argument arrays such as `brew install --cask <token>` and `npm install --global <package>@<reviewed-version>`.

Availability checks (`brew info --json=v2`, `npm view`) run only when requested and are cached in `~/Library/Caches/Viper`. Before anything is queued, the review re-reads installed state and fetches fresh metadata; only that fresh metadata can authorise an install. Viper refuses renamed or missing mappings, disabled or deprecated packages, `pkg`/installer casks that need an administrator password, incompatible macOS/architecture/Node.js requirements, non-native Homebrew prefixes, unreadable inventories, and anything already installed from another source (matching app bundle or existing command). Missing Homebrew or npm gets a guided setup that links to the official site; Viper never bootstraps them.

Catalog icons are collected once per catalog review with `swift scripts/fetch-catalog-icons.swift`. Sources are official only, tried in this order: an installed app bundle, Apple's App Store artwork, the publisher's own site icon, or a reviewed override such as a project's GitHub organisation logo. Each source is recorded in `Resources/CatalogIcons/SOURCES.json`, and the build script bundles the icons into the app. The app never downloads icons, and apps without a verified icon show a letter tile. Icons are the publishers' trademarks, used only to identify their software.

Before each queued install, Viper rechecks installed state, metadata, compatibility, the reviewed version, and the exact npm registry origin. npm registry URLs are shown during review; remote registries must use HTTPS, and a registry change requires a new review. npm installs request the exact reviewed version. Update checks and catalog/package operations are gated against each other.

Installs run one at a time and are verified with the provider's own inventory afterwards. Cancelling stops waiting items only; an active install finishes, and quitting waits for it. Outcomes are recorded in `~/Library/Application Support/Viper/install-journal.json`. Nothing is rolled back.

## Architecture

`ViperCore` contains filesystem scanning, app discovery, ownership and removal policy, cleanup and uninstall execution, the catalog (`Catalog`, `BuiltInCatalog`), package providers (`PackageProviders`), install planning, and journals. `Viper` contains the SwiftUI app, design tokens, view models, and AppKit integration. Scans and app discovery run at utility priority outside the main actor. Results remain in memory and disappear when the app quits. No daemon, login item, scheduled task, telemetry, or background polling is installed.

## Validation

`swift test` exercises real temporary fixture directories for counts, hard links, symlinks, bounded results, cancellation, missing folders, and path protection. No tests clean or uninstall real user data.

Manual checks: launch the packaged app; scan a small test folder; filter results; reveal a file; cancel a larger scan; refresh the app list; open an app detail sheet; exercise Settings handoffs; resize the window; navigate with keyboard and VoiceOver; close the last window and verify the process exits.

Release readiness still requires macOS-version coverage, broader filesystem/provider tests, accessibility QA, energy profiling on reference hardware, and Developer ID signing/notarization.
