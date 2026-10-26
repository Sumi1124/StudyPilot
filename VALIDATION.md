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

The final local release build passed without compiler warnings after avoiding a Swift 6.2.3 closure-conversion compiler crash. All 49 tests passed. GitHub Actions built and published 1.4.0 build 9. The exact released archive matched GitHub's SHA-256 digest, passed bundle-signature verification, and was signed and verified for Sparkle with the existing update key. No update was initiated in the user's installed app. Native UI and real Google mutation checks for this feature remain unperformed.

## Version 1.5.0 — on-device study chat

53 core/data tests passed, including chat-history round trips, attachment preservation, bounded recent context, and rejection of malformed roles, duplicate IDs, empty messages, and excessive input. Saved chat JSON is separate from the eleven-type workspace backup. New messages are saved before generation, canceled requests cannot append replies, failures retain the question for retry, and corrupt history is preserved rather than overwritten. UI supports explicit single-item attachments, saved threads, Stop, Retry, Copy, Save to Notes, and confirmed deletion. No remote model endpoint or API credential is used.

The complete optimized local release app compiled successfully and passed signature verification. A standalone smoke run using the exact chat prompt builder and instructions received a real, nonempty answer from Apple's Foundation Models about equivalent fractions. The first sandboxed invocation was denied access to ModelManager; the permitted native-service run succeeded. A native UI walkthrough was attempted in a separate QA bundle/data folder but could not proceed because the Mac was locked. Visual layout, Save to Notes, and interactive cancellation still need a manual walkthrough. The user's production workspace and app were not used for sample chat content.

GitHub Actions also built and published 1.5.0 build 10. The exact published archive matched GitHub's SHA-256 digest `e39f179ce4badc1e3e0bdec887a8be28addde67900e3ac67e20589074086a4cc`, passed app-signature verification, and was signed and verified with the existing Sparkle update key. The installed app is left for the user to update.

## Version 1.6.0 — calendar reading and reviewed moves in chat

58 core/data tests passed. New coverage checks structured answer/move decoding, automatic-slot requests, malformed action rejection, strict dates and DST gaps, past/conflicting/read-only/deadline-violating moves, bounded current snapshots, and current-snapshot alias mapping. Local optimized app compilation passed.

A separate integration harness exercised the actual CalendarChatService with an in-memory SwiftData workspace and calendar access disabled. Verified: proposing a move leaves data unchanged; a newly inserted conflict prevents Apply; removing that conflict permits one move; the event keeps its duration and reminder lead time; assignment deadlines remain unchanged; duplicate Apply fails; editing the event invalidates its old proposal. Notification reconciliation was stubbed only in this harness. No user calendar was modified.

Apple's real local model parsed “Move Math study to tomorrow at 5pm” against a fictional current calendar snapshot into the correct event alias and exact next-day 17:00 timestamp. Structured output decoded successfully. Live Google writes, cross-device synchronization, and native UI interaction still require a walkthrough; automated safety checks do not establish those results.

## Version 1.6.1 — empty-calendar answer refinement

Native UI walkthrough in the isolated QA workspace confirmed the calendar controls, current range, empty local-calendar count, saved conversation, thinking/Stop state, and a real local-model reply. It exposed an unhelpful request to narrow an empty calendar when Google was not connected. The instructions now explicitly distinguish zero local events from disconnected external calendars, and only request narrowing when events were omitted. All 58 core/data tests passed again. Google write/sync and the native move-preview interaction remain untested; the actual coordinator's move workflow was exercised by the isolated integration harness above.

The final local 1.6.1 build passed signature validation. The revised model smoke check passed both a fictional next-day 17:00 move proposal and an empty-local-calendar question without the earlier narrowing request. GitHub Actions published 1.6.1 build 12. The exact released archive matched GitHub's SHA-256 `b00eeeece303d00433a0a4d9ac488518a01e1c0db5819f1d69284b6d098219f6`, passed bundle-signature verification, and was signed and verified for Sparkle with the existing update key. The installed production app was not changed.

## Version 1.7.0 — subject-aware retrieval and reliable conversation output

68 core/data tests passed. New coverage includes math-to-quadratic matching with and without saved subject labels, common topic families, Unicode subject names, missing-letter and transposition typos, true subject-label precedence, task-versus-note intent, generic assignment questions, follow-up references, subject switching, bounded excerpts, long-reply history retention, and move-intent gating including negations and misspelled rescheduling requests.

A real-model regression exposed a separate defect: Apple correctly answered the math question in plain text, but the old calendar JSON parser rejected the answer. Calendar chat now uses Foundation Models' dynamic generation schema for separate reply/action fields. An ordinary question is constrained to no action; move requests may choose only aliases from the current calendar. Output fields are read directly, then validated by the existing action checks.

The real Apple model passed a four-part fictional conversation using the new generation helper: “What maths task do I have?” identified Quadratic equations; “Move it to tomorrow at 5pm” selected the correct event and exact next-day 17:00 time; “quadrtic task” identified Quadratic equations; the same task was found with an empty calendar using the real study-item list. No model substitution or cloud endpoint was introduced.

The actual CalendarChatService integration harness also verified saved-task retrieval by subject and inheritance of the assignment's Mathematics label by a generically titled linked study event, alongside preview immutability, fresh-conflict rejection, one-time Apply, preserved reminder timing/deadlines, and stale-event rejection. All data was isolated/in-memory. No live Google events were moved. New UI controls still need a native walkthrough; the previous native UI observations refer to 1.6.

