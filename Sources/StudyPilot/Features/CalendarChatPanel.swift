import SwiftUI

struct CalendarChatPanel: View {
    @Environment(StudyChatService.self) private var chat
    @Environment(AppState.self) private var app
    @State private var expanded = false
    var body: some View {
        @Bindable var calendar = chat.calendar
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Use my calendar", isOn: $calendar.enabled).toggleStyle(.checkbox).disabled(chat.generating)
                Spacer()
                Button(calendar.connected ? "Refresh" : "Connect calendars") {
                    if calendar.connected { calendar.refresh() } else { Task { await calendar.connect() } }
                }.disabled(chat.generating)
                Button("Choose calendars") { app.showingStudyPlanner = true }.disabled(chat.generating)
            }
            if calendar.enabled {
                HStack {
                    DatePicker("From", selection: $calendar.from, displayedComponents: .date).fixedSize()
                    Picker("Show", selection: $calendar.days) { Text("1 day").tag(1); Text("7 days").tag(7); Text("14 days").tag(14); Text("28 days").tag(28) }.frame(width: 150)
                    Button("Today") { calendar.from = Calendar.current.startOfDay(for: Date()); calendar.refresh() }
                }.disabled(chat.generating)
                Toggle("Only move StudyPilot study blocks", isOn: $calendar.studyBlocksOnly).toggleStyle(.checkbox).disabled(chat.generating)
                Text("Reads StudyPilot and calendars selected in Plan my study. Google must be synced with Apple Calendar. Every message refreshes this range.").font(.caption).foregroundStyle(.secondary)
                if let status = calendar.status { Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                if let error = calendar.error { Text(error).font(.caption).foregroundStyle(.red) }
                DisclosureGroup("View calendar events (\(calendar.visible.count))", isExpanded: $expanded) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(calendar.visible.prefix(100), id: \.value.id) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.value.title).font(.callout.bold())
                                    Text("\(entry.value.start.formatted(date: .abbreviated, time: .shortened)) · \(entry.value.source)\(entry.value.movable ? "" : " · read-only in chat")").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 140)
                }
            }
        }.font(.callout)
        .task { if calendar.enabled { calendar.refresh() } }
        .onChange(of: calendar.enabled) { _, enabled in calendar.pending = nil; if enabled { calendar.refresh() } }
        .onChange(of: calendar.from) { calendar.pending = nil; calendar.refresh() }
        .onChange(of: calendar.studyBlocksOnly) { calendar.pending = nil; calendar.refresh() }
        .onChange(of: calendar.days) { calendar.pending = nil; calendar.refresh() }
    }
}
struct CalendarMovePreview: View {
    @Environment(StudyChatService.self) private var chat
    let proposal: CalendarChatProposal
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Review calendar change", systemImage: "calendar.badge.clock").font(.headline)
            Text(proposal.entry.value.title).font(.headline)
            Text(proposal.entry.value.source).font(.caption).foregroundStyle(.secondary)
            Text("From: \(proposal.entry.value.start.formatted(date: .complete, time: .shortened))")
            Text("To: \(proposal.start.formatted(date: .complete, time: .shortened)) – \(proposal.end.formatted(date: .omitted, time: .shortened))").foregroundStyle(Color.pilot)
            Text("Only this event moves. Its duration and assignment deadline stay unchanged. Availability is checked again when you apply.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { chat.calendar.pending = nil }
                Button("Apply move", systemImage: "checkmark") { chat.applyCalendarMove() }.buttonStyle(.borderedProminent).disabled(chat.generating)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.pilot.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}
