# In-app updates

## Live calendar and unfinished-task answers (1.28.0)

- “What tasks do I have left?” and similar reminders now read actual unfinished assignments and selected calendar deadlines directly, excluding completed local work.
- Selecting Codex no longer turns off calendar/task context. Context settings persist, while earlier chat history and Codex memory remain separate. The previously forced-off study-context default is migrated once.
- The Codex extension also receives fresh relevant workspace records for task/calendar questions, with visible context controls.
- Chat shows calendar connection status and explains when assignment calendars still need selecting. A “What’s left?” shortcut opens the remaining-work question.
- External deadlines retain the explicit unknown-completion label; they are not silently marked finished.

## Codex sign-in connection fix (1.27.2)

- Fixes network restrictions that prevented hostname lookup and certificate initialization during Codex sign-in.
- Allows only the macOS DNS service socket paths and supplies the system's public certificate bundle to Codex. HTTPS certificate verification remains enabled; personal-file, command and memory restrictions remain in place.
- Adds an optional live connectivity regression check using a fresh, signed-out Codex process. It requests and cancels a temporary device login without signing in or printing codes.

## Codex as an alternative AI provider (1.27.1)

- Choose Codex alongside Apple Intelligence and optional Qwen in Settings → AI model.
- Use Codex for study chat, time estimates, planning advice and notebook questions with your own ChatGPT sign-in and selected model.
- Each provider request uses a fresh ephemeral conversation with memory reading and generation disabled. Earlier chats are never attached. Codex study-chat history is stored separately on this Mac.
- Calendar and saved-study context start off when selecting Codex; attachments and context are explicitly chosen. Feature-specific notices describe the task details, availability totals or excerpts sent to OpenAI.
- Existing calendar review and validation still apply. Codex's separate extension chat and file approvals remain available.
- 128 local tests pass. Signed-out app-server probes verify memory settings, ephemeral request support and exclusion from saved history. Authenticated model responses and two-account live tests remain unverified.

## Explicit Codex integration restrictions (1.26.1)

Codex connected apps, plugins, unified command execution and code-mode hosts are explicitly disabled. This prevents its default integrations from expanding the study extension’s access. The reviewed study tools introduced in 1.26.0 remain available.

## Reviewed Codex study tools (1.26.0)

Share copies of text files with an individual Codex conversation. Reading a shared file, counting words, finding passages and changing its contents each require approval. File edits show the complete before/after text and affect only the shared copy; Save copy exports to a location the student chooses. Approvals are bound to one account, conversation and turn, expire after two minutes, and cannot be replayed. Unchecked files are unavailable to tools. Shell commands, arbitrary file paths and network tools remain blocked. Sessions lock after 30 minutes idle; switching off Codex discards shared-file copies and pending permissions.

## Private Codex extension (1.25.0)

Optional Codex chat now appears in the sidebar with individual ChatGPT sign-in, a model selector, streamed replies, saved conversations, and explicit note selection. Each student uses a separate macOS login. The Codex process is confined to its own data folder by a macOS sandbox; commands, file edits, and permission expansion remain disabled. Account changes invalidate the old session, logout waits for process exit before deleting local data, and private workspace ownership and sharing permissions are checked at startup. See [Codex setup and limitations](CODEX-EXTENSION.md).

## A livelier study companion (1.24.0)

The optional companion now reacts briefly to food, play, and rest. Choose an apple, onigiri, or toast for one study ticket each. Its appearance changes at Explorer and Study buddy milestones, while its growth and ticket balance continue to come from recorded focus sessions. Care actions stay in the Focus screen and remain optional.

## Food tickets for studying (1.23.1)

Every 25 minutes of completed Focus time earns one food ticket. Short completed sessions add together; breaks and unfinished sessions do not earn tickets. Feeding the companion spends one ticket, while play and rest remain free. Focus shows the ticket balance and time until the next ticket. Previously recorded completed focus time counts, and hiding the companion keeps the balance.

## Optional study companion and update notice (1.23.0)

Settings → Study companion enables an original little creature in Focus. Give it a name, offer a snack, play, or rest. Completed focus sessions help it grow through three stages; it never loses progress or sends reminders. It starts off and can be hidden at any time.

StudyPilot now quietly checks the signed update feed when the workspace opens or becomes active. When a newer build exists, the sidebar and toolbar show an update notice that opens the existing in-app Sparkle installer. Settings also shows the available version. The notice does not start installation by itself.

## Notebook PDF import (1.22.1)

Notebooks now put a direct Import PDF or text button beside the source list. The file picker no longer disables PDFs whose macOS file type metadata is unusual; StudyPilot validates the chosen file itself. The import accepts PDFs up to 100 MB and 500 pages and up to 1 MB of extracted text per source. Import errors remain visible beside the button after the file picker closes. The app also tells you when image-only pages were skipped; a fully scanned PDF needs text recognition before import. PDFs remain on your Mac; the notebook stores a searchable text copy.

## Accent colors (1.22.0)

Settings → Appearance now offers six accent colors and a macOS color wheel for a custom choice, with a quicker menu in the toolbar. The selected color persists across launches and is shared by primary controls and highlights in Light and Dark mode. Custom colors are adjusted for readable contrast on each appearance.

## Today screen and agenda (1.21.0)

Today uses a compact header and one status strip, with the schedule visible before notebooks and extras. Study blocks tied to the same task are grouped by day; expand one group to see and complete individual sessions. The sidebar and cards use flatter, quieter surfaces.

