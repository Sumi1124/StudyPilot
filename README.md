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

## Version 1.3.1 appearance controls

Use the sun/moon Appearance menu in the main toolbar to choose Light mode, Dark mode, or Follow Mac appearance. The choice applies immediately and stays saved on this Mac. Settings → Appearance offers the same choices. The menu also provides ⇧⌘D to switch between Light and Dark.

## Version 1.3.2 updater fix

Check for Updates now closes Settings first, preventing the Settings sheet from blocking Install and Relaunch. If an editor is open, save or cancel it before checking. During an update, workspace actions are temporarily unavailable. In 1.3.0 or 1.3.1, close Settings before pressing Install and Relaunch if the update appears stuck.

Version 1.3.3 completes the updater fix by waiting for the Settings animation to finish. The Settings button has been checked in the native UI and now hands off to the updater without leaving a blocking sheet.

## Version 1.3.4 — Copy Markdown

Open a note and use **Copy Markdown** beside the word count to copy the note’s full Markdown source. The button briefly shows Copied. It works in Write and Preview modes and is unavailable for an empty note.

### AI Chat (1.5)

Choose **AI Chat** in the sidebar (⌘9). Ask for explanations, practice questions, feedback, or planning help. Attach one note or assignment to include up to 1,800 characters of its content; other workspace content is not included automatically. Send with ⌘Return. Stop cancels a reply; Retry reply retries the saved question. Copy answers or save them to Notes.

Uses Apple's Foundation Models on macOS 26 with Apple Intelligence enabled on a compatible Mac. No API keys, cloud chat provider, or web search. Saved conversations are stored in `StudyChats.json` beside the database and are separate from workspace JSON backups. Up to 50 conversations, 200 messages each. Recent history is included within a bounded context window; older turns may be omitted. Delete chat removes that conversation after confirmation. AI answers may be inaccurate and cannot directly edit calendars or assignments.

### Calendar-aware chat (1.6)

AI Chat now reads local events, assignment deadlines, and the synced calendars selected in **Plan my study**. Enable **Use my calendar**, connect calendars if needed, and choose the date range. Each message refreshes the snapshot. A bounded subset is sent to Apple's on-device model; omitted events are reported and the full calendar list remains available in the panel. No calendar data is sent to a cloud model.

Examples: “What is on my calendar today?”, “Move Math study to tomorrow at 5pm”, or “Move my next study block to the next free study slot.” Chat prepares one change at a time, shows the event and old/new times, and requires **Apply move**. It checks availability and the source event again before saving. It preserves duration and reminder timing, and rejects changes to assignment deadlines, completed study blocks, all-day/recurring/read-only events, and study blocks that would pass their deadline. An optional switch limits proposals to StudyPilot study blocks. Automatic slot finding uses configured study hours, breaks, and daily limits, for blocks up to two hours. Explicit times can be used for longer single events.

Google synchronization is handled by macOS Calendar. The selected busy calendars determine which commitments are protected. Calendar chat previews are temporary and cannot be replayed after an applied move. Chat does not create or delete events or perform bulk moves.

### Subject-aware conversations (1.7)

Chat can now search unfinished assignments and note titles using subject labels, related study topics, and minor spelling variations. “Math tasks” can find “Quadratic equations” without the word math in the title. Calendar events include their linked subject, and relevant events are prioritized when the model's context is limited. Inferred topic labels are suggestions; no subjects or assignments are changed automatically.

**Use my study tasks and note titles** controls this local retrieval and remembers your choice. Assignment descriptions are included only as short matching excerpts; note bodies still require an explicit attachment. Conversation history is compacted so one long answer does not remove every earlier reference. Follow-ups such as “move it tomorrow” use recent task context; changing to science starts a new subject search.

Calendar-enabled replies use Apple's guided generation instead of relying on handwritten JSON. Ordinary questions cannot select an event to move; calendar changes still require the existing reviewed Apply move flow. The underlying model remains Apple's on-device model, with its existing hardware and OS requirements.

### A more usable daily workspace (1.8)

