// App/Sources/DashboardView.swift
import SwiftUI
import TokenMonitorKit

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    var onTogglePin: (Bool) -> Void
    @State private var showSettings = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                header
                subscriptionSection
                tokensSection
                costSection
                Spacer(minLength: 0)
            }
            .padding(16)
            ScanlineOverlay()
        }
        .frame(width: 320, height: 420)
        .background(Theme.background.opacity(0.92))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Theme.neonCyan.opacity(0.35), lineWidth: 1))
        .sheet(isPresented: $showSettings) {
            SettingsView { viewModel.startPolling() }
        }
    }

    private var header: some View {
        HStack {
            Text("TOKEN//MONITOR")
                .font(Theme.digits(14))
                .foregroundStyle(Theme.neonCyan)
                .shadow(color: Theme.neonCyan.opacity(0.9), radius: 5)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape").foregroundStyle(Theme.dimText)
            }
            .buttonStyle(.plain)
            Button {
                viewModel.isPinned.toggle()
                onTogglePin(viewModel.isPinned)
            } label: {
                Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(viewModel.isPinned ? Theme.neonMagenta : Theme.dimText)
            }
            .buttonStyle(.plain)
        }
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SUBSCRIPTION", status: viewModel.state.usageStatus)
            if let usage = viewModel.state.usage {
                NeonGauge(title: "5H Session", percent: usage.sessionPercent,
                          subtitle: usage.sessionResetsAt.map { "resets \(relative($0))" })
                NeonGauge(title: "Weekly", percent: usage.weeklyPercent,
                          subtitle: usage.weeklyResetsAt.map { "resets \(relative($0))" })
                ForEach(scopedLimits, id: \.scopeLabel) { limit in
                    NeonGauge(title: "Weekly · \(limit.scopeLabel ?? "?")",
                              percent: limit.percent, subtitle: nil)
                }
            } else {
                unavailableText(viewModel.state.usageStatus)
            }
        }
    }

    private var scopedLimits: [RateLimitInfo] {
        viewModel.state.usage?.limits.filter { $0.kind == .weeklyScoped } ?? []
    }

    private var tokensSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("TOKENS · LOCAL", status: viewModel.state.transcriptsStatus)
            if let transcripts = viewModel.state.transcripts {
                HStack(spacing: 16) {
                    stat("TODAY", value: transcripts.tokensToday.formatted())
                    stat("5H WINDOW", value: transcripts.tokensThisSessionWindow.formatted())
                }
            } else {
                unavailableText(viewModel.state.transcriptsStatus)
            }
        }
    }

    private var costSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("API SPEND · MTD", status: viewModel.state.costStatus)
            if let cost = viewModel.state.cost {
                Text(cost.monthToDateUSD, format: .currency(code: "USD"))
                    .font(Theme.digits(24))
                    .foregroundStyle(Theme.neonMagenta)
                    .shadow(color: Theme.neonMagenta.opacity(0.8), radius: 6)
            } else if case .unavailable(let reason) = viewModel.state.costStatus,
                      reason.contains("credentialsUnavailable") {
                Text("add admin key in settings ⚙")
                    .font(Theme.label).foregroundStyle(Theme.dimText)
            } else {
                unavailableText(viewModel.state.costStatus)
            }
        }
    }

    private func sectionLabel(_ text: String, status: SourceStatus) -> some View {
        HStack(spacing: 6) {
            Text(text).font(Theme.label).foregroundStyle(Theme.neonCyan.opacity(0.7))
            if status.isStale(maxAge: 300, now: Date()) {
                Text("stale").font(Theme.label).foregroundStyle(Theme.neonAmber)
            }
        }
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.label).foregroundStyle(Theme.dimText)
            Text(value).font(Theme.digits(16)).foregroundStyle(Theme.neonCyan)
        }
    }

    private func unavailableText(_ status: SourceStatus) -> some View {
        Text("no data").font(Theme.label).foregroundStyle(Theme.dimText)
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
