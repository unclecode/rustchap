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
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/puzzles/\(puzzleId)/evaluate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(submission)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(EvaluateResponse.self, from: data)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent(path))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
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
