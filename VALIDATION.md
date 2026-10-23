# StudyPilot validation

Validation completed on 23 October 2026 with the delivered source and optimized release executable.

## Build environment and results

| Check | Result |
| --- | --- |
| Architecture | Apple Silicon / arm64 |
| Swift | Apple Swift 6.2.3 |
| SDK | macOS 26.2 |
| Host OS | Reports macOS 27.0.1, build 26A434 |
| Deployment target | macOS 14.0 |
| SwiftPM debug compilation | Passed |
| SwiftPM release compilation | Passed |
| Delivered `Scripts/build-app.sh` | Passed; creates optimized native `.app` |
| Delivered `Scripts/test.sh` | Passed: 37 tests, zero failures |
| Ad-hoc signature verification | Passed `codesign --verify --deep --strict` |
| Property-list validation | Project, Info.plist, privacy manifest passed `plutil -lint` |
| Xcode project references | Source/resource references and shared scheme checked |
| Full Xcode build | Not run: full Xcode is not installed |

The test script handles the installed Command Line Tools' incomplete Swift Testing/Foundation overlay. Persistence tests printed sandbox-related CoreData notification-registration messages, while all save, fetch, restore, and disk-reopen assertions passed. No test failures were ignored.

## Automated coverage

The 37 tests cover:

- Assignment completion/progress, overdue behavior, and calendar rescheduling that preserves the time of day and reminder lead time.
- Again/Hard/Good/Easy scheduling, interval/ease bounds, repeatable results, daylight-saving transitions, and recall accuracy.
- Focus pause/resume, serialized recovery, elapsed time, duration limits, and backward clock changes.
- Study streaks, unique study days, yesterday continuation, criterion averages that distinguish zero from missing data, and note-link parsing.
- JSON round trips for all eleven record types and Unicode text; rejection of malformed JSON, unsupported versions, duplicate IDs, orphan references, invalid scores, invalid schedules, and invalid durations.
- SQLite-backed assignment/note persistence after container reopen; all eleven record types restored and reopened from disk.
- Restore reconciliation by stable ID, removal of absent records, rejection before mutation, idempotent subject presets, and review history saved alongside the updated card schedule.
- Study-plan conflict avoidance, breaks, deadline/priority ordering, daily caps, explicit capacity shortfalls, past deadlines, selected weekdays, DST transitions, rounded start times, five-minute duration rounding, all-day busy events, and deterministic allocations.
- Existing future study blocks preventing duplicate allocation, past study not implying completion, and calendar task metadata preserving Unicode identifiers.
- Validated AI JSON suggestions and rejection of malformed, empty, or out-of-range estimates.
- Planned blocks surviving JSON backup/restore with their source-task identity and preventing duplicate scheduling afterward.

The tests operate on temporary or in-memory stores. They do not depend on a user's workspace or network access.

## Native UI checks

The app was launched as a native macOS application and inspected using accessibility state and screenshots. Test content was kept in an isolated QA store, excluded from both deliverables.

- Assignment creation and subtask entry updated the saved workspace and dashboard.
- A Markdown note, title, and tags saved automatically; preview rendered; content remained present after quitting and relaunching.
- A deck and question/answer card were created. Revealing the answer and choosing Good saved one review, changed the due count, displayed 100% recall for that review, and scheduled the next day.
- A focus session advanced, paused, and saved an explicitly confirmed partial session. History and time totals reflected the recorded 57 seconds; it did not produce a one-day study streak.
- Global search opened with Command-K, updated its result labels when the query changed, and Return opened the matching persisted note. The final search-label fix was checked in the release executable.
- Criterion A = 0 and B = 8 were saved with C/D unassessed. The cards, chart, history, and improvement guidance showed the correct values immediately.
- Settings created a local JSON backup. Restore presented the replacement confirmation and record count; cancellation left the workspace unchanged. Actual restore and disk persistence are covered by integration tests.
- Main-section keyboard shortcuts, calendar month/week controls, native light/dark presentation, and empty states were inspected.
- Version 1.1: opened the planner with ⇧⌘P, confirmed the Google setup instructions and editable study preferences, and requested a real on-device AI suggestion for an isolated test assignment. The available Apple model returned a 45-minute estimate and six study steps. The scheduler previewed 16:00–16:25 and 16:30–16:50, saved both blocks locally, and the dashboard showed two planned events. Generating again produced zero new blocks and recognized all 45 minutes as already scheduled. Closing and reopening the planner retained the estimate and AI steps.

The Foundation Models framework is weak-linked in the delivered executable, whose minimum OS load command remains macOS 14. Actual AI generation was exercised on this host; that does not establish model availability on every supported Mac.

Live query refresh initially exposed a runtime incompatibility between SwiftUI Query and the explicit model conformances in this environment. The delivered app uses `LiveQuery`, which observes saves and fetches through the same SwiftData ModelContext. The affected notes and revision flows were rerun successfully after that fix.

## Checks still requiring the target environment

