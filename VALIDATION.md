# Viper — validation

Checked on 2026-09-15 using the installed Apple Swift 6.4 toolchain and macOS 27 SDK. Package deployment target: macOS 14. The delivered binary is arm64; deployment-target declaration is not a substitute for testing older OS versions.

## Initial 0.1 checks

- `swift test`: 13 tests, zero failures; final debug build has no compiler warnings.
- `bash scripts/build-app.sh release`: production build and app packaging succeed.
- `codesign --verify --deep --strict --verbose=2 dist/Viper.app`: valid local ad-hoc signature.
- `plutil -lint dist/Viper.app/Contents/Info.plist`: valid.
- Packaged native app launches and displays actual disk capacity.
- Overview, Storage, app inventory, and Privacy layouts visually inspected at the default size.
- UI folder picker selects `.build/smoke-fixture`; scan returns its two fixture files and actual allocated-byte totals. No user files were used as cleanup targets.
- Largest-file search filters the fixture results to the matching filename.
- Standard-folder app inventory loads; detail sheet displays version, path, source hint, and running state, and dismisses correctly.
- Camera shortcut opens System Settings directly to Camera. No permissions were changed.
- Closing the only Viper window exits its process.

## Automated coverage

Scanner fixtures: logical file totals, category sums, read-only content preservation, symbolic links including cycles, hard-link deduplication, top-100 bounding and ordering, empty directories, cancellation, missing directories, symbolic-link roots, and category path boundaries.

Policy fixtures: system roots, home root, other users, sensitive settings/credentials, personal-file review requirements, and symlink escapes. Cleanup and uninstall execution add exact-target review, file-identity checks, scope validation, and Trash recovery on top of these policy rules.

## Performance observation

One settled process snapshot after UI checks showed 0.2% CPU and 166,096 KiB resident memory (about 162 MiB). This is a single development-machine observation, not an idle-energy benchmark or a guarantee. Instruments profiling, scan peaks, startup measurement, accessibility, and memory optimization remain release work. No periodic task, daemon, or login item is installed by the app.

## Discover & Install — 2026-09-15

- `swift test`: 36 tests, zero failures, no compiler warnings. New coverage: catalog schema and unsafe mappings (taps, flags, command characters, versioned npm names, insecure links, duplicates, broken collections), exact argument arrays, recorded `brew info`/`brew list`/`npm view`/`npm ls` shapes (installer packages, arm-only, minimum macOS, disabled, E404 vs offline), installed-elsewhere detection, prerequisites, non-native Homebrew prefixes, unreadable inventories, renamed/missing/admin/deprecated/incompatible packages, Node.js ranges, plan deduplication/ordering/fresh-metadata requirement, journal limits and permissions, corrupt cache handling, and stderr capture.
- Every catalog Homebrew token was checked against live `brew info` on this Mac and is canonical (this caught `todoist` → `todoist-app`); npm names were checked with `npm view`.
- Read-only live run on this Mac (Homebrew and npm at /opt/homebrew/bin): detection matched manually installed Claude, ChatGPT, Brave, and WhatsApp as installed elsewhere, Xcode via App Store receipt, and Node.js via Homebrew. A review of Firefox, Git, Node.js, Zoom, Claude Code, Xcode, LM Studio, and a duplicate Firefox produced: 4 installs with dependency/script/Node disclosures, Node.js skipped as installed, Zoom blocked (installer package needs an administrator password), Xcode routed to the App Store, duplicate removed.
- Rendered Discover page, review sheet, and prerequisite sheet were visually inspected (dark appearance). A layout bug where the review list collapsed was found and fixed.
- **Not verified:** no real installation was performed (installs belong in a disposable environment), so queue execution, post-install verification, retry, cancel-waiting, and quit-while-installing are exercised by code review only. Also unverified: missing Homebrew/npm on a clean machine, multiple npm runtimes, Intel Macs, offline behaviour in the UI, VoiceOver, and App Store/publisher links.

## Still unverified / release work

- Other macOS versions and Intel builds; minimum-window-size and full VoiceOver/keyboard audits.
- Remaining Settings deep links across supported macOS versions.
- Cloud-provider behavior, access-denied integration scenarios, APFS clones/snapshots, and external-volume behavior beyond the implemented guards.
- Active scan cancellation through the UI (the core cancellation test passes).
- Finder handoff end-to-end (buttons exist; app detail and file search were exercised).
- Real-user cleanup/uninstall and package-update execution; tests use disposable fixtures, and the manual checks below intentionally stop before mutation. A remotely refreshed catalog is not implemented.
- Developer ID signing and notarization.


