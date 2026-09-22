# Viper production audit

Date: 22 September 2026  
Scope: source tree at this revision, `swift test`, and `swift build` on macOS 27 (arm64, Swift 6.4).  
The packaged app was not launched in this pass, and no real install, update, uninstall, or Trash operation was run against this Mac.

## Executive summary

Viper is a native SwiftUI Mac maintenance app. Domain work lives in `ViperCore` (scan, ownership, removal, catalog, package providers, journals). The `Viper` target is SwiftUI, view models, and AppKit handoff. There is no daemon, login item, telemetry, or background poller.

The destructive path is already deliberate: read-only by default, fixed argument arrays, identity and directory fingerprints, write-ahead removal transactions, and serial package mutations. This pass closed gaps where that promise was not actually enforced: waiting installs and updates could continue after reviewed changes were turned off, a journal write failure did not stop the rest of a queue, a cancelled package command could leave a child that had left its process group, and external links were not checked again at the open boundary.

`swift test`: 97 tests, 0 failures. `swift build`: no compiler warnings.

Distribution is not release-complete until the app is Developer ID signed and notarized with the existing `scripts/build-app.sh release --distribution` path. That needs the maintainer’s signing credentials. It is not a code defect.

## Architecture

```
SwiftUI pages (Viper)
  AppModel + feature models (Cleanup, Uninstall, Install, Maintenance)
    ViperCore policy and executors
      FileManager / lstat fingerprints
      CommandRunner (posix_spawn, fixed argv, allowlisted environment)
      Homebrew, npm, tccutil, App Store URLs
    Journals in ~/Library/Application Support/Viper
    Settings in UserDefaults
```

UI does not shell out with interpolated command strings. Package names are validated before they become arguments. Scans and inventories run off the main actor. Mutation is gated by `allowReviewedChanges`, journal readability, and `maintenanceBusy` / `installing`.

Known structural limits, left in place because replacing them would be a rewrite:

- `AppModel` is a large coordinator. Feature logic is split across files, but mutual exclusion is still a set of booleans rather than one operation state machine.
- Filesystem and process effects are static functions. Tests inject trash and package outcomes at the executor boundary; they do not inject a fake disk for every scanner.
- Results are in memory. Journals record outcomes; they are not a general database.

## Feature matrix

| Feature | Happy path | Failure / edge | Status |
| --- | --- | --- | --- |
| Storage scan | Folder totals, categories, largest files, cancel | Symlinks, hard links, other volumes, exclusions, hidden files | Covered by fixtures |
| Storage cleanup | Review, fingerprint, Trash, put back | Apps, protected paths, changed size, symlink occupying the original path | Covered |
| Uninstaller | Plan, select, journal, revalidate, Trash or package manager | Running app, swapped file, ambiguous cask, self, system apps | Covered |
| Junk and leftovers | Scan, evidence, optional preselect of exact rebuildable items | Open-app heuristics, Launch Services, application groups | Covered; name heuristics remain |
| Updates | Check, review, one-at-a-time upgrade, version recheck | Metadata change, failed command, timeout, unsettled process | Core covered |
| Privacy | Settings links, `tccutil reset` for a bundle id | Invalid identifiers rejected; system apps not offered | Argument validation covered |
| Discover & Install | Catalog validation, review, serial install | Unsafe mappings, registry change, read-only gate | Catalog and planner covered |
| Settings | Safety mode, folders, journals, reset | Corrupt settings restore defaults and say so; unreadable journals quarantine | Journal quarantine covered |

## Issues

### AUD-001

Category: State management  
Severity: P1  
Problem: Turning reviewed changes off, or hitting an unreadable journal, did not stop installs and updates that were already queued. A cleanup or uninstall already in progress also kept moving later items.  
Evidence: `runInstallQueue` / `runUpdateQueue` only checked gates before the queue started. `CleanupExecutor` and `UninstallExecutor` did not consult the safety switch between items.  
Root cause: The safety switch was checked at confirmation time only.  
Affected files: `AppModel.swift`, `InstallModel.swift`, `MaintenanceModel.swift`, `CleanupModel.swift`, `UninstallModel.swift`, `LeftoverScanner.swift`, `Uninstaller.swift`, `Maintenance.swift`  
Fix: Waiting queue items are cancelled when reviewed changes turn off or a journal becomes unreadable. Each later cleanup or uninstall item re-reads the switch and is left in place when it is off. A journal write failure cancels the rest of the queue.  
Test performed: `testWaitingWorkStaysBlockedUntilChangesAndJournalsAreClear`, `testCleanupStopsWhenReviewedChangesTurnOff`, `testTurningOffReviewedChangesStopsBeforeAnythingMoves`. Full suite green.  
Regression risk: Quit still cancels waiting work and lets the active package command finish. An in-flight Trash move is not interrupted.  
Status: Resolved

