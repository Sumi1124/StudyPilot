import Foundation
import Darwin

/// Keeps a local StudyPilot workspace private to the current macOS login.
public enum LocalAccountStorage {
    @discardableResult
    public static func prepare(_ directory: URL, expectedUserID: UInt32 = getuid()) throws -> URL {
        guard directory.isFileURL else { throw LocalAccountStorageError.invalidLocation }
        let manager = FileManager.default
        if (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw LocalAccountStorageError.symbolicLink
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        // Operate on the opened directory, never a followed symlink. Verify ownership
        // before changing permissions. An ACL could grant access despite mode 0700.
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw LocalAccountStorageError.notPrivate }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == expectedUserID else {
            throw LocalAccountStorageError.notPrivate
        }
        errno = 0
        if let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var entry: acl_entry_t?
            // Darwin returns -1/ENOENT for an ACL with no entries.
            errno = 0
            let result = acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry)
            guard result == -1 && errno == ENOENT else { throw LocalAccountStorageError.notPrivate }
        } else if errno != ENOENT { throw LocalAccountStorageError.notPrivate }
        guard fchmod(descriptor, 0o700) == 0,
              fstat(descriptor, &info) == 0, info.st_mode & 0o777 == 0o700 else {
            throw LocalAccountStorageError.notPrivate
        }
        return directory
    }
}

public enum LocalAccountStorageError: LocalizedError {
    case invalidLocation, symbolicLink, notPrivate

    public var errorDescription: String? {
        switch self {
        case .invalidLocation: "The StudyPilot data location must be a local folder."
        case .symbolicLink: "The StudyPilot data folder is a symbolic link. Move it into your private Mac account before opening it."
        case .notPrivate: "StudyPilot could not make this data folder private to your Mac account. Check its owner and sharing permissions."
        }
    }
}
