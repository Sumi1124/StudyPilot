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
