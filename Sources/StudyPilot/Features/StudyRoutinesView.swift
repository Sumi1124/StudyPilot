import SwiftUI
import StudyPilotCore

struct StudyRoutinesView: View {
    @Environment(CalendarPlanningService.self) private var planning
    @State private var name = ""
    @State private var expanded = false
    @State private var message: String?
    @State private var error: String?
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save your study days, hours, session length and daily limit. Reuse them when your timetable changes.").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Routine name, e.g. School week", text: $name).textFieldStyle(.roundedBorder).onSubmit(save)
                Button("Save current settings", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 40)
            }
            ForEach(planning.settings.routines ?? []) { routine in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(routine.name).font(.callout.weight(.semibold))
                        Text(summary(routine.preferences)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Use") { apply(routine) }.help("Apply \(routine.name) and regenerate your preview")
                    Menu { Button("Remove routine", role: .destructive) { remove(routine) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24).accessibilityLabel("Options for \(routine.name)")
                }.padding(.vertical, 3)
            }
            if let message { Text(message).font(.caption).foregroundStyle(Color.pilot) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(.top, 14)
        } label: {
            HStack { Label("My study routines", systemImage: "bookmark").font(.headline); Spacer(); Text("\(planning.settings.routines?.count ?? 0)/5 saved").font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).pilotCard()
    }
    private func save() {
        let previous = planning.settings.routines
        do {
            planning.settings.routines = try StudyRoutines.saving(name: name, preferences: planning.settings.preferences, in: previous ?? [])
            try planning.saveSettings(); message = "Saved \(name.trimmingCharacters(in: .whitespacesAndNewlines)). Use the same name to update a routine."; name = ""; error = nil
        } catch { planning.settings.routines = previous; self.error = error.localizedDescription }
    }
    private func apply(_ routine: StudyRoutine) {
        let previous = planning.settings.preferences
        do {
            try routine.preferences.validate()
            planning.settings.preferences = routine.preferences
            try planning.saveSettings(); error = nil; message = "Using \(routine.name). Preview again to check the schedule."
        } catch { planning.settings.preferences = previous; self.error = error.localizedDescription }
    }
    private func remove(_ routine: StudyRoutine) {
        let previous = planning.settings.routines
        planning.settings.routines?.removeAll { $0.id == routine.id }
        do { try planning.saveSettings(); error = nil; message = "Removed \(routine.name). Your current study hours are kept." }
        catch { planning.settings.routines = previous; self.error = error.localizedDescription }
    }
    private func summary(_ p: PlanningPreferences) -> String {
        let calendar = Calendar.current
        var labels: [String] = []
        for offset in 0..<7 {
            let day = (calendar.firstWeekday - 1 + offset) % 7 + 1
            if p.weekdays.contains(day) { labels.append(calendar.shortWeekdaySymbols[day - 1]) }
        }
        let days = labels.joined(separator: ", ")
        func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
        return "\(days) · \(time(p.startMinute))–\(time(p.endMinute)) · \(p.dailyMinutes) min/day"
    }
}