- Google sign-in through macOS Calendar, actual calendar permissions, live event reads, and publication/synchronization to a Google account. No real Google event was created during testing.
- A full Xcode build and scheme run. The generated project is included and structurally validated; SwiftPM build success does not establish an Xcode build result.
- Runtime compatibility on macOS 14 itself. The deployment target is set to 14, but this host runs a newer OS.
- Notification permission and actual macOS delivery, including delivery while closed, Focus settings, and long queues.
- Extended real-world timer sleep/wake and multi-hour sessions. Clock/recovery logic is covered by deterministic tests, with a short native UI session checked.
- A full VoiceOver audit, very large workspace performance, and drag-and-drop interaction across calendar cells. Rescheduling calculations are tested and editing sheets provide an alternative.
- Developer ID signing, notarization, and App Store sandbox distribution. The local build is ad-hoc signed and does not include a distribution identity.

## Reproduce

From the extracted source directory:

```sh
./Scripts/test.sh
./Scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 dist/StudyPilot.app
plutil -lint StudyPilot.xcodeproj/project.pbxproj Resources/Info.plist Resources/PrivacyInfo.xcprivacy
```

Build caches default to `.build-local/`; set `STUDYPILOT_BUILD_DIR` to use another local directory. The app defaults to `~/Library/Application Support/StudyPilot/`. An advanced QA launch can pass `--data-directory /absolute/path/to/isolated-store`; do not use a production workspace for destructive tests.

## Version 1.2 verification — 23 October 2026

- 44 automated core/data tests passed. New tests cover flashcard line parsing and duplicate detection, daily study goals, visible-selection bulk actions, completion dates, and deadline shifts across daylight saving.
- The complete release macOS app compiled and was signed locally.
- The Xcode project was regenerated to include the new UI files.
- These new screens have not yet received a manual UI walkthrough; the earlier UI verification sections refer to earlier releases.

## Version 1.3 — updater validation

44 core/data tests passed locally. Local release compilation passed. GitHub Actions built the complete Apple Silicon app on macOS 26 and published v1.3.0. Downloaded the exact release asset, matched its SHA-256 with GitHub’s digest, signed and verified the archive using Sparkle’s Ed25519 tool, and confirmed the release embeds the matching public key and Sparkle framework. The local isolated GUI launch could not be completed in this environment; a full update-install/relaunch cycle has not been exercised.

## Version 1.3.1

The complete local macOS release build passed. The bundle and Xcode project validation passed. Confirmed build 5 sorts above 1.3.0 build 4, with identical embedded public verification key and feed URL. The user’s local 1.3.0 app remains in place for an actual in-app upgrade test. This release adds UI controls using the existing persisted appearance setting; no data schema changes.

## Version 1.3.2 — reproduced relaunch blockage

System logs confirmed `App termination blocked by modal sheet`. The downloaded archive’s EdDSA verification had succeeded. Using the live UI, closed Settings, brought Updating StudyPilot to the front, pressed Install and Relaunch, and confirmed the app restarted at 1.3.1 with the Appearance toolbar control. Local compilation passed for the 1.3.2 Settings-dismissal fix.

## Version 1.3.3 — native UI regression test

Local release compilation passed. Launched a separate QA bundle using a separate data directory and preference domain. Opened Settings and clicked Check for Updates: Settings dismissed, the native Sparkle “You’re up to date” result appeared, and dismissing it returned to the enabled workspace. The QA copy was then quit. This caught and corrected the early onDismiss guard failure in 1.3.2 before publishing 1.3.3. The real app also completed installation/relaunch from 1.3.1 to 1.3.2, preserving its existing workspace.

Final production verification: the installed main app detected 1.3.3, downloaded it, completed Install and Relaunch, and reopened on its existing workspace. Settings showed 1.3.3. Clicking Check for Updates from Settings dismissed the sheet and displayed Sparkle’s “You’re up to date! StudyPilot 1.3.3” result. Dismissing that result returned to an enabled overview with the saved assignments still visible. All 44 automated tests passed. GitHub’s feed cache briefly served 1.3.2 before propagating the new feed.

## Version 1.3.4

Local release compilation and app signature verification passed. Confirmed build 8 is newer than installed 1.3.3 build 7 and uses the same update-verification key. Copy Markdown copies the current note’s exact source as plain text and shows transient confirmation. The user’s running 1.3.3 app is deliberately not updated: the user will exercise the in-app upgrade and new button.

GitHub’s 1.3.4 release build also succeeded. Downloaded that exact archive, matched its SHA-256 to GitHub’s digest, verified the app bundle signature, and verified Sparkle’s update signature with the existing key. The signed feed is published separately; no update was initiated in the user’s app.

## Version 1.4.0 — completion and automatic rescheduling

49 automated tests cover ended versus active blocks, completed-block exclusion, metadata and backup round trips, idempotent checks after moving the same block, intact allocation around conflicts, daily caps, and capacity/deadline failures. Calendar and planner expose completion controls and the automatic-rescheduling preference. The shared service runs every minute while the app is open and on reopening, preserving block IDs and assignment deadlines. Local release build and signature validation are checked separately. Real Google event writes and prolonged sleep/wake behavior have not been exercised; no user calendar was mutated during development.