### AUD-002

Category: Reliability  
Severity: P1  
Problem: Cancelling or timing out a package command killed the process group, but a child that called `setsid` stayed in the process tree and could keep running while Viper reported the operation had stopped.  
Evidence: `CommandRunner.stop` signalled the process group only.  
Root cause: New sessions are not in the original group, but they remain children until the parent exits.  
Affected files: `CommandRunner.swift`, `PackageProviders.swift`, `Maintenance.swift`  
Fix: On stop, Viper records descendant pids and signals those pids as well as the group. If any recorded descendant is still alive, the error is `CommandError.unsettled` and install, update, and uninstall copy says the operation may still be running.  
Test performed: Existing process-group timeout test, plus `testTimeoutKillsAChildThatLeftTheProcessGroup` (Python `fork` + `setsid`).  
Regression risk: A descendant that double-forks and is reparented to launchd before the snapshot is still invisible. That case is reported only if a known pid survives.  
Status: Resolved for children still in the tree. Residual double-fork case is AUD-010.

### AUD-003

Category: Security  
Severity: P2  
Problem: `openExternal` handed any URL string to `NSWorkspace.open`. Catalog data is validated, but the open boundary did not repeat that check.  
Evidence: `AppModel.openExternal` accepted any `URL(string:)`.  
Root cause: Validation lived only in the catalog decoder.  
Affected files: `ExternalLink.swift`, `AppModel.swift`  
Fix: Only `https` URLs without userinfo, and `macappstore` links to `itunes.apple.com` or `apps.apple.com` with `/app/id<digits>`, are opened. System Settings suffixes must match the compiled Privacy destinations.  
Test performed: `ExternalLinkTests.testOnlySecureWebAndAppStoreLinksOpen`.  
Regression risk: A future catalog link on another host will not open until the allowlist is updated.  
Status: Resolved

### AUD-004

Category: Data integrity  
Severity: P2  
Problem: Put-back used `FileManager.fileExists`, which follows symlinks. A dangling symlink at the original path looked empty.  
Evidence: `UninstallExecutor.restore`.  
Root cause: Existence was checked with the following API.  
Fix: `lstat` on the Trash copy and the original path. A symlink, including a dangling one, blocks the restore.  
Test performed: `testPutBackRefusesWhenTheOriginalPathIsASymlink`.  
Status: Resolved

### AUD-005

Category: State management  
Severity: P2  
Problem: Resetting settings replaced the struct but left the selected scan folder and in-memory scan pointing at the previous location.  
Evidence: Settings reset assigned `AppSettings()` and did not call `selectFolder`.  
Fix: `resetSettings()` restores defaults, keeps quarantined journals and already-acknowledged interruptions, clears the scan, and selects the default folder. It refuses while a scan or mutation is running.  
Test performed: Code review and build. No UI automation for Settings.  
Status: Resolved in code; not clicked through in the packaged app

### AUD-006

Category: Accessibility  
Severity: P2  
Problem: Custom button styles, sidebar rows, checkboxes, menus, and disclosures did not draw their own keyboard focus ring. Checkboxes were exposed as plain buttons.  
Evidence: `GlowButtonStyle`, `IconButtonStyle`, `ViperCheckboxStyle`, `NavRow` use plain or fully custom styles.  
Fix: `FocusHalo` draws a white ring from the focus environment. Checkboxes add the toggle trait. Select options and chips expose selected state.  
Test performed: Compiles. Not verified with VoiceOver or Full Keyboard Access in a running app.  
Status: Resolved in code; needs a keyboard pass on the packaged app

### AUD-007