Settings → App updates → Check for Updates (also in the StudyPilot application menu) uses Sparkle 2.10.0. The native update window downloads, verifies the Ed25519 signature, installs and relaunches. Automatic checks start disabled. Finish an active focus session before checking. Workspace data remains in Application Support.

The appcast is hosted at `https://raw.githubusercontent.com/Sumi1124/StudyPilot/main/updates/appcast.xml`. Archives are immutable GitHub Release assets. The public verification key is embedded in Info.plist. The private key is deliberately outside this source tree in the original development workspace’s `work/updater-signing-private.key`; preserve it securely. Never commit that key. Only its owner can sign future updates trusted by this app.

To release an update: increment both bundle version fields, push the source, let the GitHub release workflow build the Apple Silicon archive, then download that exact release archive and run Sparkle’s `bin/sign_update --ed-key-file /secure/path/to/key StudyPilot-macOS.zip`. Alternatively run `python3 Scripts/sign-release.py /path/to/release.zip /secure/path/to/private.key` to verify the signature and generate the feed. Add the returned signature and length to the feed alongside the new version and release URL. Commit the feed only after signing and verifying the archive. Do not modify a published archive. Public release builds are ad-hoc signed; Developer ID signing and notarization remain necessary for trusted broad distribution.

Install version 1.3.0 manually once to gain the updater. Versions before 1.3 have no updater. The feed’s initial item points to the installed version, so checks should report that it is current until a newer signed version is released.

## Testing 1.3.0 → 1.3.1

Open the existing 1.3.0 app. In Settings → App updates, choose Check for Updates, then follow the native Download/Install and Relaunch prompts. After relaunch, Settings should show 1.3.1 and the main toolbar should have a sun/moon Appearance menu. Light and Dark apply immediately and persist after reopening. Finish any active focus timer before checking for updates.

## Settings sheet fix (1.3.2)

AppKit can refuse termination while a SwiftUI sheet remains attached. In versions 1.3.0–1.3.1, close Settings with Done before Install and Relaunch. Version 1.3.2 dismisses Settings before starting Sparkle and prevents opening new workspace sheets during the update session. Other open editors are preserved and must be closed first.

Version 1.3.3 also waits for AppKit’s sheet animation to finish; 1.3.2 could show a close-editor message too early. Use the application-menu Check for Updates with Settings closed when updating from 1.3.2.

## Guided first study loop (1.15.0)

Version 1.15.0 adds a short first-run setup for entering a deadline, choosing calendar availability, building a study plan, and starting focus. An optional sample workspace avoids empty sections without changing existing workspaces. The Today view keeps the next step visible until the first deadline → plan → focus loop is complete. Assignment and planner time estimates accept long projects and display the full minute value while editing.

## AI schedule coach (1.16.0)

Version 1.16.0 adds optional AI planning help inside Plan my study. Apple Intelligence or the optional local Qwen model can recommend session length, daily load, and planning horizon from selected deadlines, remaining minutes, subjects, and anonymized free-time totals. The recommendation is review-only until the student presses Use these settings; StudyPilot's deterministic planner still places sessions, checks conflicts, and requires an explicit save. Calendar event names are not included in the coaching request, and the coach is instructed not to solve assignments or generate schoolwork.

## Adaptive interface system (1.17.0)

Version 1.17.0 introduces one adaptive StudyPilot visual language across light and dark appearances. It adds a responsive Today hero, stronger information hierarchy, richer but restrained surfaces, unified brand color, clearer progress and workload visuals, upgraded notebook tiles, a more legible sidebar primary action, and a polished three-step planner. Wide windows now use a centered workspace composition instead of stretching controls into empty space.

## Clearer school calendar (1.18.0)

Version 1.18.0 reorganizes Calendar around the questions students need answered: what is due, when to study, what else is happening, and what to check off next. The header now has direct planning and event actions, simpler List/Week/Month switching, search and active-item filtering, a clear legend, and more understandable connection status. Week and Month cells show compact previews with overflow counts instead of trying to display every item. Selecting a day opens grouped sections for deadlines, study blocks, and other calendar events, with completion controls and readable time badges. Month synchronization now covers every visible day rather than only the selected date.

## Repeated calendar items (1.18.1)

Version 1.18.1 groups same titled study sessions and other calendar events within each day. A topic such as Math sheet appears once with its session count and combined study time. Expand it to see each time slot and check off individual sessions. Week and Month cells also show the title once with a compact count badge.

## IB MYP and DP workspace (1.19.0)

Version 1.19.0 adds a school programme choice in Settings. MYP assignments can be tagged as class tasks, assessments, or Personal Project work while retaining criteria A–D. DP assignments can be tagged as coursework, internal assessments, Extended Essay, Theory of Knowledge, CAS, or exams. The Assignments screen adds a work type filter and workload summary. Academic progress shows the existing MYP criterion view for MYP students and a DP deadline and core work overview for DP students. Tags are stored with assignment records and included in existing JSON backups. These are personal planning tools, not official IB grade calculations.

Version 1.19.1 also accepts IB work type tags during JSON backup validation, so tagged assignments export and restore correctly.

## In-app local model setup (1.20.0)

Version 1.20.0 makes Download 0.8B model available when the local service is stopped. It starts an installed Ollama runtime automatically. If the runtime is missing or too old for Qwen 3.5, StudyPilot downloads a pinned official macOS runtime archive, verifies its SHA-256 checksum, unpacks it inside Application Support, starts it on a separate loopback port, and continues the model download with progress in Settings. The model remains optional, and StudyPilot does not install a system-wide runtime or open a browser for setup.