## Combined 0.2 review — 2026-09-15

- Combined suite: 37 tests passed. Additional coverage rejects npm inventory error payloads and pins npm install arguments to the reviewed version.
- Added mutual exclusion between update checking, catalog metadata operations, inventory refresh, and installation. Each queued install revalidates state/compatibility/version immediately before execution; changed or unverifiable items require review again.
- Installer errors after a command may have started are reported as uncertain/possibly partial, never as a guarantee of no changes.
- Live update check displayed an npm update with installed and available versions. Homebrew completed successfully; an unmatched App Store app was labelled unknown rather than current.
- Live Leftovers scan returned candidates and evidence. A discovered false positive for Viper running outside Applications was corrected by including running-app identifiers and the current app in owner matching.
- Dark and light appearance and custom search/dropdown/chip controls were inspected in the native app. The menu-bar feedback-loop crash found during development was fixed by guarding redundant writes.
- Discover search, selection, themed status dropdown, and exact-package review were exercised. The test review was cancelled before installation; no software was installed during this combined review.
- Adding a fixture directory to saved scan locations was exercised through the native folder picker.
- A Dock accessibility inspection timed out; the icon resource is packaged, but this combined review does not claim a successful Dock accessibility capture.

## Uninstaller — 2026-09-15

- `swift test`: 50 tests, zero failures. New fixture coverage (temporary home folders and a fixture Trash; the real Trash and real apps are never touched): exact vs likely matching across Library scopes, ByHost and team/group prefixes, longer unrelated identifiers, data owned by other installed apps, duplicate app copies, symlink exclusion, credential-name warnings, blocked system apps/Viper/apps outside application folders, execution order, running and replaced apps keeping everything, revalidation against swapped files/symlinks/recreated folders/out-of-scope parents, put back, npm package plans with failure handling, bundled and dependency tools, unsafe package names, Homebrew cask ownership, and journal permissions. Command-line inventory parsers are covered with recorded `brew info --installed` and `npm ls --long` shapes.
- Read-only dry run on this Mac produced plans for every installed app and tool with plausible results (e.g. Claude's shared `Application Support/Claude` and `~/.claude` unselected with warnings; `~/.dsh` flagged for its credentials file; Homebrew `node` warns that global npm tools depend on it). No real removal was performed.
- The native Xcode review sheet was visually inspected on 2026-09-16 and cancelled before removal. **Not verified:** a real `trashItem` of root-owned App Store apps, the Finder fallback, real `brew`/`npm uninstall` runs, and quit-while-removing.

## Version 1.0 actions — 2026-09-15

- The preview label is gone; the app is versioned 1.0.0 and shows a header tag only while installing, uninstalling, cleaning, or updating.
- `swift test`: 56 tests, zero failures. New fixture coverage: junk selection (rebuildable vs slow-to-rebuild, open-app caches and vendor folders kept, recent temp files and Viper's own process folders skipped, every item inside an accepted location), leftover ownership (Launch Services, installed helpers, developer group containers kept while a sibling is installed, never-preselected shared groups), cleanup execution (identity swap, scope rejection, put back), storage file blocks (apps, protected locations, files changed since scan via lstat), exact update commands and version pinning, and permission-reset argument validation.
- Read-only dry runs on this Mac: Junk found about 2.8 GB with open apps' caches kept (Claude, ChatGPT); Leftovers first flagged WhatsApp's shared group folders, which led to the developer-group rule above.
- **Not verified:** the native pages were not visually inspected in this pass (no Accessibility/Screen Recording access in this environment). No real cleanup, update, permission reset, or Empty Trash was run on this Mac.

## Integration follow-up — 2026-09-16

- Rebuilt version 1.0 after integrating cleanup, uninstaller, maintenance, and Discover & Install. `swift test`: 56 tests, zero failures.
- Visually inspected the packaged app in its current system dark appearance: Updates presents a store-style available-update list and no standalone macOS/App Store update detour; Junk and App leftovers each expose a clear Scan action; Settings uses themed controls and persists folders and appearance; Discover & Install shows 60 catalog entries, starter collections, custom status and category filters, installed-state feedback, and recognizable bundled icons.
- Restored the appearance preference to System and removed the temporary smoke-test folder from the saved scan-folder list after the walkthrough.
- No real install, update, cleanup, uninstall, permission reset, or Trash operation was performed.
- A settled process snapshot after the walkthrough showed 0.0% CPU and 126,048 KiB resident memory. This is a single observation rather than an Instruments energy or memory benchmark.
