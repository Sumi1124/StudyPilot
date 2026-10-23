# In-app updates

Settings → App updates → Check for Updates (also in the StudyPilot application menu) uses Sparkle 2.10.0. The native update window downloads, verifies the Ed25519 signature, installs and relaunches. Automatic checks start disabled. Finish an active focus session before checking. Workspace data remains in Application Support.

The appcast is hosted at `https://raw.githubusercontent.com/Sumi1124/StudyPilot/main/updates/appcast.xml`. Archives are immutable GitHub Release assets. The public verification key is embedded in Info.plist. The private key is deliberately outside this source tree in the original development workspace’s `work/updater-signing-private.key`; preserve it securely. Never commit that key. Only its owner can sign future updates trusted by this app.

To release an update: increment both bundle version fields, push the source, let the GitHub release workflow build the Apple Silicon archive, then download that exact release archive and run Sparkle’s `bin/sign_update --ed-key-file /secure/path/to/key StudyPilot-macOS.zip`. Add the returned signature and length to the feed alongside the new version and release URL. Commit the feed only after signing and verifying the archive. Do not modify a published archive. Public release builds are ad-hoc signed; Developer ID signing and notarization remain necessary for trusted broad distribution.

Install version 1.3.0 manually once to gain the updater. Versions before 1.3 have no updater. The feed’s initial item points to the installed version, so checks should report that it is current until a newer signed version is released.
