import Foundation
import Testing
@testable import StudyPilotCore

@Test func codexServerRequestCannotConsumePendingClientResponseWithSameID() throws {
    let approval: [String: Any] = ["id": 1, "method": "item/fileChange/requestApproval", "params": ["threadId": "other-user"]]
    #expect(!CodexSecurityPolicy.isResponse(approval))
    let denial = try #require(CodexSecurityPolicy.denial(for: approval))
    #expect((denial["result"] as? [String: String])?["decision"] == "decline")
    #expect(CodexSecurityPolicy.isResponse(["id": 1, "result": [:]]))
    #expect(!CodexSecurityPolicy.isResponse(["id": 1]))
    #expect(!CodexSecurityPolicy.isResponse(["id": 1, "result": [:], "error": [:]]))
}

@Test func codexNeverGrantsPermissionsAndRejectsUnknownTools() throws {
    let reply = try #require(CodexSecurityPolicy.denial(for: ["id": "request-1", "method": "item/permissions/requestApproval", "params": ["permissions": ["fileSystem": ["write": ["/"]]]]]))
    let result = try #require(reply["result"] as? [String: Any])
    #expect((result["permissions"] as? [String: Any])?.isEmpty == true)
    #expect(result["scope"] as? String == "turn")
    let unknown = try #require(CodexSecurityPolicy.denial(for: ["id": 2, "method": "future/tool"]))
    #expect(unknown["result"] == nil)
    #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32601)
}

@Test func codexRejectsSymlinkedAncestorsAndCannotEraseOutsideItsRoot() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let support = base.appendingPathComponent("support"), outside = base.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let marker = outside.appendingPathComponent("keep")
    try Data("untouched".utf8).write(to: marker)
    try FileManager.default.createSymbolicLink(at: support.appendingPathComponent("StudyPilot"), withDestinationURL: outside)
    let scope = try CodexIsolation(userID: "1001", applicationSupport: support)
    #expect(throws: LocalAccountStorageError.self) { try scope.prepare() }
    #expect(throws: LocalAccountStorageError.self) { try scope.erase() }
    #expect(try String(contentsOf: marker, encoding: .utf8) == "untouched")
}

@Test func codexLogoutErasesOnlyItsOwnAccountAndHistory() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let alice = try CodexIsolation(userID: "1001", applicationSupport: base)
    let bob = try CodexIsolation(userID: "1002", applicationSupport: base)
    try alice.prepare(); try bob.prepare()
    try alice.recordConnection(email: "alice@example.com", workspaceName: nil)
    try bob.recordConnection(email: "bob@example.com", workspaceName: nil)
    try Data("fake-token".utf8).write(to: alice.codexHome.appendingPathComponent("auth.json"))
    try alice.erase()
    #expect(!FileManager.default.fileExists(atPath: alice.root.path))
    #expect(bob.matchesConnection(email: "bob@example.com", workspaceName: nil))
}
