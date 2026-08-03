// Talks to the RustChap backend (services/api). Dev default is
// http://localhost:8787 — the simulator shares the Mac's loopback. Override
// with the `--api <url>` launch argument (e.g. the Mac's LAN IP for a device).

import Foundation

struct APIClient {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        session = URLSession(configuration: config)
    }

    static func fromEnvironment() -> APIClient {
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "--api"),
           args.indices.contains(flag + 1),
           let url = URL(string: args[flag + 1]) {
            return APIClient(baseURL: url)
        }
        return APIClient(baseURL: URL(string: "http://localhost:8787")!)
    }

    func packs() async throws -> [Pack] {
        try await get("v1/packs")
    }

    func packDetail(_ packId: String) async throws -> PackDetail {
        try await get("v1/packs/\(packId)")
    }

    func evaluate(puzzleId: String, submission: SubmissionBody) async throws -> EvaluateResponse {
        try await send("POST", "v1/puzzles/\(puzzleId)/evaluate", body: submission)
    }

    // MARK: Identity + sync (anonymous device, token from the Keychain)

    func register(name: String?, email: String?) async throws -> RegisteredDevice {
        try await send("POST", "v1/devices/register", body: ProfileBody(name: name, email: email))
    }

    func profile() async throws -> DeviceProfileWire {
        try await get("v1/devices/me")
    }

    func updateProfile(name: String?, email: String?) async throws {
        let _: EmptyReply = try await send(
            "PUT", "v1/devices/me",
            body: ProfileBody(name: name, email: email)
        )
    }

    func syncProgress(_ records: [ProgressWire]) async throws -> [ProgressWire] {
        let reply: SyncBody = try await send("POST", "v1/progress/sync", body: SyncBody(records: records))
        return reply.records
    }

    // MARK: Plumbing

    private func request(_ method: String, _ path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = DeviceCredentials.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send<Body: Encodable, Reply: Decodable>(
        _ method: String, _ path: String, body: Body
    ) async throws -> Reply {
        var request = request(method, path)
        request.httpBody = try JSONEncoder.api.encode(body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError.badStatus(status) }
        if data.isEmpty, let empty = EmptyReply() as? Reply { return empty }
        return try JSONDecoder.api.decode(Reply.self, from: data)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await session.data(for: request("GET", path))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError.badStatus(status) }
        return try JSONDecoder.api.decode(T.self, from: data)
    }
}

struct EmptyReply: Decodable {}

struct RegisteredDevice: Decodable {
    let deviceId: String
    let token: String

    private enum CodingKeys: String, CodingKey {
        case token
        case deviceId = "device_id"
    }
}

struct ProfileBody: Encodable {
    let name: String?
    let email: String?
}

struct DeviceProfileWire: Decodable {
    let deviceId: String
    let name: String?
    let email: String?

    private enum CodingKeys: String, CodingKey {
        case name, email
        case deviceId = "device_id"
    }
}

/// One puzzle's progress on the wire — both directions of /v1/progress/sync.
struct ProgressWire: Codable {
    let puzzleId: String
    let puzzleVersion: Int
    let solved: Bool
    let bestRank: String?
    let bestMetrics: [String: Int]
    let attemptCount: Int
    let firstSolvedAt: Date?
    let bestSolvedAt: Date?
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case solved
        case puzzleId = "puzzle_id"
        case puzzleVersion = "puzzle_version"
        case bestRank = "best_rank"
        case bestMetrics = "best_metrics"
        case attemptCount = "attempt_count"
        case firstSolvedAt = "first_solved_at"
        case bestSolvedAt = "best_solved_at"
        case updatedAt = "updated_at"
    }
}

struct SyncBody: Codable {
    let records: [ProgressWire]
}

// The server (chrono) emits RFC3339 with fractional seconds; plain .iso8601
// on Foundation coders can't parse those. One shared pair handles both forms.
extension JSONDecoder {
    static let api: JSONDecoder = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: text) ?? plain.date(from: text) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "unparseable date \(text)"
            ))
        }
        return decoder
    }()
}

extension JSONEncoder {
    static let api: JSONEncoder = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractional.string(from: date))
        }
        return encoder
    }()
}

enum APIError: Error {
    case badStatus(Int)
}

/// GET /v1/packs/{id}: pack fields flattened at the top level + full puzzles.
struct PackDetail: Decodable {
    let pack: Pack
    let puzzles: [Puzzle]

    private enum CodingKeys: String, CodingKey { case puzzles }

    init(from decoder: Decoder) throws {
        pack = try Pack(from: decoder)
        puzzles = try decoder.container(keyedBy: CodingKeys.self)
            .decode([Puzzle].self, forKey: .puzzles)
    }
}

struct EvaluateResponse: Decodable {
    let cached: Bool
    let result: EvalResult
}

/// POST body — field names must match the Rust `Submission` type.
struct SubmissionBody: Encodable {
    let puzzleId: String
    let puzzleVersion: Int
    let operations: [PuzzleOperation]

    private enum CodingKeys: String, CodingKey {
        case operations
        case puzzleId = "puzzle_id"
        case puzzleVersion = "puzzle_version"
    }
}

extension PuzzleOperation: Encodable {
    private enum CodingKeys: String, CodingKey {
        case op, order
        case slotId = "slot_id"
        case choiceId = "choice_id"
        case candidateId = "candidate_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .select(let slotId, let choiceId):
            try container.encode("select", forKey: .op)
            try container.encode(slotId, forKey: .slotId)
            try container.encode(choiceId, forKey: .choiceId)
        case .arrange(let order):
            try container.encode("arrange", forKey: .op)
            try container.encode(order, forKey: .order)
        case .pick(let candidateId):
            try container.encode("pick", forKey: .op)
            try container.encode(candidateId, forKey: .candidateId)
        }
    }
}
