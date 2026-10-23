import SwiftUI
import SwiftData
import Combine
import Observation

extension Notification.Name {
    static let studyPilotQueryFailed = Notification.Name("StudyPilot.queryFailed")
}

/// Fetches through SwiftData and refreshes after committed changes. This avoids
/// Query's dependency on metadata emitted by the Xcode-only Model macro plug-in.
@MainActor @propertyWrapper struct LiveQuery<Model: PersistentModel>: @preconcurrency DynamicProperty {
    @Environment(\.modelContext) private var context
    @State private var store = QueryStore<Model>()
    private let descriptor: FetchDescriptor<Model>
    var wrappedValue: [Model] { store.records }
    init() { descriptor = FetchDescriptor<Model>() }
    init<Value: Comparable>(sort: KeyPath<Model, Value> & Sendable, order: SortOrder = .forward) {
        descriptor = FetchDescriptor<Model>(sortBy: [SortDescriptor(sort, order: order)])
    }
    mutating func update() { store.connect(context, descriptor: descriptor) }
}

@MainActor @Observable private final class QueryStore<Model: PersistentModel> {
    var records: [Model] = []
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var descriptor = FetchDescriptor<Model>()
    @ObservationIgnored private var subscription: AnyCancellable?
    func connect(_ context: ModelContext, descriptor: FetchDescriptor<Model>) {
        guard self.context !== context else { return }
        self.context = context; self.descriptor = descriptor
        subscription = NotificationCenter.default.publisher(for: ModelContext.didSave).sink { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        Task { @MainActor [weak self] in self?.reload() }
    }
    private func reload() {
        guard let context else { return }
        do { records = try context.fetch(descriptor) }
        catch { NotificationCenter.default.post(name: .studyPilotQueryFailed, object: nil, userInfo: ["message": "Your saved data could not be loaded: \(error.localizedDescription)"]) }
    }
}
