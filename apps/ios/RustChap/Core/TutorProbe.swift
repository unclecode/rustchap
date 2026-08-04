// Spike for the on-device AI tutor (phase-8 experiment): `--fm-probe` prints
// Foundation Models availability and one canned generation to stdout, read
// from the Mac via `devicectl device process launch --console`. Not user-facing.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum TutorProbe {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--fm-probe") else { return }
        Task { await run() }
    }

    private static func run() async {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            print("FM-PROBE: iOS < 26 — FoundationModels not present")
            return
        }
        let model = SystemLanguageModel.default
        print("FM-PROBE availability: \(model.availability)")
        guard case .available = model.availability else { return }

        let session = LanguageModelSession(
            instructions: """
            You are a concise Rust tutor inside a puzzle game. The player is an \
            experienced programmer new to Rust. Answer in under 120 words. If you \
            are not sure, say so rather than guessing.
            """
        )
        let question = "Why is &str usually a better parameter type than &String?"
        print("FM-PROBE question: \(question)")
        let start = Date()
        do {
            let response = try await session.respond(to: question)
            print("FM-PROBE latency: \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
            print("FM-PROBE answer: \(response.content)")
        } catch {
            print("FM-PROBE error: \(error)")
        }

        // Round 2 — grounded: same question, but the session is pinned to the
        // material the app already bundles (concept lectures + a puzzle
        // explanation), which is how the real TutorSheet would work.
        var material: [String] = []
        for conceptId in ["borrow", "deref-coercion", "move"] {
            if let url = Bundle.main.url(forResource: "concepts/\(conceptId)", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let concept = try? JSONDecoder().decode(Concept.self, from: data) {
                material.append("## \(concept.title)\n" + concept.lecture.joined(separator: "\n"))
            }
        }
        if let url = Bundle.main.url(
            forResource: "packs/move-or-borrow/puzzles/move-or-borrow.002", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let puzzle = try? JSONDecoder().decode(Puzzle.self, from: data) {
            material.append("## Puzzle explanation (\(puzzle.title))\n" + puzzle.explanation)
        }
        print("FM-PROBE grounding sources: \(material.count)")
        let grounded = LanguageModelSession(
            instructions: """
            You are a concise Rust tutor inside a puzzle game. The player is an \
            experienced programmer new to Rust. Answer in under 120 words, using ONLY \
            the reference material below. If the material does not cover the question, \
            say you are not sure — never invent Rust rules.

            # Reference material
            \(material.joined(separator: "\n\n"))
            """
        )
        let start2 = Date()
        do {
            let response = try await grounded.respond(to: question)
            print("FM-PROBE grounded latency: \(String(format: "%.1f", Date().timeIntervalSince(start2)))s")
            print("FM-PROBE grounded answer: \(response.content)")
        } catch {
            print("FM-PROBE grounded error: \(error)")
        }
        #else
        print("FM-PROBE: SDK lacks FoundationModels")
        #endif
    }
}
