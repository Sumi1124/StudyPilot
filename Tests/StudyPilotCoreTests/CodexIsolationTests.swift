import Foundation
import Testing
@testable import StudyPilotCore

@Test func codexAccountsHaveDifferentPrivateHomesAndWorkspaces() throws {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: support) }
    let alice = try CodexIsolation(userID: "1001", applicationSupport: support)
    let bob = try CodexIsolation(userID: "1002", applicationSupport: support)
    let preview = try CodexIsolation(userID: "1001", applicationSupport: support, appID: "com.studypilot.preview")
    try alice.prepare(); try bob.prepare()
    try preview.prepare()
    #expect(alice.codexHome != bob.codexHome)
    #expect(alice.codexHome != preview.codexHome)
    #expect(alice.workspace != bob.workspace)
    #expect(!alice.owns(bob.codexHome))
    #expect(!alice.owns(preview.codexHome))
    #expect(!bob.owns(alice.workspace))
    let permissions = try FileManager.default.attributesOfItem(atPath: alice.codexHome.path)[.posixPermissions] as? Int
    #expect(permissions == 0o700)
    #expect(!alice.hasConnectionReceipt)
    try alice.recordConnection(email: "alice@example.com", workspaceName: "School")
    #expect(alice.hasConnectionReceipt)
    #expect(alice.matchesConnection(email: "ALICE@example.com", workspaceName: "School"))
    #expect(!alice.matchesConnection(email: "bob@example.com", workspaceName: "School"))
    #expect(!alice.matchesConnection(email: "alice@example.com", workspaceName: "Another school"))
    #expect(!preview.hasConnectionReceipt)
}

@Test func codexRejectsTraversalAndInvalidUserNames() throws {
    let support = FileManager.default.temporaryDirectory
    #expect(throws: CodexIsolationError.self) { try CodexIsolation(userID: "../other", applicationSupport: support) }
    let alice = try CodexIsolation(userID: "1001", applicationSupport: support)
    #expect(!alice.owns(alice.root.appendingPathComponent("../1002/CodexHome")))
    #expect(!alice.owns(support.appendingPathComponent("StudyPilot/CodexExtension/Apps/com.studypilot.app/Users/1001-other")))
    #expect(throws: CodexIsolationError.self) {
        try CodexIsolation(userID: "1001", applicationSupport: support, appID: "../outside")
    }
}
