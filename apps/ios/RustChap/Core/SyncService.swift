// Cloud sync (build-order step 19, client side). The server's merge is the
// authority: we push local records, receive the merged set, and overwrite
// local state with it. Identity lives in the Keychain (survives reinstalls),
// so a fresh install pulls everything back with an empty push.

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SyncService {
    enum State: Equatable {
        case idle
        case syncing
        case synced(Date)
        case offline
    }

    private(set) var state: State = .idle
    private(set) var deviceId: String?

    private let api = APIClient.fromEnvironment()
    private let context: ModelContext

    init(container: ModelContainer) {
        context = container.mainContext
        deviceId = DeviceCredentials.deviceId
    }

    private func dlog(_ message: String) {
        print("[sync] \(message)")
        let url = URL.documentsDirectory.appending(path: "sync.log")
        let line = "\(Date.now) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: Local profile cache (works offline; pushed when the server returns)

    private static let nameKey = "profile_name"
    private static let emailKey = "profile_email"
    private static let dirtyKey = "profile_dirty"

    var localProfile: (name: String, email: String) {
        (UserDefaults.standard.string(forKey: Self.nameKey) ?? "",
         UserDefaults.standard.string(forKey: Self.emailKey) ?? "")
    }

    private var profileDirty: Bool {
        get { UserDefaults.standard.bool(forKey: Self.dirtyKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.dirtyKey) }
    }

    /// Called at launch: ensure identity exists, then reconcile with the server.
    func bootstrap() async {
        dlog("bootstrap: token present = \(DeviceCredentials.token != nil)")
        await ensureRegistered()
        await pushProfileIfDirty()
        await syncNow()
    }

    private func pushProfileIfDirty() async {
        guard profileDirty, DeviceCredentials.token != nil else { return }
        let (name, email) = localProfile
        if (try? await api.updateProfile(
            name: name.isEmpty ? nil : name,
            email: email.isEmpty ? nil : email
        )) != nil {
            profileDirty = false
            dlog("pending profile pushed")
        }
    }

    private func ensureRegistered() async {
        guard DeviceCredentials.token == nil else {
            deviceId = DeviceCredentials.deviceId
            return
        }
        do {
            let registered = try await api.register(name: nil, email: nil)
            DeviceCredentials.deviceId = registered.deviceId
            DeviceCredentials.token = registered.token
            deviceId = registered.deviceId
            dlog("registered \(registered.deviceId.prefix(8)); keychain readback = \(DeviceCredentials.token != nil)")
        } catch {
            dlog("register failed: \(error)")
            state = .offline
        }
    }

    /// Push all local records, apply the server's merged truth back.
    /// A 401 means the server no longer knows our token (revoked/wiped) —
    /// drop the identity, register fresh, and retry once.
    func syncNow() async {
        guard DeviceCredentials.token != nil else {
            dlog("no token — skipping sync")
            return
        }
        state = .syncing
        do {
            try await pushAndApply()
        } catch APIError.badStatus(401) {
            dlog("token rejected — re-registering")
            DeviceCredentials.token = nil
            DeviceCredentials.deviceId = nil
            await ensureRegistered()
            do {
                try await pushAndApply()
            } catch {
                dlog("sync after re-register failed: \(error)")
                state = .offline
            }
        } catch {
            dlog("sync failed: \(error)")
            state = .offline
        }
    }

    private func pushAndApply() async throws {
        let local = (try? context.fetch(FetchDescriptor<PuzzleProgressRecord>())) ?? []
        dlog("pushing \(local.count) records")
        let merged = try await api.syncProgress(local.map(Self.wire))
        apply(merged)
        state = .synced(.now)
        dlog("synced; server returned \(merged.count) records")
    }

    // MARK: Profile

    func profile() async -> DeviceProfileWire? {
        try? await api.profile()
    }

    /// Always saves locally; returns whether the server also has it now.
    /// Offline saves are pushed automatically on the next bootstrap.
    func updateProfile(name: String?, email: String?) async -> Bool {
        UserDefaults.standard.set(name ?? "", forKey: Self.nameKey)
        UserDefaults.standard.set(email ?? "", forKey: Self.emailKey)
        do {
            try await api.updateProfile(name: name, email: email)
            profileDirty = false
            return true
        } catch {
            profileDirty = true
            return false
        }
    }

    // MARK: Mapping

    private static func wire(_ record: PuzzleProgressRecord) -> ProgressWire {
        ProgressWire(
            puzzleId: record.puzzleId,
            puzzleVersion: record.puzzleVersion,
            solved: record.solved,
            bestRank: record.bestRankRaw,
            bestMetrics: record.bestMetrics,
            attemptCount: record.attemptCount,
            firstSolvedAt: record.firstSolvedAt,
            bestSolvedAt: record.bestSolvedAt,
            updatedAt: record.updatedAt
        )
    }

    private func apply(_ merged: [ProgressWire]) {
        for wire in merged {
            let record = ProgressRecorder.fetch(puzzleId: wire.puzzleId, in: context)
                ?? {
                    let fresh = PuzzleProgressRecord(
                        puzzleId: wire.puzzleId, puzzleVersion: wire.puzzleVersion)
                    context.insert(fresh)
                    return fresh
                }()
            record.puzzleVersion = wire.puzzleVersion
            record.solved = wire.solved
            record.bestRankRaw = wire.bestRank
            if let data = try? JSONEncoder().encode(wire.bestMetrics) {
                record.bestMetricsJSON = String(decoding: data, as: UTF8.self)
            }
            // An attempt made while the sync was in flight must not be lost.
            record.attemptCount = max(record.attemptCount, wire.attemptCount)
            record.firstSolvedAt = wire.firstSolvedAt
            record.bestSolvedAt = wire.bestSolvedAt
            record.updatedAt = wire.updatedAt
        }
        try? context.save()
    }
}
