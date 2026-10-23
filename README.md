# StudyPilot

A native, offline student workspace for Apple Silicon Macs running macOS 14 or later. Built with Swift 6, SwiftUI, SwiftData, Charts, and UserNotifications. Core study features work offline without an account or paid API. Optional in-app updates use the Sparkle framework and an internet connection.

**Version 1.3 adds native signed in-app updates through Settings and the StudyPilot menu.** Version 1.2 added note-to-flashcard creation, bulk assignment updates, assignment focus shortcuts, and an adjustable daily study goal. Google Calendar study planning remains available. This optional connection uses Google calendars synced through macOS Calendar. Automatic scheduling works locally; AI time estimates and study steps use Apple Intelligence on supported Macs with macOS 26+. Google synchronization requires your Google account and connectivity.

## Run the application

Unzip **StudyPilot-macOS.zip**, then open **StudyPilot.app**. You can move it to Applications. The provided build is signed locally for development, not notarized for public distribution. A Developer ID certificate and notarization are needed for broadly distributing a trusted release.

The first launch creates a real SQLite-backed SwiftData database and five editable subject presets. Assignments, notes, results, and statistics start empty. No demonstration records are inserted.

## Build from source

### Xcode

1. Install Xcode 16 or newer (Swift 6 and the macOS SDK).
2. Open `StudyPilot.xcodeproj` and select the **StudyPilot** scheme and **My Mac**.
3. Press **⌘R**. The project references its two local Swift package libraries; it downloads the Sparkle updater dependency.

The target uses an ad-hoc signing identity for local development, without a team. Choose your own signing team and identity for distribution. The provided entitlements file is an optional starting point for a sandboxed distribution; the default local build is not sandboxed.

### Command-line build

From the source directory:

```sh
./Scripts/build-app.sh
open dist/StudyPilot.app
```

The script creates an optimized release app and its icon, Info.plist, privacy manifest, and ad-hoc signature. `swift build` also compiles the executable directly; use the app bundle to run the UI and notification integration.

```sh
./Scripts/test.sh
```

The test script supports both Xcode and standalone Command Line Tools. On this host, Apple's SwiftData macro plug-in and a Testing/Foundation overlay are missing from the Command Line Tools installation. The app therefore uses explicit SwiftData model conformances and a small live-fetch wrapper. The test script isolates the library tests and supplies the available Testing framework path. No dependency downloads or replacement data store are involved.

## Using your workspace

- **Overview:** real task counts, an interactive next-deadline countdown (or an all-caught-up state), overdue and today’s work, upcoming deadlines and exams, weekly planning, study hours, review counts, and study streak.
- **Assignments:** create and edit tasks; assign subjects/projects; set deadlines, reminders, priorities, statuses, estimates, criteria A–D, and subtasks. On supported Macs, ask Apple Intelligence to suggest editable checklist steps from an assignment title and description. Review each suggestion before saving; existing checklist items and the time estimate are preserved. Search, filter, sort, or mark complete. Right-click to delete with confirmation.
- **Calendar:** month and week views; select a day to inspect its items. Add examinations or study events. Drag assignment/event chips to another day; times of day and reminder lead times are preserved. The editing sheets also provide an accessible alternative to dragging.
- **Plan my study:** connect calendars, identify assignment deadlines, set study hours and a daily limit, request optional on-device AI estimates/steps, and generate a conflict-checked preview. Save the blocks locally or add them to a writable Google calendar. See `GOOGLE-CALENDAR.md` for setup and the complete workflow.
- **Notes:** create notebooks linked to subjects; write Markdown with automatic saving, tags, search, and preview. Use `[[Another note’s title]]` to connect notes. Existing matching notes and backlinks appear beneath the editor. Duplicate titles expose each matching note. Use unique titles for clearer links.
- **Revision:** create decks and question/answer cards. Review due cards, reveal the answer, and rate recall with Again/Hard/Good/Easy. Every rating saves history and a next review date. Right-click decks/cards for confirmed deletion.
- **Focus:** 25-minute Pomodoro, 50-minute, and custom 1–240 minute sessions; optional 5-minute breaks; pause/resume and save partial sessions. A timestamp-based timer recovers after relaunch and keeps accurate elapsed time while backgrounded. Breaks do not add study time.
- **Progress:** record individual criterion scores from 0 to 8; unassessed criteria remain blank. Inspect averages, trends, feedback, and the lowest recorded average. Set a personal target for each subject. These are unofficial progress estimates, never an official MYP grade calculation.
- **Subjects & projects:** rename and configure subjects, colors, icons, and targets, and organize related assignments into editable projects.

