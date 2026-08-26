// App/Sources/SettingsView.swift
import SwiftUI
import TokenMonitorKit

/// In-memory store wrapping a candidate admin key, so the existing
/// AdminCostClient can validate it before anything is written to Keychain.
private struct StaticKeyStore: CredentialStore {
    let key: String
    func readClaudeCodeOAuthToken() throws -> String { throw CredentialError.notFound }
    func readAdminAPIKey() -> String? { key }
    func writeAdminAPIKey(_ key: String) throws {}
}

struct SettingsView: View {
    private enum Phase: Equatable {
        case idle
        case validating
        case rejected            // API said 401/403 — not saved
        case unverifiable        // network error — offer save-anyway
        case keychainError
    }

    @Environment(\.dismiss) private var dismiss
    @State private var adminKey = ""
    @State private var phase: Phase = .idle
    @State private var storedKeySuffix: String?
    var onSave: () -> Void

    private var trimmedKey: String {
        adminKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Admin API Key").font(.headline)
            statusRow
            Text("Needed for API spend. Create one (sk-ant-admin…) in the Anthropic Console. Stored in your Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            SecureField("sk-ant-admin01-…", text: $adminKey)
                .textFieldStyle(.roundedBorder)
                .onChange(of: adminKey) { phase = .idle }
            feedbackRow
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                if phase == .unverifiable {
                    Button("Save anyway") { persist() }
                }
                Button("Save") { Task { await validateAndSave() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedKey.isEmpty || phase == .validating)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            if let key = KeychainCredentialStore().readAdminAPIKey() {
                storedKeySuffix = String(key.suffix(4))
            }
        }
    }

    @ViewBuilder private var statusRow: some View {
        if let suffix = storedKeySuffix {
            Label("Admin key stored (…\(suffix))", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        } else {
            Label("No key configured", systemImage: "circle.dashed")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var feedbackRow: some View {
        switch phase {
        case .validating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Verifying key with Anthropic API…").font(.caption).foregroundStyle(.secondary)
            }
        case .rejected:
            Text("Key rejected by Anthropic API — not saved")
                .font(.caption).foregroundStyle(.red)
        case .unverifiable:
            Text("Could not verify (offline?) — save anyway?")
                .font(.caption).foregroundStyle(.orange)
        case .keychainError:
            Text("Could not save to Keychain").font(.caption).foregroundStyle(.red)
        case .idle:
            EmptyView()
        }
    }

    private func validateAndSave() async {
        phase = .validating
        let client = AdminCostClient(credentials: StaticKeyStore(key: trimmedKey))
        do {
            _ = try await client.fetchMonthToDateCost(now: Date())
            persist()
        } catch FetchError.httpStatus(let status) where status == 401 || status == 403 {
            phase = .rejected
        } catch {
            phase = .unverifiable
        }
    }

    private func persist() {
        do {
            try KeychainCredentialStore().writeAdminAPIKey(trimmedKey)
            onSave()
            dismiss()
        } catch {
            phase = .keychainError
        }
    }
}
