// Optional profile + app settings. Name/email are never required to play;
// saves land locally first and reach the server when it's reachable.

import SwiftUI

struct ProfileView: View {
    @Environment(SyncService.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"

    @State private var name = ""
    @State private var email = ""
    @State private var saving = false
    @State private var saveState: SaveState = .none

    enum SaveState {
        case none, synced, localOnly
    }

    var body: some View {
        NavigationStack {
            Form {
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
