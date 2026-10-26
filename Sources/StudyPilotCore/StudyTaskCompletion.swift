import Foundation

public struct CompletedStudyTask: Codable, Equatable, Sendable {
    public var title: String
    public var completedAt: Date
    public var removeAfter: Date
    public var needsCalendarAccess: Bool
    public var cleaned: Bool
    public init(title: String, completedAt: Date = Date(), needsCalendarAccess: Bool) {
        self.title = title; self.completedAt = completedAt
        self.removeAfter = completedAt.addingTimeInterval(90)
        self.needsCalendarAccess = needsCalendarAccess; self.cleaned = false
    }
    public func ready(at now: Date) -> Bool { !cleaned && now >= removeAfter }
}

public enum StudyTaskLink {
    public static func matches(notes: String, taskID: String) -> Bool {
        !taskID.isEmpty && PlannedStudyBlock.taskID(in: notes) == taskID
    }
    public static func ownsSyncedSession(url: URL?, notes: String, taskID: String) -> Bool {
        url?.scheme == "studypilot" && url?.host == "plan" && matches(notes: notes, taskID: taskID)
    }
    public static func localID(_ taskID: String) -> UUID? {
        guard taskID.hasPrefix("local:") else { return nil }
        return UUID(uuidString: String(taskID.dropFirst(6)))
    }
}
