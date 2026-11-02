import Foundation
import Testing
@testable import StudyPilotCore

@MainActor private func toolFixture() throws -> (URL, CodexStudyTools, CodexStudyTools) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let alice = try CodexStudyTools(root: root.appendingPathComponent("alice"), ownerID: "mac-1001")
    let bob = try CodexStudyTools(root: root.appendingPathComponent("bob"), ownerID: "mac-1002")
    return (root, alice, bob)
}

@Test @MainActor func codexSharedFilesAndToolApprovalsCannotCrossAccountsThreadsOrTurns() throws {
    let (root, alice, bob) = try toolFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let a = try alice.importText(name: "notes.txt", text: "Alice private notes")
    let b = try bob.importText(name: "notes.txt", text: "Bob private notes")
    try alice.beginTurn(owner: "mac-1001", thread: "alice-thread", turn: "turn-a", fileIDs: [a.id])
    try bob.beginTurn(owner: "mac-1002", thread: "bob-thread", turn: "turn-b", fileIDs: [b.id])
    #expect(throws: CodexStudyToolError.self) { try alice.text(for: b.id) }
    for (owner, thread, turn, file) in [("mac-1002", "alice-thread", "turn-a", a.id), ("mac-1001", "bob-thread", "turn-a", a.id), ("mac-1001", "alice-thread", "turn-b", a.id), ("mac-1001", "alice-thread", "turn-a", b.id)] {
        #expect(throws: CodexStudyToolError.self) { try alice.prepare(owner: owner, thread: thread, turn: turn, callID: UUID().uuidString, tool: "study_read_file", arguments: ["file_id": file.uuidString]) }
    }
    let approval = try alice.prepare(owner: "mac-1001", thread: "alice-thread", turn: "turn-a", callID: "call-a", tool: "study_read_file", arguments: ["file_id": a.id.uuidString])
    #expect(throws: CodexStudyToolError.self) { try bob.resolve(approval, owner: "mac-1002", approve: true) }
    #expect(try alice.resolve(approval, owner: "mac-1001", approve: true) == "Alice private notes")
    #expect(throws: CodexStudyToolError.self) { try alice.resolve(approval, owner: "mac-1001", approve: true) }
}

@Test @MainActor func codexFileEditsRequireFreshSingleUseApprovalAndLeaveRejectedFilesIntact() throws {
    let (root, alice, _) = try toolFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let file = try alice.importText(name: "notes.txt", text: "Original")
    try alice.beginTurn(owner: "mac-1001", thread: "thread", turn: "turn", fileIDs: [file.id])
    let rejected = try alice.prepare(owner: "mac-1001", thread: "thread", turn: "turn", callID: "reject", tool: "study_edit_file", arguments: ["file_id": file.id.uuidString, "replacement": "Unapproved"])
    #expect(try alice.text(for: file.id) == "Original")
    _ = try alice.resolve(rejected, owner: "mac-1001", approve: false)
    #expect(try alice.text(for: file.id) == "Original")
    let first = try alice.prepare(owner: "mac-1001", thread: "thread", turn: "turn", callID: "first", tool: "study_edit_file", arguments: ["file_id": file.id.uuidString, "replacement": "Reviewed"])
    let stale = try alice.prepare(owner: "mac-1001", thread: "thread", turn: "turn", callID: "stale", tool: "study_edit_file", arguments: ["file_id": file.id.uuidString, "replacement": "Overwrite"])
    _ = try alice.resolve(first, owner: "mac-1001", approve: true)
    #expect(throws: CodexStudyToolError.self) { try alice.resolve(stale, owner: "mac-1001", approve: true) }
    #expect(try alice.text(for: file.id) == "Reviewed")
    #expect(alice.approvedCount == 1 && alice.rejectedCount == 1)
}