Category: Correctness  
Severity: P2  
Problem: Storage accounting skipped a file when URL resource values omitted `isRegularFile`, even if `lstat` showed a regular file.  
Fix: The file-type decision uses `lstat` mode.  
Test performed: Existing scanner fixtures still pass.  
Status: Resolved

### AUD-008

Category: Data integrity  
Severity: P3  
Problem: Journal writes were atomic but not explicitly fsynced after the rename.  
Fix: `InstallJournal.write` fsyncs the file after the atomic replace and permission update.  
Test performed: Existing journal round-trip and permission test.  
Status: Resolved. The journal file and its parent directory are both fsynced.

### AUD-009

Category: UX  
Severity: P3  
Problem: The uninstall sheet used a fixed 780×740 frame, and the install review list used a fixed 440-point height, which clips on shorter windows.  
Fix: Both use a min/ideal/max size so they can shrink.  
Test performed: Not visually checked.  
Status: Resolved in code

### AUD-010

Category: Reliability  
Severity: P2  
Problem: A package-manager child that double-forks into a daemon before Viper snapshots the tree is no longer a descendant and cannot be signalled.  
Evidence: Process-tree stop cannot see processes reparented to launchd.  
Fix: Not fully solvable without a privileged helper. The unsettled error covers descendants that were seen and could not be killed.  
Status: Mitigated. Descendants are sampled about every 15ms and signalled even after they are reparented. A double-fork that finishes before that sample can still escape.

### AUD-011

Category: Release engineering  
Severity: P1 for public distribution, not a logic defect  
Problem: Local builds are ad-hoc signed. `spctl` will not treat them as a normal download.  
Evidence: `scripts/build-app.sh` signs with `-` unless `--distribution` is passed with `VIPER_SIGN_IDENTITY` and `VIPER_NOTARY_PROFILE`.  
Fix: The distribution path already checks for a universal binary, hardened runtime, notarization, and stapling. It cannot be completed in this environment.  
Status: Open until credentials are supplied

### AUD-012

Category: Product safety  
Severity: P2  
Problem: Junk ownership for folders that are not bundle identifiers is still a name heuristic. A running app whose cache folder does not match its bundle id or a long-enough name prefix can be offered for deletion. It is not preselected unless the match is exact.  
Evidence: `JunkScanner.runningOwner`. Default `preselectRebuildableItems` is false. Execution rechecks the same heuristic.  
Status: Mitigated. A running bundle id such as `com.openai.codex` now keeps a `Codex` cache even when the app’s display name does not match. At delete time, a folder any process has open is left in place. A cache whose name shares nothing with the app, and that the app does not currently have open, can still be selected.

### AUD-013

Category: Product safety  
Severity: P2  
Problem: An app with more than 200,000 files is removed from the root identity only. The review warning says files added inside it after confirm are removed with it. Related data files that exceed the fingerprint limit are omitted entirely.  
Evidence: `RemovalSignature` and `testOversizedAppCanStillBeRemoved`.  
Status: Mitigated. A truncated review now fingerprints the app and the folders directly inside it, so a change there cancels removal. The review text says files added deeper inside a huge app can still go with it.

### AUD-014

Category: Testing  
Severity: P2  
Problem: There is no UI or VoiceOver automation. Install, update, and uninstall execution against real Homebrew, npm, and the real Trash was not run in this pass.  
Status: Open. Fixture coverage is the regression net.

### AUD-015

Category: Maintainability  
Severity: P4  
Problem: `AppSettings.theme` is still decoded, and `applyAppearance()` always applies dark Aqua. The Settings screen no longer offers a theme picker.  
Status: Open, harmless. Removing the key is unnecessary for compatibility.

## Pass notes

