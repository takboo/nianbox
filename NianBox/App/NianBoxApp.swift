import SwiftUI

@main
struct NianBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let coordinator = AppCoordinator.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: coordinator.store, syncEngine: coordinator.syncEngine, settings: coordinator.settings,
                        uiState: coordinator.uiState, coordinator: coordinator)
        } label: {
            MenuBarIconLabel(lifecycle: coordinator.menuBarLifecycle)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    coordinator.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

private struct MenuBarIconLabel: View {
    @ObservedObject var lifecycle: MenuBarLifecycle

    var body: some View {
        Image(nsImage: lifecycle.image)
            .renderingMode(.template)
            .accessibilityLabel(lifecycle.accessibilityLabel)
            .help(lifecycle.accessibilityLabel)
    }
}
