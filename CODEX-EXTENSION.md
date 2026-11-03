# Codex extension (macOS local preview)

StudyPilot has no StudyPilot accounts, extension manager, server, or WebSocket
service. This optional integration adds a Codex section to the existing macOS
sidebar and a toggle in Settings. It is a **local preview**, not the remote
multi-user service described in the request.

For a shared Mac, create a separate **macOS login for each student**. Each login
opens its own StudyPilot database under that user's Application Support folder,
with the workspace folder set to owner-only permissions. Codex has a separate
process, account directory, and history under that same macOS login. Switching
students means switching macOS logins; switching the name in StudyPilot does
not switch users.

## Setup

1. Install the official Codex CLI (at `/opt/homebrew/bin/codex` or
   `/usr/local/bin/codex`) or ChatGPT for Mac with its bundled Codex CLI.
2. Open **Settings → Codex extension**, enable it, then open **Codex**.
3. Select **Connect with ChatGPT** and finish the official browser sign-in.
   StudyPilot never receives a password or copies Codex tokens from another app.
4. Choose a model in the **Model for new chats** menu, or leave **Codex default**.
   The menu comes from the app-server's `model/list` response. A model appearing
   there does not guarantee your account can use it; Codex reports access errors
   when a turn starts. Existing conversations retain their model.
5. Start a conversation. Check a note only when you want its text included in
   the next message. Unchecked notes and other StudyPilot data are not attached.
6. Use **Shared files → Choose text files**, then check the copies to share in a
   message. Files are UTF-8 text, up to 64 KB each, with at most 12 copies per
   connection. New conversations register the study tools. Review each read,
   word count, passage search or proposed edit, then approve once or reject.
   Edits update only the shared copy. **Save copy** exports to a chosen location.
   Removing a copy or disconnecting prevents future tool access; material already
   sent remains in that conversation.
7. **Disconnect and erase Codex data** calls `account/logout`, ends the process,
   and removes this macOS user's dedicated Codex home, workspace, and local
   conversation history. Disabling the extension stops the process but keeps the
   account and history so it can reconnect later.