| Pass | Result |
| --- | --- |
| Build | `swift build` clean. `swift test` 94/94. Package is SwiftPM, macOS 14+, no third-party dependencies. |
| Functional | Core fixtures cover scan, policy, uninstall, cleanup, catalog, journals, and command execution. GUI flows were read, not clicked. |
| State | Queue cancellation and per-item safety switch added. In-memory scans still clear on folder change. |
| Architecture | Boundary between core and UI is sound. Coordinator is large but not circular. |
| Security | No shell interpolation. Environment allowlist omits `SSH_AUTH_SOCK`. Link allowlist added. No secrets in the tree. |
| Supply chain | No package dependencies. Catalog icons are bundled; sources are listed in `Resources/CatalogIcons/SOURCES.json`. |
| Data integrity | Write-ahead removal transactions remain. Put-back no longer trusts `fileExists`. Journal file is fsynced. |
| Errors | Package timeouts and unsettled trees have distinct copy. Journal failure stops the rest of a queue. |
| Performance | Not measured with Instruments this pass. Scans stay off the main actor and skip other volumes and symlinks. |
| Accessibility | Focus rings and toggle/selected traits added in code. Contrast and VoiceOver were not measured on a running window. |
| Network | Installs and updates are user-started, serial, and revalidated. No telemetry. |
| Release | CI workflow runs `swift test` on macOS 14. Notarization remains a credential step. |

## Final review

### 1. Production readiness

Fit for a signed beta of the read-only and reviewed-change flows. Not ready to ship as a downloaded commercial build until AUD-011 is done, and not ready to call the interface fully accessibility-tested until AUD-006 is exercised in the app.

### 2. Release blockers

No open P0. AUD-011 is the remaining distribution blocker. It is external to the code: run `bash scripts/build-app.sh release --distribution` with `VIPER_SIGN_IDENTITY` and `VIPER_NOTARY_PROFILE`.

### 3. Architecture

Strength: policy, fingerprints, and package execution are outside the views and are unit-tested. Weakness: one main-actor model owns every feature flag. That is acceptable at this size. A second mutation type should go through `ReviewedChangePolicy` and the same busy flags rather than a new boolean.

### 4. Security

Command execution is an allowlisted executable plus an argument array. Links opened from the UI are scheme-checked. Journals are mode `0600` in a `0700` directory. Viper does not read the TCC database. Residual risk is a malicious executable already on the user’s PATH, which is the same tool Terminal would run, and a double-forked child after a forced stop (AUD-010).

### 5. Reliability

Removals journal the plan before the first Trash move and record each outcome. Crash recovery surfaces unfinished transactions at launch. Queued package work does not start after the safety switch is turned off. The active package command is still allowed to finish, because killing Homebrew or npm mid-transaction is more dangerous than letting it end.

### 6. Performance

No new hot path was added except descendant listing when a command is stopped. Scan behavior is unchanged aside from trusting `lstat` for regular files. Startup, scan peaks, and idle energy were not measured in this pass.

### 7. UX

Read-only mode now matches the copy: waiting work is cancelled, and the running item finishes. Put back is disabled while another change is running. Reset no longer leaves a stale scan folder selected. Empty, error, and progress states already exist on the main pages; they were not re-walked in a window.

### 8. Accessibility

Keyboard focus is represented in code. VoiceOver labels already exist on the main actions. This pass did not run VoiceOver, Zoom, or Increase Contrast.

### 9. Testing

94 unit tests, all passing, including the new safety, link, put-back, and process-tree cases. No UI test target. Do not treat that as coverage of layout or of real package-manager transactions.

### 10. Technical debt

- Operation coordinator instead of scattered busy flags, if a new mutation source is added.
- Ownership recipes for junk folders that are not bundle identifiers (AUD-012).
- UI tests for keyboard order and the safety-mode switch.
- Directory fsync for journals if a power-loss test ever shows a torn directory entry.

### 11. Production checklist

| Category | Result |
| --- | --- |
| Build reproducible from README | Pass |
| Unit tests | Pass (94) |
| Compiler warnings | Pass (none) |
| P0 defects | Pass (none known) |
| Safety switch enforced for waiting work | Pass |
| Secrets in source | Pass (none found) |
| Link open allowlist | Pass |
| Crash journal for removals | Pass |
| UI / VoiceOver on device | Fail (not run) |
| Developer ID notarization | Fail (credentials required) |
| Real Homebrew/npm mutation on a disposable Mac | Fail (not run) |

## Definition of done

Known P0 issues: none.  
P1 issues: AUD-011 remains and is justified — it needs the publisher’s Apple credentials, and the script already refuses to pretend a local signature is a release.  
Core flows covered by fixtures behave as the safety copy describes, including the cases fixed above.  
State for waiting package work and later removal items follows the safety switch.  
Failures from a stopped command are visible when the process tree does not die.  
Public distribution still requires notarization and a manual accessibility pass.
