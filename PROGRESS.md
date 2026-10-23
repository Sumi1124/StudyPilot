# StudyPilot implementation progress

Updated: 23 October 2026. All five implementation phases are complete within the scope documented in `README.md`. The native release application builds and runs on the available Apple Silicon Mac. Platform checks that could not be performed are listed below and in `VALIDATION.md`.

## Phase 1 — Foundation and assignments
Complete: native SwiftUI window and collapsible sidebar, keyboard navigation, eleven persistent SwiftData record types, real assignment CRUD, subtasks, priorities, statuses, estimates, criteria, sorting/filtering, subjects, and projects.

## Phase 2 — Planning
Complete: dashboard calculated from saved data, current and upcoming deadlines, study streak and hours, week/month calendar, examinations, custom study events, drag-to-reschedule, and local reminder scheduling with permission controls.

## Phase 3 — Knowledge and revision
Complete: subject-linked notebooks, Markdown editing and preview, autosave, tags/search, note links/backlinks, editable decks and cards, review sessions, recall statistics, saved history, and deterministic SM-2-inspired scheduling.

## Phase 4 — Focus and academic progress
Complete: preset/custom focus durations, pause/resume, optional breaks, timestamp-based recovery, partial-session saving, subject-based study history, daily/weekly Charts, criterion scores and trends, reflections, improvement guidance, and personal targets. Missing scores remain distinct from recorded zeros.

## Phase 5 — Reliability and delivery
Complete: global search and quick actions, light/dark appearance, native accessibility labels and keyboard controls, validated JSON export/import, local automatic/manual backups, safety copies before restore, destructive-action confirmation, explicit error handling, app icon, source documentation, build/test scripts, Xcode project, and optimized locally signed app bundle.

Verification: 37 automated tests pass, including disk reopen and restore of every record type and the new study scheduler. Debug and release compilation succeeded. Real UI checks covered notes, search, flashcard review, focus history, criterion entry/charts, and backup/restore confirmation. See `VALIDATION.md` for exact coverage.

## Version 1.1 — Google Calendar study planning

Implemented: EventKit access to Google calendars synced by macOS; separate deadline and busy calendar selection; editable work estimates; optional on-device AI time estimates and study steps; configurable study hours, weekdays, breaks, and daily limits; conflict-free deadline-first allocation; explicit overflow reporting; preview; local persistence or reviewed calendar publication; stale-preview checks; and recognition of previously scheduled work. The core database schema is unchanged. Setup instructions are in `GOOGLE-CALENDAR.md`.

Verified in the release UI: real Apple on-device AI generation, two scheduled blocks with a break, local save, dashboard update, zero duplicate blocks on a second generation, and restored estimates/steps when reopening the planner.

The real Google account connection, provider synchronization, and event publication require the user to connect their account. No Google event was created during development verification.

## Assignment checklist suggestions

Added an optional assignment-editor action that uses the same Apple on-device model to propose concrete checklist steps from the assignment title and description. Suggestions are appended as editable draft subtasks, duplicates are skipped, existing progress and time estimates are preserved, and the model output is not saved until the student saves the assignment. Unsupported devices retain the manual checklist workflow with a clear availability explanation.

## Overview deadline card

Added a live next-deadline card to the dashboard with an overdue state, relative time remaining, and a one-click path into the assignment. When no open assignments remain, it shows an all-caught-up state and a quick add action.

## Remaining platform and distribution checks

- Build and run the included project in full Xcode. Only Command Line Tools are installed on the available host; project structure, references, and property-list syntax were checked, but an Xcode build could not be executed.
- Run on macOS 14 hardware, exercise notification delivery with permission granted, and perform extended sleep/wake and VoiceOver checks.
- For public distribution, use the owner's Developer ID identity and notarize the release. The delivered bundle is ad-hoc signed for local development.

No unfinished placeholder screens or demonstration statistics are included. Deliberate smaller implementations (Markdown subset, Unicode math, SM-2-inspired scheduling, bounded reminder queue, and title-based note links) are described in `README.md`.

## Environment
Apple Silicon; Swift 6.2.3; macOS SDK 26.2; host reports macOS 27.0.1. Deployment target: macOS 14. Compilation and automated tests used Swift Package Manager and Apple's installed frameworks without third-party dependencies.

## Version 1.2 — Study workflow shortcuts

Implemented offline note-to-flashcard drafts with editable previews, existing/new deck selection, duplicate prevention and atomic saves; visible-selection bulk assignment status/postponement; subject-based focus shortcuts; and persistent, adjustable daily study goals on Overview and Focus. Existing database and backup schemas are unchanged.

Validation: 44 core/data tests passed, including local-day goal calculation, note parsing, selection isolation, completion history and daylight-saving reminder preservation.

Release compilation succeeded for version 1.2; new screen interactions still need a manual UI walkthrough.

## Version 1.3 — GitHub and native updates

Source uploaded to Sumi1124/StudyPilot. Integrated Sparkle 2.10.0 with a signed Ed25519 update feed, native Check for Updates controls in Settings and the application menu, and an Apple Silicon GitHub release build workflow. Public verification key embedded; private key kept outside the source tree. Automatic checks are disabled initially. Existing focus sessions must finish before a check can start.

## Version 1.3.1

Added a visible toolbar Appearance menu for Light, Dark, and System modes, plus a ⇧⌘D toggle. Uses the existing saved appearance preference. Version 1.3.1 uses bundle build 5, above version 1.3.0 build 4, for updater detection.
