// Where tutor answers come from. Two engines behind one interface:
// on-device Foundation Models, or OpenRouter (cloud) when the player enables
// it in Settings and has stored an API key. Cloud failures fall back to the
// local engine for that question — the tutor degrades, never breaks.
// Both engines stream CUMULATIVE text snapshots, matching the chat UI.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Settings

enum TutorEngineKind: String {
    case local
    case openRouter
}

enum TutorSettings {
    private static let engineKey = "tutorEngine"
    private static let apiKeyAccount = "openrouter_api_key"

    /// Pinned snapshot: the cheapest capable model on OpenRouter as of
    /// 2026-08 ($0.09/M in, $0.18/M out). One constant to move.
    static let openRouterModel = "deepseek/deepseek-v4-flash-0731"
    static let openRouterModelDisplayName = "DeepSeek V4 Flash"

    static var engineKind: TutorEngineKind {
        get {
            TutorEngineKind(
                rawValue: UserDefaults.standard.string(forKey: engineKey) ?? "") ?? .local
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: engineKey) }
    }

    static var openRouterKey: String? {
        get { Keychain.string(for: apiKeyAccount) }
        set {
            if let newValue, !newValue.isEmpty {
                Keychain.set(newValue, for: apiKeyAccount)
            } else {
                Keychain.delete(apiKeyAccount)
            }
        }
    }

    static var cloudConfigured: Bool {
        engineKind == .openRouter && !(openRouterKey ?? "").isEmpty
    }
}

// MARK: - Engine interface

@MainActor
protocol TutorEngine {
    /// Stream cumulative snapshots of the answer to one question.
    /// Implementations keep the conversation state between calls.
    func reply(to question: String) -> AsyncThrowingStream<String, Error>
}

@MainActor
enum TutorEngineFactory {
    /// Engine per the player's settings; nil when nothing can answer.
    /// `transcript` seeds a resumed conversation (persisted turns).
    static func make(context: TutorContext, transcript: [TutorMessage]) -> (any TutorEngine)? {
        if TutorSettings.cloudConfigured, let key = TutorSettings.openRouterKey {
            return OpenRouterTutorEngine(context: context, transcript: transcript, apiKey: key)
        }
        return makeLocal(context: context, transcript: transcript)
    }

    /// The on-device engine alone — also the fallback target for cloud errors.
    static func makeLocal(context: TutorContext, transcript: [TutorMessage]) -> (any TutorEngine)? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability
        else { return nil }
        return LocalTutorEngine(context: context, transcript: transcript)
        #else
        return nil
        #endif
    }
}

// MARK: - Local (Foundation Models)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@MainActor
final class LocalTutorEngine: TutorEngine {
    private let session: LanguageModelSession

    init(context: TutorContext, transcript: [TutorMessage]) {
        // A fresh session folds the recent turns into its instructions so a
        // resumed conversation keeps its thread (FM sessions are ephemeral).
        var instructions = context.instructions
        let replay = transcript.suffix(6).filter { $0.role != .failure }
        if !replay.isEmpty {
            let turns = replay.map { message in
                "\(message.role == .player ? "Player" : "Tutor"): \(message.text)"
            }.joined(separator: "\n")
            instructions += "\n\n# Recent conversation (continue it)\n\(turns)"
        }
        session = LanguageModelSession(instructions: instructions)
    }

    func reply(to question: String) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let task = Task {
            do {
                for try await partial in session.streamResponse(to: question) {
                    continuation.yield(partial.content)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}
#endif

// MARK: - OpenRouter (cloud)

@MainActor
final class OpenRouterTutorEngine: TutorEngine {
    private struct WireMessage: Codable {
        let role: String
        let content: String
    }

    /// Streaming chunk — only the fields we read. `reasoning` deltas from
    /// thinking models are deliberately ignored; players get the answer.
    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
        }
        let choices: [Choice]
    }

    private let apiKey: String
    private var history: [WireMessage]

    init(context: TutorContext, transcript: [TutorMessage], apiKey: String) {
        self.apiKey = apiKey
        // Cloud chat is stateless HTTP: the real transcript rides along.
        history = [WireMessage(role: "system", content: context.instructions)]
        for message in transcript where message.role != .failure {
            history.append(WireMessage(
                role: message.role == .player ? "user" : "assistant",
                content: message.text))
        }
    }

    func reply(to question: String) -> AsyncThrowingStream<String, Error> {
        history.append(WireMessage(role: "user", content: question))
        let request = makeRequest()
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let task = Task {
            var answer = ""
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = line.dropFirst(6)
                    if payload == "[DONE]" { break }
                    guard let chunk = try? JSONDecoder().decode(
                        Chunk.self, from: Data(payload.utf8)),
                        let delta = chunk.choices.first?.delta?.content, !delta.isEmpty
                    else { continue }
                    answer += delta
                    continuation.yield(answer)
                }
                guard !answer.isEmpty else { throw URLError(.zeroByteResource) }
                self.history.append(WireMessage(role: "assistant", content: answer))
                continuation.finish()
            } catch {
                // The unanswered question must not pollute the transcript.
                if self.history.last?.role == "user" {
                    self.history.removeLast()
                }
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func makeRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": TutorSettings.openRouterModel,
            "stream": true,
            "messages": history.map { ["role": $0.role, "content": $0.content] },
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
}
