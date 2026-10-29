import Foundation

public enum ChatModelChoice: String, CaseIterable, Identifiable, Sendable {
    case apple, qwen08
    public var id: String { rawValue }
    public var title: String { self == .apple ? "Apple Intelligence" : "Qwen 3.5 · 0.8B" }
    public static func saved(_ value: String?) -> Self { Self(rawValue: value ?? "") ?? .apple }
}

/// The local integration has a fixed loopback destination and an exact model tag.
public enum OllamaWire {
    public static let model = "qwen3.5:0.8b-q8_0"
    public static let base = URL(string: "http://127.0.0.1:11434")!
    public struct Progress: Decodable, Sendable {
        public let status: String?
        public let total: Int64?
        public let completed: Int64?
        public let error: String?
        public var fraction: Double? {
            guard let total, total > 0, let completed else { return nil }
            return min(1, max(0, Double(completed) / Double(total)))
        }
    }
    public static func installed(in data: Data) throws -> Bool {
        struct Model: Decodable { let name: String?; let model: String? }
        struct List: Decodable { let models: [Model] }
        guard data.count < 2_000_000 else { throw PlanningError.invalid("The local model list is too large.") }
        return try JSONDecoder().decode(List.self, from: data).models.contains { $0.name == model || $0.model == model }
    }
    public static func requestBody(prompt: String, eventIDs: [String]?) throws -> Data {
        guard prompt.utf8.count <= 20_000 else { throw PlanningError.invalid("This message is too large for the local model.") }
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "properties": [
                "eventID": ["type": "string", "enum": ["none"] + (eventIDs ?? []).sorted()],
                "start": ["type": "string"], "reply": ["type": "string"]
            ], "required": ["eventID", "start", "reply"]
        ]
        let rules = (eventIDs == nil ? StudyChat.instructions : CalendarChat.instructions) + "\nReturn only JSON matching this schema: " + String(decoding: try JSONSerialization.data(withJSONObject: schema, options: .sortedKeys), as: UTF8.self) + "\nFor no action use eventID none and start empty. Only select an allowed event ID for an explicitly requested move. For the next free slot use start next-free. Never claim a calendar change is applied."
        return try JSONSerialization.data(withJSONObject: [
            "model": model, "stream": false, "think": false, "keep_alive": "5m",
            "messages": [["role": "system", "content": rules], ["role": "user", "content": prompt]],
            "format": schema, "options": ["temperature": 0.1, "num_ctx": 8192, "num_predict": 900]
        ])
    }
    public static func content(from data: Data) throws -> String {
        struct Message: Decodable { let role: String; let content: String }
        struct Envelope: Decodable { let model: String; let message: Message; let done: Bool; let done_reason: String? }
        guard data.count <= 128_000 else { throw PlanningError.invalid("The local model returned too much data. Try a shorter request.") }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.model == model, envelope.done, envelope.message.role == "assistant", envelope.done_reason != "length" else {
            throw PlanningError.invalid("The selected local model did not finish its reply. Retry with a shorter message.")
        }
        return envelope.message.content
    }
    public static func reply(from data: Data, eventIDs: [String]?) throws -> CalendarChatResponse {
        struct Fields: Decodable { let eventID: String; let start: String; let reply: String }
        let fields = try JSONDecoder().decode(Fields.self, from: Data(content(from: data).utf8))
        var response: [String: Any] = ["reply": fields.reply, "move": NSNull()]
        if fields.eventID != "none" {
            guard let eventIDs, eventIDs.contains(fields.eventID), !fields.start.isEmpty else {
                throw PlanningError.invalid("The local model selected an unavailable calendar event. No change was prepared.")
            }
            if fields.start != "next-free" { _ = try CalendarChat.date(fields.start) }
            response["move"] = ["eventID": fields.eventID, "start": fields.start == "next-free" ? NSNull() : fields.start] as [String: Any]
        }
        return try CalendarChatResponse.decode(String(decoding: JSONSerialization.data(withJSONObject: response), as: UTF8.self))
    }
}

