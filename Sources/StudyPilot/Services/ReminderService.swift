import Foundation
import Observation
@preconcurrency import UserNotifications
import SwiftData
import StudyPilotData

@MainActor @Observable final class ReminderService {
    static let shared = ReminderService()
    var status = "Notifications have not been enabled."
    var lastError: String?
    private var refreshing = false
    private var refreshAgain = false
    private let center = UNUserNotificationCenter.current()
    func requestPermission(context: ModelContext) async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            UserDefaults.standard.set(granted, forKey: "remindersEnabled")
            await reconcile(context: context)
        } catch { lastError = error.localizedDescription }
    }
    func reconcile(context: ModelContext) async {
        if refreshing { refreshAgain = true; return }
        refreshing = true
        defer {
            refreshing = false
            if refreshAgain { refreshAgain = false; Task { await reconcile(context: context) } }
        }
        let settings = await center.notificationSettings()
        let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        let enabled = UserDefaults.standard.bool(forKey: "remindersEnabled")
        status = allowed ? (enabled ? "Local reminders are enabled." : "Reminders are turned off in StudyPilot.") : "Enable notifications to receive reminders. If denied, allow StudyPilot in System Settings → Notifications."
        let old = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: old.filter { $0.identifier.hasPrefix("plan-") || $0.identifier.hasPrefix("revision-") }.map(\.identifier))
        guard allowed && enabled else { return }
        do {
            let now = Date()
            var scheduled: [(String, String, String, Date)] = []
            for item in try context.fetch(FetchDescriptor<Assignment>()) where item.status != "Done" {
                if let date = item.reminderDate, date > now { scheduled.append(("plan-task-\(item.id)", item.title, "Assignment due \(item.dueDate.formatted(date: .abbreviated, time: .shortened))", date)) }
            }
            for item in try context.fetch(FetchDescriptor<PlannerEvent>()) {
                if let date = item.reminderDate, date > now { scheduled.append(("plan-event-\(item.id)", item.title, "\(item.kind) at \(item.startDate.formatted(date: .abbreviated, time: .shortened))", date)) }
            }
            for item in scheduled.sorted(by: { $0.3 < $1.3 }).prefix(48) {
                let content = UNMutableNotificationContent(); content.title = item.1; content.body = item.2; content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.3)
                try await center.add(UNNotificationRequest(identifier: item.0, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
            let cards = try context.fetch(FetchDescriptor<Flashcard>())
            let decks = try context.fetch(FetchDescriptor<Deck>()).filter(\.reminderEnabled).sorted { $0.id.uuidString < $1.id.uuidString }
            for deck in decks.prefix(10) {
                guard let firstDue = cards.filter({ $0.deckID == deck.id }).map(\.dueDate).min() else { continue }
                let earliest = max(now, firstDue)
                var next = Calendar.current.date(bySettingHour: deck.reminderHour, minute: 0, second: 0, of: earliest) ?? earliest
                if next <= earliest { next = Calendar.current.date(byAdding: .day, value: 1, to: next) ?? next }
                let content = UNMutableNotificationContent(); content.title = "Time to revisit \(deck.title)"; content.body = "A short review keeps your learning fresh."; content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: next)
                try await center.add(UNNotificationRequest(identifier: "revision-\(deck.id)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
            lastError = nil
            if scheduled.count > 48 || decks.count > 10 { status += " The nearest 48 deadlines and up to 10 deck reminders are queued; opening the app refreshes the queue." }
        } catch { lastError = "Could not schedule reminders: \(error.localizedDescription)" }
    }
    func scheduleFocus(at date: Date, isBreak: Bool) async {
        center.removePendingNotificationRequests(withIdentifiers: ["focus-complete"])
        guard UserDefaults.standard.bool(forKey: "remindersEnabled"), date > Date() else { return }
        let content = UNMutableNotificationContent(); content.title = isBreak ? "Ready for your next chapter?" : "Focus session complete"; content.body = isBreak ? "Your break is over." : "Nice work. Take a moment to recharge."; content.sound = .default
        do { try await center.add(UNNotificationRequest(identifier: "focus-complete", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false))) }
        catch { lastError = error.localizedDescription }
    }
    func cancelFocus() { center.removePendingNotificationRequests(withIdentifiers: ["focus-complete"]) }
}