| Shortcut | Action |
| --- | --- |
| ⌘N | New assignment |
| ⇧⌘N | New note |
| ⌘K | Search assignments, note contents/tags, subjects, projects, decks, and actions |
| ⇧⌘F | Start a 25-minute focus session, or open an active session |
| ⇧⌘P | Open Google Calendar and study planning |
| ⌘1–8 | Navigate the eight workspace sections |
| ⌘, | Settings, reminders, and backups |
| Space | Reveal a flashcard answer |
| 1–4 | Rate a revealed flashcard |

## Storage, backups, and recovery

The standard local build stores data at:

```text
~/Library/Application Support/StudyPilot/StudyPilot.store
~/Library/Application Support/StudyPilot/Backups/
```

SQLite may also create `-wal` and `-shm` companions. Do not copy only the `.store` file while the app is running. Use JSON export for a portable, consistent snapshot.

**Settings → Export JSON** exports all eleven record types. JSON dates are milliseconds since the Unix epoch; the envelope has `version: 1`. Appearance, preferred name, notification permission, and a running timer are local preferences and are not part of a workspace export.

Calendar selections, study hours, and reviewed task estimates are stored in `CalendarPlanning.json` beside the database, outside the workspace JSON export. Google events remain in the account; the app does not copy them into the assignment database. Blocks saved with **Save in StudyPilot** are normal planner events and are included in backups. Blocks added to Google are managed in Apple/Google Calendar and are not mirrored as local planner events.

**Import / restore** validates the entire file before presenting confirmation. It replaces the workspace; it does not merge two workspaces. The app creates a safety backup first and reconciles IDs in one database save. Invalid IDs, broken references, unsupported versions, out-of-range scores, and malformed schedules are rejected before any changes. Import is unavailable during an active focus timer. The input limit is 50 MB and 100,000 records.

An automatic local backup is created on the first app launch each day. You can also create backups manually, reveal their folder, or restore one from Settings. Backups are never pruned automatically. Copy an export to another disk to protect against loss of this Mac.

If the database cannot open, the app displays the error and preserves the existing files instead of silently creating an empty store. For advanced recovery, quit the app, retain a copy of the database and its companions, move that original aside, launch a fresh workspace, and import a known-good JSON backup. Never discard the original before confirming the restored data.

## Defined scope

- Markdown preview supports headings, lists, quotes, emphasis, links, inline code, and Unicode mathematics. Source text is always preserved. There is no full LaTeX engine, attachment storage, or rich-text format conversion.
- Revision uses a documented SM-2-inspired scheduler, not Anki file compatibility or the FSRS algorithm. A review session visits its initial due-card queue once. Again cards become available in ten minutes, and may be reviewed in a subsequent session.
- Notes link by title. Renaming a note does not rewrite other notes. Subject folders are implemented as subject-linked notebooks and filters.
- Personal targets apply equally to all four criteria within a subject. Averages use recorded scores only and preserve zero scores.
- Focus time is credited to the session’s ending day. A study streak requires at least one recorded session of 60 seconds on each day, and can continue from yesterday. Manually moving the system clock backward is clamped; large forward clock changes count toward elapsed time.
- Reminders require permission through Settings. The app queues the nearest 48 assignment/event reminders, up to ten next deck reminders, and a focus completion. Opening the app or saving data refreshes the queue. macOS controls delivery, including Focus settings. A closed app does not continually refill its queue.
- Essential workspace features remain local. Google Calendar integration is optional and relies on macOS account synchronization; this release does not include direct Google OAuth, continuous background replanning, or automatic modification of existing calendar events. Collaboration and shared StudyPilot accounts are outside this release.

## Project map

See `ARCHITECTURE.md` for the data model and scheduling rules, `PROGRESS.md` for implementation status, and `VALIDATION.md` for the exact verification performed and remaining platform checks.

## New study shortcuts in 1.2

- **Notes → Make flashcards:** preview your note, write editable questions/answers, or automatically extract lines formatted as `Question :: Answer`. Save up to 100 cards into a new or existing deck. Duplicate question/answer pairs in that deck are skipped. This workflow is fully offline and does not require AI.
- **Assignments → Select assignments:** select visible tasks and update their status together or postpone them one calendar day. Deadline time and reminder lead time are preserved; filtering removes hidden items from the selection.
- **Assignment timer menu:** start a 25- or 50-minute session attributed to the assignment's subject. An existing timer is opened rather than replaced. Focus history remains subject-based.
- **Focus → Daily goal:** choose a goal from 15 to 480 minutes. Overview and Focus show progress from saved sessions for the current day. The default is an editable 60 minutes. Running sessions count once saved; breaks do not count. This preference stays on this Mac and is not part of JSON exports.

## App updates

Install 1.3.0 once to enable **Settings → App updates → Check for Updates**. Future signed releases download and install through the app’s native update window. See `UPDATES.md` for publishing and signing instructions.
