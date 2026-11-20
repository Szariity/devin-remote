import Foundation

struct Ping: Codable {
    let ok: Bool?
    let hasApi: Bool?
    let workspaces: [String]?
}

struct SessRow: Codable, Identifiable {
    var id: String { sessionId }
    let sessionId: String
    let title: String?
    let cwd: String?
    let updatedAt: String?
    let status: String?
    let source: String?
    enum CodingKeys: String, CodingKey { case title, cwd, updatedAt, status, source; case sessionId = "id" }
}

struct CloudSess: Decodable, Identifiable {
    var id: String { devinId }
    let devinId: String
    let title: String?
    let status: String?
    let statusEnum: String?
    let updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case title, status
        case devinId = "devin_id"
        case statusEnum = "status_enum"
        case updatedAt = "updated_at"
        case sid2 = "session_id"
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        devinId = (try? c.decode(String.self, forKey: .devinId)) ?? (try? c.decode(String.self, forKey: .sid2)) ?? UUID().uuidString
        title = try? c.decode(String.self, forKey: .title)
        status = try? c.decode(String.self, forKey: .status)
        statusEnum = try? c.decode(String.self, forKey: .statusEnum)
        updatedAt = try? c.decode(String.self, forKey: .updatedAt)
    }
    var effectiveStatus: String { statusEnum ?? status ?? "unknown" }
}

struct CloudDetail: Codable {
    let title: String?
    let status: String?
    let statusEnum: String?
    enum CodingKeys: String, CodingKey { case title, status; case statusEnum = "status_enum" }
}

struct CMsg: Codable, Identifiable {
    var id: String { (ts ?? "") + (text?.prefix(20) ?? "") }
    let role: String?
    let text: String?
    let ts: String?
}

struct Transcript: Codable {
    let session: SessState
}

struct SessState: Codable {
    var entries: [Entry] = []
    var status: String?
    var mode: String?
    var configOptions: [ConfigOpt]?
}

struct ConfigOpt: Codable, Identifiable {
    var id: String
    let name: String?
    let category: String?
    let currentValue: String?
    let options: [CfgValue]?
}
struct CfgValue: Codable, Identifiable {
    var id: String { value }
    let value: String
    let name: String?
    let description: String?
}

struct Entry: Codable, Identifiable {
    var id: String { (k ?? "?") + String(toolCallId ?? "") + String(permKey ?? -1) + (text?.prefix(16) ?? "") + String(title?.prefix(16) ?? "") }
    let k: String?
    let text: String?
    let chunk: Int?
    let toolCallId: String?
    let title: String?
    let kind: String?
    let status: String?
    let content: [Brief]?
    let locations: [Loc]?
    let entries: [PlanEnt]?
    let permKey: Int?
    let options: [PermOpt]?
}
struct Brief: Codable { let t: String?; let v: String?; let v2: String? }
struct Loc: Codable { let path: String? }
struct PlanEnt: Codable { let content: String?; let status: String? }
struct PermOpt: Codable, Identifiable {
    var id: String { optionId }
    let optionId: String
    let name: String?
    let kind: String?
}
struct NewResp: Codable {
    let sessionId: String?
    let devin_id: String?
    let session_id: String?
    let url: String?
    var id: String { sessionId ?? devin_id ?? session_id ?? "" }
}
