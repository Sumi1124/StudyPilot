import Foundation

public enum CodexSecurityPolicy {
    public static func permitsStudyOnlyConfiguration(_ config: [String: Any]) -> Bool {
        guard let features = config["features"] as? [String: Any],
              config["web_search"] as? String == "disabled" else { return false }
        return ["apps", "plugins", "shell_tool", "unified_exec", "code_mode", "code_mode_host", "apply_patch_freeform"]
            .allSatisfy { features[$0] as? Bool == false }
    }

    // The host process is confined as well as any model-requested operations.
    // Paths are passed as sandbox parameters, never interpolated into this program.
    public static let sandboxProfile = """
    (version 1)
    (deny default)
    (import "system.sb")
    (system-network)
    (allow process-exec (literal (param "EXECUTABLE")))
    (allow process-fork)
    (allow signal (target self))
    (allow sysctl-read)
    (allow mach-lookup
        (global-name "com.apple.system.opendirectoryd.libinfo")
        (global-name "com.apple.system.opendirectoryd.membership")
        (global-name "com.apple.trustd.agent")
        (global-name "com.apple.trustd")
        (global-name "com.apple.system.logger")
        (global-name "com.apple.system.notification_center")
        (global-name "com.apple.SystemConfiguration.configd")
        (global-name "com.apple.networkd"))
    (allow file-read-metadata)
    (allow file-read* file-map-executable
        (subpath "/System/Library")
        (subpath "/usr/lib")
        (subpath "/usr/share")
        (subpath "/private/var/db/dyld")
        (subpath "/private/var/db/timezone")
        (subpath "/private/var/db/mds/system")
        (subpath "/Library/Apple/System/Library")
        (subpath "/Library/Apple/usr/lib")
        (subpath (param "BINARY_DIRECTORY"))
        (literal "/private/etc/localtime")
        (literal "/private/etc/hosts")
        (literal "/private/etc/resolv.conf")
        (literal "/private/etc/services")
        (literal "/private/etc/protocols")
        (literal "/private/etc/ssl/cert.pem")
        (literal "/dev/random") (literal "/dev/urandom"))
    (allow file-read* file-write* file-lock (subpath (param "ROOT")))
    (allow file-read* file-write-data (literal "/dev/null"))
    (allow network-outbound (remote tcp "*:443"))
    (allow network-bind (local tcp "localhost:1455"))
    (allow network-inbound (local tcp "localhost:1455"))
    """

    public static func denial(for message: [String: Any]) -> [String: Any]? {
        guard let id = message["id"], let method = message["method"] as? String else { return nil }
        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            return ["id": id, "result": ["decision": "decline"]]
        case "item/permissions/requestApproval":
            return ["id": id, "result": ["permissions": [:], "scope": "turn"]]
        case "mcpServer/elicitation/request":
            return ["id": id, "result": ["action": "decline", "content": NSNull()]]
        default:
            return ["id": id, "error": ["code": -32601, "message": "This StudyPilot extension does not allow this operation."]]
        }
    }

    public static func isResponse(_ message: [String: Any]) -> Bool {
        message["method"] == nil && message["id"] is Int &&
            ((message["result"] != nil) != (message["error"] != nil))
    }
}
