import Foundation
import Testing
@testable import StudyPilotCore

@Test func studyPilotWorkspaceIsPrivateToCurrentMacLogin() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StudyPilot-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    try LocalAccountStorage.prepare(directory)
    let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    #expect((attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid())
    #expect((attributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o700)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
    try LocalAccountStorage.prepare(directory)
    let repaired = try FileManager.default.attributesOfItem(atPath: directory.path)
    #expect((repaired[.posixPermissions] as? NSNumber)?.uint16Value == 0o700)
    #expect(throws: LocalAccountStorageError.self) {
        try LocalAccountStorage.prepare(directory, expectedUserID: getuid() + 1)
    }
}

@Test func studyPilotRefusesSymlinkedWorkspace() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("StudyPilot-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: base) }
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let real = base.appendingPathComponent("real")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    let link = base.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    #expect(throws: LocalAccountStorageError.self) { try LocalAccountStorage.prepare(link) }
}
