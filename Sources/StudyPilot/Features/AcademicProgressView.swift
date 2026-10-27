import SwiftUI
import SwiftData
import Charts
import StudyPilotCore
import StudyPilotData

struct AcademicProgressView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @LiveQuery(sort: \Assessment.date, order: .reverse) private var assessments: [Assessment]
    @State private var selectedID: UUID?
    @State private var adding = false
    @State private var editing: Assessment?
    @State private var deleting: Assessment?
    @State private var editTarget = false
    private var selected: Subject? { subjects.first { $0.id == selectedID } ?? subjects.first }
    private var results: [Assessment] { assessments.filter { $0.subjectID == selected?.id } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "Notice how far you’ve come", title: "Academic progress", subtitle: "Assessments and progress by subject.")
                HStack {
                    Picker("Subject", selection: $selectedID) { ForEach(subjects) { Text($0.name).tag(Optional($0.id)) } }.frame(maxWidth: 350)
                    Spacer()
                    Button("Personal target") { editTarget = true }.disabled(selected == nil)
                    Button("Record assessment", systemImage: "plus") { adding = true }.buttonStyle(.borderedProminent).disabled(selected == nil)
                }
                Label("Criterion scores use the 0–8 scale. Averages and trends are personal progress estimates, not official MYP grades.", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.pilot.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                    ForEach(Criterion.allCases) { criterion in
                        let value = StudyAnalytics.average(criterion, assessments: results.map(\.record))
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Criterion \(criterion.rawValue)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 3) { Text(value.map { String(format: "%.1f", $0) } ?? "—").font(.system(size: 34, weight: .semibold, design: .rounded)); Text("/ 8").foregroundStyle(.secondary) }
                            Text("Target \(selected?.target ?? 6) · recorded average").font(.system(size: 10)).foregroundStyle(.secondary)
                            if let value { SwiftUI.ProgressView(value: value, total: 8).tint(value >= Double(selected?.target ?? 6) ? Color(hex: "2B998C") : .pilot) }
                        }.frame(maxWidth: .infinity, alignment: .leading).pilotCard()
                    }
                }
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Progress over time").font(.headline)
                        if results.isEmpty { EmptyState(symbol: "chart.xyaxis.line", title: "Your progress begins with a starting point", message: "Record an assessment to see your criterion scores and trends.") }
                        else {
                            Chart {
                                ForEach(results.sorted { $0.date < $1.date }) { result in
                                    ForEach(Criterion.allCases) { criterion in
                                        if let score = criterion.score(in: result.record) {
                                            LineMark(x: .value("Date", result.date), y: .value("Score", score), series: .value("Criterion", criterion.rawValue)).foregroundStyle(by: .value("Criterion", criterion.rawValue))
                                            PointMark(x: .value("Date", result.date), y: .value("Score", score)).foregroundStyle(by: .value("Criterion", criterion.rawValue)).accessibilityLabel("\(result.title), criterion \(criterion.rawValue)").accessibilityValue("\(score) out of 8")
                                        }
                                    }
                                }
                            }.chartYScale(domain: 0...8).chartYAxis { AxisMarks(values: [0, 2, 4, 6, 8]) }.frame(height: 250)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).pilotCard()
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Your next step", systemImage: "sparkle").font(.headline)
                        let averages = Criterion.allCases.compactMap { criterion -> (Criterion, Double)? in StudyAnalytics.average(criterion, assessments: results.map(\.record)).map { (criterion, $0) } }
                        if let lowest = averages.min(by: { $0.1 < $1.1 }) {
                            Text("Give criterion \(lowest.0.rawValue) a little extra attention.").font(.title3.weight(.medium))
                            Text(String(format: "Your recorded average is %.1f/8. Your personal target is %d/8.", lowest.1, selected?.target ?? 6)).foregroundStyle(.secondary)
                            Text("Read your teacher’s feedback and choose one specific skill to practise.").foregroundStyle(.secondary)
                            Button("Plan a focus session") { app.section = .focus }.buttonStyle(.borderedProminent)
                        } else { Text("When you add results, this space will highlight where practice could help most.").foregroundStyle(.secondary) }
                    }.font(.callout).frame(width: 230, alignment: .leading).pilotCard()
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Assessment history").font(.title3.bold())
                    ForEach(results) { result in
                        HStack(spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) { Text(result.title).font(.headline); Text(result.date, format: .dateTime.month(.abbreviated).day().year()).font(.caption).foregroundStyle(.secondary); if !result.reflection.isEmpty { Text(result.reflection).font(.caption).foregroundStyle(.secondary).lineLimit(2) } }
                            Spacer()
                            ForEach(Criterion.allCases) { criterion in VStack(spacing: 6) { Text(criterion.rawValue).font(.caption).foregroundStyle(.secondary); Text(criterion.score(in: result.record).map(String.init) ?? "—").font(.headline) }.frame(width: 30) }
                            Button("Edit") { editing = result }
                        }.padding(.vertical, 10).contextMenu { Button("Delete result…", role: .destructive) { deleting = result } }
                        Divider()
                    }
                    if results.isEmpty { Text("No results recorded for this subject yet.").foregroundStyle(.secondary) }
                }.pilotCard()
            }.padding(30)
        }
        .onAppear { selectedID = app.selectedSubjectID ?? subjects.first?.id; app.selectedSubjectID = nil }
        .onChange(of: subjects.map(\.id)) { if selectedID == nil { selectedID = subjects.first?.id } }
        .onChange(of: app.selectedSubjectID) { if let id = app.selectedSubjectID { selectedID = id; app.selectedSubjectID = nil } }
        .sheet(isPresented: $adding) { if let selected { AssessmentEditor(subjectID: selected.id) } }
        .sheet(item: $editing) { AssessmentEditor(subjectID: $0.subjectID, assessment: $0) }
        .sheet(isPresented: $editTarget) { if let selected { SubjectEditor(subject: selected) } }
        .alert("Delete this result?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) { if let deleting { context.delete(deleting); app.save(context) }; deleting = nil }
        } message: { Text("This assessment will be removed from your history and progress charts.") }
    }
}
struct AssessmentEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    let assessment: Assessment?
    @State private var draft: AssessmentRecord
    init(subjectID: UUID, assessment: Assessment? = nil) { self.assessment = assessment; _draft = State(initialValue: assessment?.record ?? AssessmentRecord(subjectID: subjectID)) }
    private var hasScore: Bool { [draft.criterionA, draft.criterionB, draft.criterionC, draft.criterionD].contains { $0 != nil } }
    var body: some View {
        VStack(spacing: 0) {
            Text(assessment == nil ? "Record an assessment" : "Edit assessment").font(.title2.bold()).padding(24)
            Form {
                TextField("Title", text: $draft.title)
                Picker("Subject", selection: $draft.subjectID) { ForEach(subjects) { Text($0.name).tag($0.id) } }
                DatePicker("Assessment date", selection: $draft.date, displayedComponents: .date)
                scorePicker("Criterion A", score: $draft.criterionA)
                scorePicker("Criterion B", score: $draft.criterionB)
                scorePicker("Criterion C", score: $draft.criterionC)
                scorePicker("Criterion D", score: $draft.criterionD)
                TextField("Feedback & reflection", text: $draft.reflection, axis: .vertical).lineLimit(3...6)
                Text("Leave unassessed criteria blank. Zero is a recorded score, not missing data.").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped)
            SheetActions(title: "Save result", disabled: draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !hasScore, cancel: { dismiss() }) {
                draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if let assessment { assessment.apply(draft) } else { context.insert(Assessment(draft)) }
                if app.save(context) { dismiss() }
            }
        }.frame(width: 550, height: 600)
    }
    private func scorePicker(_ title: String, score: Binding<Int?>) -> some View {
        Picker(title, selection: score) { Text("Not assessed").tag(nil as Int?); ForEach(0...8, id: \.self) { Text("\($0) / 8").tag(Optional($0)) } }
    }
}