The extension uses the official [Codex app-server protocol](https://developers.openai.com/codex/app-server)
over stdio. Browser login uses `account/login/start` with `type: chatgpt` as
described by the [authentication documentation](https://learn.chatgpt.com/docs/auth).
It does not silently use an API key or the developer's credentials. Each macOS
user and app build has a separate private `CODEX_HOME` under their own
Application Support directory; the process does not inherit the parent app's
environment. A build only recognizes a saved account after its own in-app
sign-in writes a local connection receipt containing a hash of the ChatGPT
account identity. An unrecognized auth file is erased before launching the
app-server. If the account changes or signs out without StudyPilot's Disconnect
action, StudyPilot erases the old isolated history before another account can
connect.

## Boundaries and current limitations

- This is **one StudyPilot identity per macOS account**. It does not provide
  multiple signed-in StudyPilot accounts within one macOS account. Do not use a
  shared macOS account as a multi-user installation.
- Four host-managed study tools are available: read a checked file, count its
  words, find literal passages and propose a replacement. Every operation requires
  explicit approval. The model supplies an opaque file ID, never a filesystem
  path. The host checks the verified account, connection, thread, turn, grant and
  original content again when approval is applied. Approval expires after two
  minutes and can be consumed once. Changed files invalidate older proposals.
- Shell execution, built-in file modification, permission expansion, connected apps, plugins, MCP servers
  and network tools stay unavailable. The app-server's shell tool is disabled,
  its process is sandboxed, and unknown server requests are rejected. Study tools
  execute bounded local app functions; they do not interpret shell commands.
- Shared text files are private copies in a fresh session directory. Originals
  are not modified by Codex. Only the student's explicit Save copy action can
  write the reviewed content to a chosen destination. The tool API cannot choose
  that destination or trigger export. Pending permissions and copies are revoked
  on disconnect, disable, process restart or 30-minute idle lock. Each turn is
  limited to 20 calls with at most four pending approvals. Per-connection approval
  and rejection totals stay local.
- The app-server itself runs under a macOS Seatbelt policy that permits its
  dedicated account directory, system runtime files, the Codex binary directory,
  HTTPS service traffic and the localhost sign-in callback. Other personal file
  contents and arbitrary executable launches are denied. Directory metadata is
  readable for runtime compatibility. The extension fails closed if the sandbox
  cannot start; there is no unrestricted fallback. macOS administrators/root and
  a compromised operating system are outside this local account boundary.
- The sandbox integration is experimental and uses macOS `sandbox-exec` and
  Apple's system runtime rules. Test compatibility after macOS or Codex upgrades.
  The extension remains optional and disabled by default.
- Conversation history is local and scoped to this user's `CODEX_HOME` and
  exact Codex workspace path. The UI accepts only thread IDs returned by that
  scoped list and checks the workspace again when reading a thread.
- A first-party Sign in with ChatGPT program for third-party/open-source apps
  is documented in [OpenAI's overview](https://developers.openai.com/siwc/token-sharing-open-source).
  This local implementation uses the app-server's documented managed browser
  login instead of sharing a token or implementing a custom OAuth backend.
- Windows currently has no native Codex extension. The WPF app has no shared
  extension framework or parity with the macOS view. iPadOS is not present in
  this repository; iPadOS cannot run this local CLI integration.
- The requested authenticated service, WebSocket authorization, simultaneous
  StudyPilot accounts, server-side session expiry, resource quotas, and
  cross-user process/file tests require a remote architecture that this project
  does not contain. They have **not** been implemented or claimed as tested.

## Security design for a future remote version

Use a server-authenticated StudyPilot user ID (never a client-provided ID), one
isolated Codex process and storage volume per account, authenticated socket
handshakes, authorization checks for every thread/file/session operation,
short-lived sessions, resource limits, and explicit file permission grants.
Restrict both reads and writes at the OS/container boundary. Reject guessed
thread IDs and paths before forwarding requests to an app-server. Never expose
an unauthenticated app-server to the network. An SSH login into a common OS
account does not provide these guarantees.

## Validation

`CodexIsolationTests` checks that two local identities get separate homes and
workspaces, that separate app builds cannot share those homes, that a connection
receipt belongs to only one build, private directory permissions, and traversal
rejection. `LocalAccountStorageTests` checks the main workspace's ownership,
owner-only permissions, and symlink rejection. The macOS app build checks
SwiftUI and protocol integration. A clean app-server process was verified to
respond to `initialize` and `account/read`, and the QA app showed the enabled
Codex section and signed-out screen. Live ChatGPT sign-in and model responses
require the individual user's account and were not automated. The full local
suite passes; it does not substitute for testing with two distinct
macOS logins and two live Codex accounts.

## Security release checks (1.25.0)

Run `bash Scripts/test.sh` and `python3 Scripts/test-codex-sandbox.py` from an
ordinary macOS terminal. The native sandbox probe verifies permitted access to
its own file and denied reads/writes of another workspace, symlink traversal,
and shell execution. It also initializes the actual installed Codex app-server
with an empty home, verifies it is signed out, and starts the official browser
login protocol without opening a browser or using an existing account. Live
sign-in and model answers still need the student's own account. No tokens are
printed, bundled in the release, or uploaded to GitHub.

The client distinguishes server requests from responses even when numeric IDs
collide, returns method-specific denials, rejects stale process callbacks, checks
the connected account before conversation operations, caps pagination and reply
size, and stops responses after three minutes. Disconnect blocks new requests,
waits for process exit, erases only that account's dedicated directory, and
reports cleanup failures. File storage checks reject symlinks, incorrect owners
and extended ACLs that could bypass owner-only mode.

## Additional validation for 1.26.0

The full suite contains 125 tests. Study-tool tests cover two synthetic account
identities, guesses of other users' file IDs, wrong conversation and turn IDs,
unchecked files, traversal, symlink escapes, rejected edits, changed-file
conflicts, expired/replayed approvals, turn-end/disconnect revocation, bounded
inputs and actual tool results. These tests exercise the same authorization and
mutation code used by the app.

`python3 Scripts/test-codex-protocol.py` starts two actual app-server processes
simultaneously with empty, separate homes. Both report signed out, register an
official dynamic tool, create distinct conversations, reject the other process's
conversation ID, and complete logout. It uses no existing credentials and makes
no model turn. Live authenticated responses and two different live accounts
remain unverified; the owner currently has only one test account. This limitation
is explicit and is not replaced by a claim that the full end-to-end account
isolation suite has passed.

Version 1.26.1 explicitly disables Codex apps, plugins, unified execution and code-mode hosts at launch; these integrations are not inherited from Codex defaults. StudyPilot also reads back the effective configuration and refuses to connect unless every restriction is confirmed. Only the registered, reviewed study tools are intended for this extension.

## Alternative AI provider (1.27.0)

Settings → AI model now offers **Codex · ChatGPT** alongside Apple Intelligence
and optional Qwen. Connect your own account and choose an available Codex model
there. Study chat, time estimates, planning advice and notebook questions route
to this provider. Messages and the feature inputs described on screen go to
OpenAI; this option requires an internet connection and account access.

Provider requests use fresh ephemeral threads with no tools. The process and
thread configuration disable both `memories.use_memories` and
`memories.generate_memories`; the app verifies these settings before sending.
They never resume the extension conversation or include earlier study-chat
messages. Codex study-chat history is saved in a separate local file; seeing an
old answer does not send it with your next request. Include needed details again
for follow-ups. Calendar and saved-study context start off on provider selection
and can be explicitly enabled in Context & sources. Attachments are explicit.
Estimates use their displayed task input; planning advice uses the selected tasks
and free-time totals; notebook answers use the selected excerpts. Existing schema
validation and calendar review still gate changes.

The signed-out protocol test verifies the memory-disabled configuration and that
an ephemeral thread stays out of saved history. It makes no authenticated model
turn, so real account access and answer quality still require user testing.
Memory being disabled here is not a claim about OpenAI service retention.
