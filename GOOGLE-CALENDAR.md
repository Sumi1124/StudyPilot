# Google Calendar → your study plan

Open **Calendar → Plan my study** in StudyPilot, or press **⇧⌘P**.

## Connect your assignments

1. In Apple Calendar, choose **Calendar → Add Account → Google**. Sign in and enable **Calendars**. If the Google account is already connected, check that your assignment calendars appear and finish syncing.
2. In StudyPilot's planner, choose **Connect calendars** and grant calendar access. macOS provides full calendar access for workflows that read events and add new ones; StudyPilot writes only when you choose to add a previewed plan.
3. Mark calendars that contain deadlines with **Assignments**. Keep your classes, activities, appointments, and other commitments checked under **Busy time**.
4. Select a writable calendar under **Add study blocks to**. Choose one belonging to your Google account if you want the study blocks to appear in Google Calendar. A school-owned assignment calendar may be read-only; your personal Google calendar can be the destination.

This is a native macOS calendar connection, not a Google sign-in embedded in StudyPilot. It requires no API key. [Google documents connecting its calendars to Apple Calendar](https://support.google.com/calendar/answer/99358).

## Generate what to do and when

1. Set your study hours, weekdays, session length, breaks, daily time limit, and planning horizon (7, 14, or 28 days). The app uses this Mac's time zone. The initial 16:00–20:00 window and two-hour daily limit are editable defaults.
2. Select the events that are actual assignments. A calendar may contain both deadlines and classes; only selected assignment events are treated as deadlines. Unselected events on busy calendars continue to reserve time. Completed StudyPilot assignments are excluded.
3. Review **remaining minutes** for each assignment. Google does not provide a reliable work-duration estimate, so new calendar assignments begin at 60 minutes. You can enter your own estimate or choose **AI estimate & steps**.
4. Choose **Generate study plan**. Earlier deadlines come first; priority breaks equal-deadline ties. The planner fits sessions into free time, inserts breaks, honors your daily cap, and shows any work that will not fit before its deadline.
5. Review the proposed dates, times, and assignments. Change the inputs and regenerate as needed.
6. Choose **Add to [calendar]** to create those blocks in your selected Google calendar, or **Save in StudyPilot** to keep them in the local calendar. These are separate destinations; the app does not make two copies.

New Google blocks are titled **Study: [assignment]**. Their notes contain the suggested study steps and an internal task identifier used to recognize existing sessions. Your original deadlines and other calendar events are preserved.

## The AI component

**AI estimate & steps** uses Apple's on-device Foundation Models, available with macOS 26+ on supported Macs when Apple Intelligence is enabled and the model is ready. The app displays the actual availability state. Older systems still support calendar connection and automatic scheduling using your estimates. Build with the macOS 26 SDK or newer to include the AI component; builds against older SDKs omit it.

The AI proposes how much work may remain and practical steps such as reviewing instructions, drafting, practicing, and checking. It receives the chosen assignment title and description on this Mac. Estimates are suggestions: review them against your teacher's instructions and what you have already completed. A deterministic scheduler places the accepted work into calendar gaps, so generated prose cannot bypass timing or conflict checks. [Apple's model documentation](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) describes the device availability requirements.

## Refreshing and replanning

- Calendar data comes from macOS's synced copy. Use **Calendar → View → Refresh Calendars** in Apple Calendar, then **Refresh calendars** in StudyPilot if recent Google changes are missing. Generating and adding a plan recheck the local calendar store; StudyPilot cannot prove that Google has finished syncing over the network.
- Upcoming StudyPilot blocks on the selected source/destination calendars count toward remaining work. Leave those calendars included when replanning. Repeated generation does not schedule the same remaining minutes again.
- Past blocks do not prove an assignment was completed. Reduce its remaining minutes, deselect it, or mark a local assignment done as you make progress.
- Plans round work up to five minutes. Most blocks are at least 15 minutes; a final five- or ten-minute remainder is allowed.
- Timed assignment events use their start time as the deadline. All-day assignment events use 23:59 on the last included day. Check the teacher's actual cutoff when their calendar entry does not specify one.
- Busy all-day events reserve the whole day. Free events and declined/cancelled invitations do not block study time.
- Existing blocks are not moved or deleted automatically. Edit or remove them in the calendar where you saved them, then refresh and regenerate. This release plans on demand and does not continuously reschedule in the background.

## Data and permissions

Google passwords stay with macOS/Google. The application uses EventKit and does not maintain Google OAuth tokens. Task selections, reviewed estimates, and study preferences are stored beside the local database in `CalendarPlanning.json`; event descriptions are not retained in that preferences file. These preferences are excluded from workspace JSON backup. Locally saved study events are included in workspace backup; Google events are managed by the Google account.

You can revoke access in **System Settings → Privacy & Security → Calendars**. Existing local features remain available. A new locally signed app build may require granting access again.

The implementation has scheduling tests and local UI verification. Real Google sign-in, provider synchronization, and adding events to your account require you to connect that account; no Google events were created during development verification.
