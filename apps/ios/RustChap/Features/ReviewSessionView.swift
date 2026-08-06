// One review run: prompt, reveal, rate, next.
//
// A missed card is re-queued to the end of the same run (the standard
// "learning steps" behaviour) so every session ends with you having recalled
// it at least once. The run ends when the queue empties, and nothing is
// waiting for you afterwards.

import SwiftData
import SwiftUI

/// A named list of cards to run through. Identifiable so it can drive a sheet.
struct ReviewQueue: Identifiable {
    let id = UUID()
    let title: String
    let cards: [ReviewCard]
}

struct ReviewSessionView: View {
    let queue: ReviewQueue

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var reviewRecords: [ReviewRecord]

    @State private var pending: [ReviewCard] = []
    @State private var revealed = false
    @State private var tally: [ReviewRating: Int] = [:]
    @State private var reviewedCount = 0
    @State private var lastOutcome: String?
    @State private var startedAt = Date.now

    private var current: ReviewCard? { pending.first }

    var body: some View {
        NavigationStack {
            Group {
                if let card = current {
                    cardView(card)
                } else {
                    summary
                }
            }
            .navigationTitle(current == nil ? "Done" : queue.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if pending.isEmpty && reviewedCount == 0 { pending = queue.cards }
            // Screenshot automation: start on the revealed side.
            if ProcessInfo.processInfo.arguments.contains("--reveal") { revealed = true }
        }
    }

    // MARK: - The card

    private func cardView(_ card: ReviewCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(card.kind.label.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                Spacer()
                Text("\(reviewedCount + 1) of \(reviewedCount + pending.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Inline markdown (`code`) like lesson prose - concept text
                    // is written with backticks around types and keywords.
                    Text(.init(card.prompt))
                        .font(revealed ? .subheadline : .title3.weight(.semibold))
                        .foregroundStyle(revealed ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if revealed {
                        Divider()
                        Text(.init(card.answer))
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let example = card.example {
                            CodeText(source: example.code)
                            if let caption = example.caption, !caption.isEmpty {
                                Text(caption)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            if !revealed {
                Text("Answer it in your head, then reveal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
            }

            if let lastOutcome {
                Label(lastOutcome, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
            }

            if revealed {
                HStack(spacing: 8) {
                    rateButton(.got, tint: .green)
                    rateButton(.shaky, tint: .orange)
                    rateButton(.missed, tint: .red)
                }
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { revealed = true }
                } label: {
                    Text("Reveal")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func rateButton(_ rating: ReviewRating, tint: Color) -> some View {
        Button {
            record(rating)
        } label: {
            Text(rating.label)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rating

    private func record(_ rating: ReviewRating) {
        guard let card = pending.first else { return }
        let cache = ReviewProgress.records(reviewRecords)
        let entry = ReviewProgress.record(for: card.id, in: modelContext, cache: cache)
        entry.apply(rating)
        try? modelContext.save()

        tally[rating, default: 0] += 1
        reviewedCount += 1
        pending.removeFirst()
        // Standard learning-step: a miss comes back later in this same run.
        if rating == .missed {
            pending.append(card)
            lastOutcome = "\(shortTitle(card)) comes back at the end of this run."
        } else {
            lastOutcome = "\(shortTitle(card)) → \(entry.state.label)."
        }
        revealed = false
    }

    private func shortTitle(_ card: ReviewCard) -> String {
        card.kind.label
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "brain")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("\(reviewedCount) reviewed")
                    .font(.title3.weight(.semibold))
                Text("Nothing else is waiting for you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                stat("\(tally[.got] ?? 0)", "Got it", .green)
                stat("\(tally[.shaky] ?? 0)", "Shaky", .orange)
                stat("\(tally[.missed] ?? 0)", "No idea", .red)
            }
            .padding(.horizontal)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
