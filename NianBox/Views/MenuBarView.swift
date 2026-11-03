import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var syncEngine: SyncEngine
    @ObservedObject var settings: AppSettings
    @ObservedObject var uiState: PanelUIState
    @ObservedObject var updates: UpdateChecker
    let coordinator: AppCoordinator

    var body: some View {
        Button("Show NianBox", systemImage: "archivebox") {
            coordinator.showPanel()
        }

        Button("New task", systemImage: "plus") {
            coordinator.showNewTask()
        }
        .keyboardShortcut(settings.captureShortcut?.menuShortcut)

        Divider()

        HStack {
            Text("Active Tasks")
            Spacer()
            Text("\(activeTaskCount)")
                .foregroundStyle(.secondary)
        }

        Text(syncEngine.status).font(.caption).foregroundStyle(.secondary)
        if uiState.isComposerPresented { Text("Draft open · not yet saved") }
        if syncEngine.pendingCount > 0 { Text("\(syncEngine.pendingCount) changes waiting to sync") }
        if syncEngine.blockedCount > 0 { Text("\(syncEngine.blockedCount) blocked changes retained for export") }
        Button("Sync now") { syncEngine.requestSync() }
            .disabled(syncEngine.isSyncing || syncEngine.activity == .localOnly)

        Button {
            coordinator.openSettings()
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",")

        Button("Check for Updates…", systemImage: "arrow.down.circle") {
            coordinator.checkForUpdates()
        }
        .disabled(updates.isChecking)
        .accessibilityIdentifier("menu-check-for-updates")
        if let release = updates.availableRelease {
            Link("NianBox \(release.version) available…", destination: release.url)
        }

        Divider()

        Button("Quit NianBox", systemImage: "power") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var activeTaskCount: Int {
        store.snapshot(for: .tasks).activeCount
    }
}
