// Profile = progress picture + optional identity + app settings.
// Per the plan: solved counts, optimals, attempts, strongest concepts,
// concepts needing work — and no XP, coins, or badges.

import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(SyncService.self) private var sync
    @Environment(ContentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("tutorEngine") private var tutorEngine = TutorEngineKind.local.rawValue
    #if DEBUG
    @AppStorage(Progression.unlockAllKey) private var unlockAll = false
    #endif
    @State private var openRouterKey = TutorSettings.openRouterKey ?? ""
    @Query private var progress: [PuzzleProgressRecord]

    @State private var name = ""
    @State private var email = ""
    @State private var saving = false
    @State private var saveState: SaveState = .none

    enum SaveState {
        case none, synced, localOnly
    }

    private struct ConceptStrength: Identifiable {
        let id: String
        let title: String
        let solved: Int
        let total: Int
        let optimals: Int
        let attempts: Int
        var ratio: Double { total == 0 ? 0 : Double(solved) / Double(total) }
    }

    private func record(_ puzzleId: String) -> PuzzleProgressRecord? {
        progress.first { $0.puzzleId == puzzleId }
    }

    private var solvedCount: Int { progress.filter(\.solved).count }
    private var optimalCount: Int { progress.filter { $0.bestRank == .optimal }.count }
    private var attemptTotal: Int { progress.reduce(0) { $0 + $1.attemptCount } }

    private var conceptStrengths: [ConceptStrength] {
        store.concepts.values.map { concept in
            let puzzles = store.allPuzzles.filter { $0.puzzle.concepts.contains(concept.id) }
            let records = puzzles.compactMap { record($0.id) }
            return ConceptStrength(
                id: concept.id,
                title: concept.title,
                solved: records.filter(\.solved).count,
                total: puzzles.count,
                optimals: records.filter { $0.bestRank == .optimal }.count,
                attempts: records.reduce(0) { $0 + $1.attemptCount }
            )
        }
        .filter { $0.total > 0 }
    }

    private var strongest: [ConceptStrength] {
        conceptStrengths
            .filter { $0.solved > 0 }
            .sorted { ($0.ratio, $0.optimals) > ($1.ratio, $1.optimals) }
            .prefix(3).map { $0 }
    }

    private var needsWork: [ConceptStrength] {
        let strongestIds = Set(strongest.map(\.id))
        return conceptStrengths
            .filter { $0.attempts > 0 && $0.ratio < 1.0 && !strongestIds.contains($0.id) }
            .sorted { ($0.ratio, -$0.attempts) < ($1.ratio, -$1.attempts) }
            .prefix(3).map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        statBlock("\(solvedCount)/\(store.allPuzzles.count)", "solved")
                        Divider()
                        statBlock("\(optimalCount)", "optimal ★")
                        Divider()
                        statBlock("\(attemptTotal)", "attempts")
                    }
                } header: {
                    Text("Progress")
                }

                if !strongest.isEmpty {
                    Section("Strongest") {
                        ForEach(strongest) { conceptRow($0) }
                    }
                }
                if !needsWork.isEmpty {
                    Section("Needs more work") {
                        ForEach(needsWork) { conceptRow($0) }
                    }
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Theme")
                }

                Section {
                    Picker("Tutor answers", selection: $tutorEngine) {
                        Text("On-device").tag(TutorEngineKind.local.rawValue)
                        Text("OpenRouter").tag(TutorEngineKind.openRouter.rawValue)
                    }
                    if tutorEngine == TutorEngineKind.openRouter.rawValue {
                        SecureField("OpenRouter API key", text: $openRouterKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { TutorSettings.openRouterKey = openRouterKey }
                            .onChange(of: openRouterKey) { _, newValue in
                                TutorSettings.openRouterKey = newValue
                            }
                    }
                } header: {
                    Text("AI tutor")
                } footer: {
                    if tutorEngine == TutorEngineKind.openRouter.rawValue {
                        Text(
                            (openRouterKey.isEmpty
                                ? "No key yet — the tutor stays on-device. "
                                : "Cloud answers via \(TutorSettings.openRouterModel). ")
                            + "Falls back to the on-device model when the cloud fails.")
                    } else {
                        Text("Answers come from Apple's on-device model. Private and offline.")
                    }
                }

                Section {
                    TextField("Name (optional)", text: $name)
                        .textContentType(.name)
                    TextField("Email (optional)", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Both fields are optional — RustChap works without an account.")
                }

                Section {
                    Button {
                        save()
                    } label: {
                        if saving {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(saveLabel).frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(saving)
                } footer: {
                    if saveState == .localOnly {
                        Text("Server unreachable — saved on this device and will sync automatically when the server returns.")
                    }
                }

                Section {
                    HStack {
                        Text("Identity")
                        Spacer()
                        Text(shortDeviceId).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Sync")
                        Spacer()
                        Text(syncLabel).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Device")
                } footer: {
                    Text("Progress is tied to this device's Keychain identity and synced to the server — deleting and reinstalling the app restores it.")
                }

                #if DEBUG
                // Debug builds only, so it can never reach TestFlight or the
                // store. For reviewing content without playing the chain first.
                Section {
                    Toggle("Unlock every deck", isOn: $unlockAll)
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Opens every deck in every level for review. Your solved puzzles and stars are untouched, so turning this off restores the normal progression.")
                }
                #endif
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // Local cache renders instantly; server copy refreshes it when available.
                let local = sync.localProfile
                name = local.name
                email = local.email
                if let profile = await sync.profile() {
                    if name.isEmpty { name = profile.name ?? "" }
                    if email.isEmpty { email = profile.email ?? "" }
                }
            }
        }
    }

    private func statBlock(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func conceptRow(_ strength: ConceptStrength) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(strength.title)
                    .font(.subheadline)
                Spacer()
                Text("\(strength.solved)/\(strength.total)\(strength.optimals > 0 ? " · \(strength.optimals)★" : "")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: strength.ratio)
                .tint(strength.ratio == 1.0 ? .green : .accentColor)
        }
        .padding(.vertical, 2)
    }

    private var saveLabel: String {
        switch saveState {
        case .none: "Save"
        case .synced: "Saved ✓"
        case .localOnly: "Saved on device"
        }
    }

    private func save() {
        saving = true
        Task {
            let synced = await sync.updateProfile(
                name: name.isEmpty ? nil : name,
                email: email.isEmpty ? nil : email
            )
            saveState = synced ? .synced : .localOnly
            saving = false
        }
    }

    private var shortDeviceId: String {
        guard let id = sync.deviceId else { return "not registered" }
        return String(id.prefix(8))
    }

    private var syncLabel: String {
        switch sync.state {
        case .idle: "waiting"
        case .syncing: "syncing…"
        case .synced: "up to date"
        case .offline: "offline"
        }
    }
}
