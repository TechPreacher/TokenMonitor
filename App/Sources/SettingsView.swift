// App/Sources/SettingsView.swift
import SwiftUI
import TokenMonitorKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var adminKey = ""
    @State private var saveError = false
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Admin API Key").font(.headline)
            Text("Needed for API spend. Create one (sk-ant-admin…) in the Anthropic Console. Stored in your Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            SecureField("sk-ant-admin01-…", text: $adminKey)
                .textFieldStyle(.roundedBorder)
            if saveError {
                Text("Could not save to Keychain").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    do {
                        try KeychainCredentialStore().writeAdminAPIKey(
                            adminKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        onSave()
                        dismiss()
                    } catch { saveError = true }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(adminKey.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
