import SwiftUI
import StudyPilotCore

struct TimeEstimateButton: View {
    let input: EffortEstimateInput
    @Binding var minutes: Int
    @State private var showing = false
    var body: some View {
        Button("Estimate time…", systemImage: "clock") { showing = true }
            .disabled(!input.canEstimate)
            .sheet(isPresented: $showing) { TimeEstimatePanel(input: input, minutes: $minutes) }
    }
}
private struct TimeEstimatePanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StudyChatService.self) private var chat
    let input: EffortEstimateInput
    @Binding var minutes: Int
    @State private var familiarity = TopicFamiliarity.unspecified
    @State private var workLeft = ""
    @State private var controller = TimeEstimateController()
    private var effectiveInput: EffortEstimateInput { var value = input; value.familiarity = familiarity; value.workLeft = workLeft; return value }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("Time estimate").font(.title3.bold()); Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
                Text(input.title).font(.headline).lineLimit(2)
                Text("Estimate focused work left, including work in future booked sessions. Breaks are extra.").font(.caption).foregroundStyle(.secondary)
                Picker("Familiarity", selection: $familiarity) { ForEach(TopicFamiliarity.allCases) { Text($0.rawValue).tag($0) } }
                TextField("Work left (optional, e.g. 12 questions)", text: $workLeft, axis: .vertical).lineLimit(2...3).textFieldStyle(.roundedBorder)
                if workLeft.count > 500 { Text("Keep this to 500 characters.").font(.caption).foregroundStyle(.orange) }
                Text("Uses \(chat.models.choice.title). Change models in Settings → AI model.").font(.caption).foregroundStyle(.secondary)
                if let reason = chat.unavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                if chat.generating { Text("Wait for the current chat reply to finish before estimating.").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button(controller.estimate == nil ? "Estimate remaining time" : "Estimate again") { controller.start(input: effectiveInput, model: chat.models.choice, client: chat.models.client) }
                        .disabled(controller.running || chat.generating || chat.unavailableReason != nil || workLeft.count > 500 || !input.canEstimate)
                    if controller.running { ProgressView().controlSize(.small); Button("Stop") { controller.cancel() } }
                }
                if let error = controller.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                if let estimate = controller.estimate, controller.basis == effectiveInput {
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(estimate.minutes) min likely").font(.title2.bold()).monospacedDigit()
                        Spacer()
                        Text("\(estimate.minimumMinutes)–\(estimate.maximumMinutes) min").foregroundStyle(.secondary).monospacedDigit()
                    }
                    Text("Scope: " + estimate.scope).font(.callout).textSelection(.enabled)
                    Text(estimate.reason).font(.callout).textSelection(.enabled)
                    Text("Assumption: " + estimate.assumption).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text("Rough AI estimate · \(controller.model?.title ?? chat.models.choice.title)").font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button("Use \(estimate.minutes) min") { apply(estimate.minutes) }.buttonStyle(.borderedProminent)
                        if estimate.maximumMinutes > estimate.minutes { Button("Use \(estimate.maximumMinutes) min buffer") { apply(estimate.maximumMinutes) } }
                    }
                    Text("Apply sets the time field. Save the assignment or preview your plan to continue.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20)
        }.frame(width: 500, height: 620)
            .task { if chat.models.choice == .qwen08 { await chat.models.refresh() } }
            .onChange(of: effectiveInput) { controller.invalidate() }
            .onChange(of: chat.models.choice) { controller.invalidate() }
            .onDisappear { controller.cancel() }
    }
    private func apply(_ value: Int) {
        guard controller.basis == effectiveInput, !controller.running else { return }
        minutes = value; dismiss()
    }
}
