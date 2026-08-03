// Optional profile: name and email are never required to play. Identity is
// the anonymous device; these fields just attach a human to it.

import SwiftUI

struct ProfileView: View {
    @Environment(SyncService.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var saving = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
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
                            Text(saved ? "Saved ✓" : "Save")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(saving)
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
                if let profile = await sync.profile() {
                    name = profile.name ?? ""
                    email = profile.email ?? ""
                }
            }
        }
    }

    private func save() {
        saving = true
        saved = false
        Task {
            saved = await sync.updateProfile(
                name: name.isEmpty ? nil : name,
                email: email.isEmpty ? nil : email
            )
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
