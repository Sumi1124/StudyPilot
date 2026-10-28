# In-app updates

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
