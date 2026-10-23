import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var syncEngine: SyncEngine
    @ObservedObject var settings: AppSettings
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

        Button {
            coordinator.openSettings()
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",")

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