The final optimized local build and GitHub Actions release build succeeded. The exact 1.7.0 build 13 archive matched GitHub's SHA-256 `4e09635e6e9a61e4430be491864e0e1a819337c33f3e8480b676283b96584f75`, passed bundle-signature verification, and was signed and verified using the existing Sparkle key. Production student data and the installed app were not modified.

## Version 1.8.0 — daily workflow and grounded workspace answers

80 core/data tests passed. New checks cover task/calendar question routing, educational/action/unsupported-range exclusions, subject filtering before next-deadline selection, exact title matching, completed-task exclusion, tomorrow/overdue boundaries, unknown completion for external deadlines, scoped follow-ups, ambiguous references, seven-day workload totals, DST day boundaries, default deadlines, and backward-compatible chat/source metadata. Tutoring-mode tests ensure standalone math questions avoid irrelevant calendar context while task-specific help can still use saved material.

The full local optimized macOS app compiled successfully and passed signature validation. Workspace record schema is unchanged; optional chat sources, answer kind and fact scope live in the separate chat JSON file.

Native UI checks used a separate bundle ID and a separate seeded QA database. Quick-add saved a new task and updated workload from 105 to 135 minutes. Completing Quadratic equations removed its 45 minutes and displayed Undo; Undo restored the task and workload. Review overdue selected the Overdue filter and showed only the seeded Essay draft. Chat's Due today prompt immediately returned the one correct local task, actual deadline, and explicit Google scope. Expanding Saved records and clicking its source opened the correct assignment editor despite the existing overdue filter. The compact chat layout and Context & sources popover were inspected in dark mode.

A native tutoring check exposed calendar-context bias: the model pointed to a task rather than solving the expression. Standalone tutoring is now routed to the general study model with direct-answer/checking instructions and no irrelevant calendar snapshot. A subsequent real-model smoke check, including a previous task conversation, correctly factored x^2 - 5x + 6 into (x - 2)(x - 3), expanded to x^2 - 3x - 2x + 6, and checked the result. This is evidence for that sample, not a guarantee of general AI correctness. Real Google event writes/sync and long-duration focus behavior were not exercised in this update. Production data and the installed app were left untouched.

## Version 1.8.1 — conservative exact-answer routing

Before enabling the update feed, tightened the direct-answer boundary: unrecognized qualifiers are left to the conversational assistant rather than being interpreted as a title filter and falsely producing an exact empty calendar. A pronoun without one clear source also falls back to clarification instead of listing all tasks as though they were the referenced one. Two additional regression tests cover these cases. This patch contains the full 1.8 workflow/UI changes above.

All 82 core/data tests passed. The final optimized 1.8.1 app compiled and its bundle signature and plist/project syntax validated. An isolated in-memory integration harness verified that disabling calendar context prevents external calendar refresh while still returning the correct saved Mathematics assignment, that disabling both sources returns enablement guidance, and that calendar questions honor the calendar toggle. The same harness passed move-preview immutability, fresh-conflict rejection, single Apply, reminder preservation, unchanged assignment deadlines, and stale-event rejection. No external calendar reads or writes were needed for this harness.

GitHub Actions built and published 1.8.1 build 15 successfully. The exact public release archive matched GitHub's SHA-256 `c3769ae740964909af4126a406c8eadf2132c8f7c4620d65b9db3c0f00dedceb`, passed deep/strict bundle-signature verification, contained the existing Sparkle verification key, and was signed and verified with that key for the update feed. The installed production app was left for the user to update.

## Version 1.8.2 — guided study planner

Replaced the long planner sheet with three focused steps: Assignments, Study time, and Review. The calendar grid is now above synced details and the session checklist. No scheduling, record-schema, chat, or updater logic changed. Deadline-calendar choices now refresh their events immediately rather than showing a candidate list from the previous selection.

All 82 existing core/data tests passed, including planning conflicts, deadline allocation, existing-session accounting, and completion/rescheduling coverage. The optimized app compiled and passed bundle-signature verification. Native testing used a separate bundle ID, seeded database, and disabled automatic rescheduling. Search for Biology showed only Biology lab; Clear shown changed only that task and reduced selection from 135 to 75 minutes, and Select shown restored 135. Deselecting all study days showed a specific message and disabled Preview. The generated preview showed three Biology sessions totaling 60 minutes, explicit unscheduled-work reasons, correct breaks, and date grouping. Choosing a synced destination without connection displayed setup guidance and disabled Add. Saving locally showed success; View calendar selected October 27 with the three expected Biology sessions. Assignment and study-time layouts, fixed action bar, source disclosure, and review were inspected in dark mode; assignments were also inspected in light mode. Final polish makes the local save destination explicit in the button, uses a full-width destination card, and changes the footer to saved-state copy after success.

Production data and the installed app were not changed. No live Google write/sync or connection-permission flow was exercised. The existing EventKit commit/conflict validation remains in place.

The final optimized local build and GitHub Actions build both succeeded. The exact 1.8.2 build 16 release archive matched GitHub's SHA-256 `9f55af9aee30a30c196a0bdef844708b12ac24c22572af5daf28b39bb85ec792`, passed deep/strict bundle verification, contained the existing updater public key, and was signed and verified for Sparkle. The installed app is left for the user to update.
