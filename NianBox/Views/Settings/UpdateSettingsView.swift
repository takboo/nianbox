import AppKit
import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updates: UpdateChecker
    @State private var copiedCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("App updates", systemImage: "arrow.down.circle").font(.headline)
                Spacer()
                Text("Version \(updates.currentVersion)").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Automatically check for updates", isOn: $updates.automaticallyChecks)
                .accessibilityIdentifier("automatic-update-checks")
            Text(updates.status)
                .font(.caption)
                .foregroundStyle(updates.errorMessage == nil ? Color.secondary : .orange)
                .accessibilityIdentifier("update-check-status")
            if let checked = updates.lastChecked {
                Text("Last checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Button("Check for Updates…") { Task { await updates.checkNow() } }
                    .disabled(updates.isChecking)
                    .accessibilityIdentifier("check-for-updates")
                if let release = updates.availableRelease {
                    Link("View release & download \(release.version)", destination: release.url)
                        .accessibilityIdentifier("download-app-update")
                }
            }
            Text("Checks public GitHub releases once a day. Downloads and installation are manual.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Homebrew upgrade").font(.caption.weight(.medium))
            HStack(spacing: 8) {
                Text(UpdateChecker.brewUpgradeCommand).font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    copiedCommand = NSPasteboard.general.setString(UpdateChecker.brewUpgradeCommand, forType: .string)
                } label: { Image(systemName: copiedCommand ? "checkmark" : "doc.on.doc") }
                .buttonStyle(.plain)
                .help("Copy Homebrew upgrade command")
                .accessibilityLabel("Copy Homebrew upgrade command")
                .accessibilityIdentifier("copy-homebrew-upgrade")
            }
            Text("Save unfinished drafts before replacing or upgrading the app.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-update-settings")
    }
}
