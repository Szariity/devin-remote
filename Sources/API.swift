import Foundation

struct APIError: Error, LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class API: ObservableObject {
    @AppStorage("serverURL") var serverURL: String = ""
    @AppStorage("remoteKey") var remoteKey: String = ""

    private var base: URL? { URL(string: serverURL.trimmingCharacters(in: .whitespaces).hasSuffix("/") ? String(serverURL.dropLast()) : serverURL) }

    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        guard let b = base, let url = URL(string: path, relativeTo: b) else {
            throw APIError(status: 0, message: "bad server URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(remoteKey, forHTTPHeaderField: "x-remote-key")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 90
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw APIError(status: 401, message: "bad key") }
        if code >= 400 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                ?? String(data: data, encoding: .utf8) ?? "error \(code)"
            throw APIError(status: code, message: msg)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<T: Decodable>(_ path: String, _ body: [String: Any]) async throws -> T {
        try await request(path, method: "POST", body: body)
    }

    // MARK: endpoints
    func ping() async throws -> Ping { try await request("/api/ping") }
    func localList() async throws -> [SessRow] { try await request("/api/local/list") }
    func transcript(cwd: String, id: String) async throws -> Transcript {
        try await request("/api/local/transcript?cwd=\(cwd.urlEnc)&sessionId=\(id)")
    }
    func localState(id: String) async throws -> Transcript {
        try await request("/api/local/state?sessionId=\(id)")
    }
    func newLocal(cwd: String, prompt: String, model: String?, mode: String) async throws -> NewResp {
        var b: [String: Any] = ["cwd": cwd, "prompt": prompt, "modeId": mode]
        if let model, !model.isEmpty { b["model"] = model }
        return try await post("/api/local/new", b)
    }
    func prompt(_ id: String, cwd: String, text: String) async throws -> [String: StringOrInt] {
        try await post("/api/local/prompt", ["sessionId": id, "cwd": cwd, "text": text])
    }
    func cancel(_ id: String, cwd: String) async throws -> [String: StringOrInt] {
        try await post("/api/local/cancel", ["sessionId": id, "cwd": cwd])
    }
    func setConfig(_ id: String, cwd: String, configId: String, value: String) async throws -> [String: StringOrInt] {
        try await post("/api/local/config", ["sessionId": id, "cwd": cwd, "configId": configId, "value": value])
    }
    func permission(permKey: Int, optionId: String) async throws -> [String: StringOrInt] {
        try await post("/api/local/permission", ["permKey": permKey, "optionId": optionId])
    }
    func takeover(_ id: String, cwd: String) async throws -> [String: StringOrInt] {
        try await post("/api/local/takeover", ["sessionId": id, "cwd": cwd])
    }
    func cloudSessions() async throws -> [CloudSess] { try await request("/api/cloud/sessions") }
    func cloudGet(_ id: String) async throws -> CloudDetail { try await request("/api/cloud/get?id=\(id)") }
    func cloudMessages(_ id: String) async throws -> [CMsg] { try await request("/api/cloud/messages?id=\(id)") }
    func newCloud(prompt: String, mode: String, bypass: Bool, repos: [String], acu: Int?) async throws -> NewResp {
        var b: [String: Any] = ["prompt": prompt, "devin_mode": mode]
        if bypass { b["bypass_approval"] = true }
        if !repos.isEmpty { b["repos"] = repos }
        if let acu { b["max_acu_limit"] = acu }
        return try await post("/api/cloud/new", b)
    }
    func cloudMsg(_ id: String, text: String) async throws -> [String: StringOrInt] {
        try await post("/api/cloud/msg", ["id": id, "message": text])
    }
    func cloudArchive(_ id: String) async throws -> [String: StringOrInt] {
        try await post("/api/cloud/archive", ["id": id])
    }
}

// loose JSON scalar for responses we don't care about
enum StringOrInt: Codable {
    case s(String), n(Int)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .s(s); return }
        if let n = try? c.decode(Int.self) { self = .n(n); return }
        self = .s("")
    }
    func encode(to encoder: Encoder) throws {}
}
extension String { var urlEnc: String { addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self } }