- **Overview:** quick-add a task with its deadline, subject, and effort; switch Today/Tomorrow; see scheduled local/synced events; complete planned blocks; start focus; and review overdue assignments.
- **Deadline workload:** seven-day estimated effort for unfinished assignments, separate from booked study time. Select a day to open its calendar.
- **Assignments:** Any time / Overdue / Today / Tomorrow / Next 7 days filters, quick entry, Ask AI shortcuts, and a 90-second Undo button after completing or reopening a task. Undo refuses to overwrite a subsequent edit.
- **Calendar:** a collapsible study checklist and selected-day synced event list, with refresh and clear sync scope.
- **Chat:** collapsible conversation history, compact prompt shortcuts, and context settings in a popover. Replies can link back to saved tasks, notes, or calendar dates.

Common questions about unfinished tasks, subject-specific task lists, overdue work, upcoming deadlines, and today's/tomorrow's calendar are answered directly from records. These answers also work without Apple Intelligence. Selected assignment-calendar deadlines are included when connected; their completion is explicitly unknown. Source cards and timestamps show what was checked. Date/subject follow-ups retain their scope and ambiguous references are left for clarification.

General explanations still use Apple's on-device AI and can be wrong. Standalone tutoring questions avoid irrelevant calendar context, while questions about a student's attached or saved task can use its material. AI replies are labeled separately; their context cards describe provided material, not independent verification. Unsupported time ranges or open-ended reasoning are not labeled as direct saved-data answers.

### Easier study planning (1.8.2)

Plan my study now guides you through **Assignments → Study time → Review**. Search and select assignments, enter remaining effort, choose study days and hours, then preview sessions grouped by day. The bottom action bar keeps selection totals and the next action visible. Calendar setup is tucked into a disclosure with separate assignment and conflict columns; deadline-calendar selections refresh the candidate list immediately. Choose StudyPilot or a writable synced calendar before saving. Changing the destination requires a new preview so conflicts are checked. A confirmation screen links to the calendar after saving. The main Calendar shows its date grid before synced-event details and the study checklist.

### Session check-off and finished-task cleanup (1.9)

Calendar's selected-day list now has completion checkboxes. Checking a session marks only that session complete; it does not finish its assignment. **Finish task** marks the linked assignment finished and clears all linked StudyPilot study sessions, including past and checked sessions. This also works for calendar-origin tasks. Completing a saved assignment from its row, editor, or bulk status menu uses the same cleanup flow. Matching uses the stored task ID, never the title; source deadline events and unrelated calendar events are kept.

Sessions disappear from StudyPilot immediately. Actual deletion waits for the 90-second Undo window, so Undo restores the task and its sessions without recreating Google events. A saved queue catches up when the app reopens, even when automatic rescheduling is off. Synced removal requires calendar access and writable single events without attendees; failures are shown in Calendar and retried. Newly published session identifiers are registered so moved sessions can still be found. Legacy unregistered sessions are checked across all accessible calendars in the previous and next four years. Reopening a task after the Undo window does not recreate deleted sessions; generate a new plan if needed.

### Manual assignment steps (1.9.1)

Removed generated checklist steps from the assignment editor and the effort/step suggestion controls from Plan my study. Add your own checklist items and enter remaining minutes yourself. New study plans no longer copy earlier suggested steps into session notes. Existing assignment checklists and already-saved session notes are preserved. AI Chat remains available as a separate, explicit action; calendar scheduling, completion checkboxes, and finished-task cleanup continue to work.

### Weekly agenda and study routines (1.10)

Calendar opens with a seven-day **Agenda** starting on the selected date. A fixed header provides date navigation, search by event/task title or saved subject, and Hide completed. Local deadlines and events plus selected synced calendar entries share each day's list in time order, with all-day entries first. Overnight events appear on both affected days. Summary totals separate local deadlines from calendar events and timed-event minutes; they include classes and commitments, not just study sessions. The month/week grid continues to show StudyPilot items, with synced details in the selected day's agenda. Your view and completed filter are remembered.

Assignment rows now have expandable **manual checklists**. Tick individual items without opening the editor; completing a checklist does not automatically finish the assignment or clear its sessions.

In Plan my study → Study time, expand **My study routines** to save up to five named sets of study days, hours, session/break lengths, planning horizon and daily limit. Use applies a routine and requires a fresh preview. Saving the same name updates that routine. Removing a saved routine keeps your current hours. Routines do not change automatic-rescheduling preferences or calendar selections. No suggested steps are generated.