@Test @MainActor func codexToolGrantsExpireAndAreRevokedAtTurnEndOrDisconnect() throws {
    let (root, alice, _) = try toolFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let file = try alice.importText(name: "notes.txt", text: "one two three")
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    try alice.beginTurn(owner: "mac-1001", thread: "thread", turn: "turn", fileIDs: [file.id])
    let proposal = try alice.prepare(owner: "mac-1001", thread: "thread", turn: "turn", callID: "expired", tool: "study_count_words", arguments: ["file_id": file.id.uuidString], now: now)
    #expect(throws: CodexStudyToolError.self) { try alice.resolve(proposal, owner: "mac-1001", approve: true, now: now.addingTimeInterval(121)) }
    let next = try alice.prepare(owner: "mac-1001", thread: "thread", turn: "turn", callID: "end", tool: "study_count_words", arguments: ["file_id": file.id.uuidString])
    alice.endTurn()
    #expect(throws: CodexStudyToolError.self) { try alice.resolve(next, owner: "mac-1001", approve: true) }
    alice.revoke()
    #expect(throws: CodexStudyToolError.self) { try alice.text(for: file.id) }
    #expect(throws: CodexStudyToolError.self) { try alice.beginTurn(owner: "mac-1001", thread: "thread", turn: "turn2", fileIDs: []) }
}

@Test @MainActor func codexSharedFilePathsAndLinksCannotEscapePermissionGrants() throws {
    let (root, alice, bob) = try toolFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let file = try alice.importText(name: "../malicious-name.txt", text: "Shared text")
    let secret = try bob.importText(name: "secret.txt", text: "Private")
    try alice.beginTurn(owner: "mac-1001", thread: "thread", turn: "turn", fileIDs: [file.id])
    #expect(throws: CodexStudyToolError.self) { try alice.prepare(owner: "mac-1001", thread: "thread", turn: "turn", callID: "path", tool: "study_read_file", arguments: ["file_id": "../bob/secret.txt"]) }
    let source = alice.root.appendingPathComponent(file.id.uuidString + ".txt")
    let target = bob.root.appendingPathComponent(secret.id.uuidString + ".txt")
    try FileManager.default.removeItem(at: source)
    try FileManager.default.createSymbolicLink(at: source, withDestinationURL: target)
    #expect(throws: CodexStudyToolError.self) { try alice.text(for: file.id) }
    #expect(try bob.text(for: secret.id) == "Private")
}

@Test @MainActor func codexStudyToolsExecuteOnlyBoundedExplicitlySelectedOperations() throws {
    let (root, alice, _) = try toolFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let file = try alice.importText(name: "notes.txt", text: "Math notes\nQuadratic equations")
    let unselected = try alice.importText(name: "unselected.txt", text: "Do not send")
    try alice.beginTurn(owner: "mac-1001", thread: "thread", turn: "turn", fileIDs: [file.id])
    for args in [["file_id": unselected.id.uuidString], ["file_id": file.id.uuidString, "path": "/"], ["file_id": "../../auth.json"]] {
        #expect(throws: CodexStudyToolError.self) { try alice.prepare(owner: "mac-1001", thread: "thread", turn: "turn", callID: UUID().uuidString, tool: "study_read_file", arguments: args) }
    }
    #expect(throws: CodexStudyToolError.self) { try alice.prepare(owner: "mac-1001", thread: "thread", turn: "turn", callID: "shell", tool: "exec_command", arguments: ["file_id": file.id.uuidString]) }
    #expect(throws: CodexStudyToolError.self) { try alice.importText(name: "large", text: String(repeating: "x", count: 64_001)) }
    let count = try alice.prepare(owner: "mac-1001", thread: "thread", turn: "turn", callID: "count", tool: "study_count_words", arguments: ["file_id": file.id.uuidString])
    #expect(try alice.resolve(count, owner: "mac-1001", approve: true).contains("Words: 4"))
    #expect(throws: CodexStudyToolError.self) { try alice.prepare(owner: "mac-1001", thread: "thread", turn: "turn", callID: "count", tool: "study_count_words", arguments: ["file_id": file.id.uuidString]) }
    let find = try alice.prepare(owner: "mac-1001", thread: "thread", turn: "turn", callID: "find", tool: "study_find_passages", arguments: ["file_id": file.id.uuidString, "query": "quadratic"])
    #expect(try alice.resolve(find, owner: "mac-1001", approve: true) == "2: Quadratic equations")
}