private final class LoopbackSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

public actor OllamaClient {
    private let session: URLSession
    private var base = OllamaWire.base
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config, delegate: LoopbackSessionDelegate(), delegateQueue: nil)
    }
    private func request(_ path: String, body: Data? = nil, timeout: TimeInterval) -> URLRequest {
        var value = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: timeout)
        if let body { value.httpMethod = "POST"; value.httpBody = body; value.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return value
    }
    public func useManagedRuntime() { base = URL(string: "http://127.0.0.1:11435")! }
    private func validate(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else { throw PlanningError.invalid("Ollama returned an invalid response.") }
        if http.statusCode == 404 { throw PlanningError.invalid("Qwen 3.5 0.8B is not installed. Open Model setup to download it.") }
        guard http.statusCode == 200 else { throw PlanningError.invalid("Ollama could not complete this request (HTTP \(http.statusCode)). Check that Ollama is up to date and try again.") }
    }
    public func isInstalled() async throws -> Bool {
        let (data, response) = try await session.data(for: request("api/tags", timeout: 5))
        try validate(response); return try OllamaWire.installed(in: data)
    }
    public func reply(prompt: String, eventIDs: [String]?) async throws -> CalendarChatResponse {
        let body = try OllamaWire.requestBody(prompt: prompt, eventIDs: eventIDs)
        return try OllamaWire.reply(from: await chatData(body: body), eventIDs: eventIDs)
    }
    public func estimate(input: EffortEstimateInput) async throws -> EffortEstimate {
        let data = try await chatData(body: EffortEstimation.ollamaBody(input: input))
        return try EffortEstimate.decode(OllamaWire.content(from: data))
    }
    public func studyPlanAdvice(input: StudyPlanAdviceInput) async throws -> StudyPlanAdvice {
        let data = try await chatData(body: StudyPlanAdvising.ollamaBody(input: input))
        return try StudyPlanAdvice.decode(OllamaWire.content(from: data))
    }
    public func notebookAnswer(input: NotebookQuestion) async throws -> NotebookAnswer {
        let data = try await chatData(body: NotebookResearch.ollamaBody(input: input))
        return try NotebookAnswer.decode(OllamaWire.content(from: data), input: input)
    }
    private func chatData(body: Data) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request("api/chat", body: body, timeout: 180))
        try validate(response)
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 128_000 else { throw PlanningError.invalid("The local model reply exceeded the size limit.") }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }
    public func download(progress: @escaping @Sendable (OllamaWire.Progress) async -> Void) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["model": OllamaWire.model, "stream": true])
        let (bytes, response) = try await session.bytes(for: request("api/pull", body: body, timeout: 3600))
        try validate(response)
        var line = Data(), success = false
        func consume(_ data: Data) throws -> OllamaWire.Progress { try JSONDecoder().decode(OllamaWire.Progress.self, from: data) }
        for try await byte in bytes {
            try Task.checkCancellation()
            if byte == 10 {
                if !line.isEmpty {
                    let item = try consume(line)
                    if let error = item.error { throw PlanningError.invalid("Ollama download failed: " + String(error.prefix(300))) }
                    if item.status == "success" { success = true }
                    await progress(item)
                    line.removeAll(keepingCapacity: true)
                }
            } else {
                guard line.count < 16_000 else { throw PlanningError.invalid("Ollama returned an invalid download status.") }
                line.append(byte)
            }
        }
        if !line.isEmpty {
            let item = try consume(line)
            if let error = item.error { throw PlanningError.invalid("Ollama download failed: " + String(error.prefix(300))) }
            success = success || item.status == "success"; await progress(item)
        }
        try Task.checkCancellation()
        guard success, try await isInstalled() else { throw PlanningError.invalid("The download did not finish. Try Download again to resume.") }
    }
}
