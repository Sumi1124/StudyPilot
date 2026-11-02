import Foundation
import CryptoKit

/// A local installation has one StudyPilot identity per macOS account. This is
/// deliberately not a substitute for authenticated accounts on a remote server.
public struct CodexIsolation: Equatable, Sendable {
    public let userID: String
    public let appID: String
    public let root: URL
    private let applicationSupport: URL

    public init(userID: String, applicationSupport: URL, appID: String = "com.studypilot.app") throws {
        guard !userID.isEmpty, userID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw CodexIsolationError.invalidUser
        }
        guard !appID.isEmpty, appID != ".",
              appID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }),
              !appID.contains("..") else { throw CodexIsolationError.invalidApp }
        self.applicationSupport = applicationSupport.resolvingSymlinksInPath()
        self.userID = userID
        self.appID = appID
        root = self.applicationSupport.appendingPathComponent("StudyPilot/CodexExtension/Apps", isDirectory: true)
            .appendingPathComponent(appID, isDirectory: true)
            .appendingPathComponent("Users", isDirectory: true)
            .appendingPathComponent(userID, isDirectory: true)
    }

    public var codexHome: URL { root.appendingPathComponent("CodexHome", isDirectory: true) }
    public var workspace: URL { root.appendingPathComponent("Workspace", isDirectory: true) }
    public var connectionReceipt: URL { root.appendingPathComponent("ConnectedByStudyPilot", isDirectory: false) }
    public var hasConnectionReceipt: Bool { FileManager.default.fileExists(atPath: connectionReceipt.path) }

    public func recordConnection(email: String, workspaceName: String?) throws {
        guard let fingerprint = Self.fingerprint(email: email, workspaceName: workspaceName) else {
            throw CodexIsolationError.invalidAccount
        }
        try Data((fingerprint + "\n").utf8).write(to: connectionReceipt, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: connectionReceipt.path)
    }

    public func matchesConnection(email: String, workspaceName: String?) -> Bool {
        guard let fingerprint = Self.fingerprint(email: email, workspaceName: workspaceName),
              let saved = try? String(contentsOf: connectionReceipt, encoding: .utf8) else { return false }
        return saved.trimmingCharacters(in: .whitespacesAndNewlines) == fingerprint
    }

    private static func fingerprint(email: String, workspaceName: String?) -> String? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized.count <= 320 else { return nil }
        let material = "chatgpt\n\(normalized)\n\(workspaceName ?? "")"
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func prepare() throws {
        // Check every app-owned ancestor before traversing or deleting anything.
        var directory = applicationSupport
        for component in ["StudyPilot", "CodexExtension", "Apps", appID, "Users", userID] {
            directory.appendPathComponent(component, isDirectory: true)
            try LocalAccountStorage.prepare(directory)
        }
        for directory in [codexHome, workspace, temporaryDirectory] {
            try LocalAccountStorage.prepare(directory)
        }
        for file in [connectionReceipt, codexHome.appendingPathComponent("auth.json")] {
            if file.isSymbolicLink { throw CodexIsolationError.unsafeDirectory }
        }
    }

    public var temporaryDirectory: URL { root.appendingPathComponent("Temporary", isDirectory: true) }

    public func erase() throws {
        try prepare()
        try FileManager.default.removeItem(at: root)
    }

    public func owns(_ candidate: URL) -> Bool {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        return path == base || path.hasPrefix(base + "/")
    }
}

public enum CodexIsolationError: Error {
    case invalidUser, invalidApp, invalidAccount, unsafeDirectory
}

private extension URL {
    var isSymbolicLink: Bool {
        (try? resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}
