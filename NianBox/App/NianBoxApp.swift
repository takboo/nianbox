import SwiftUI

@main
struct NianBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let coordinator = AppCoordinator.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: coordinator.store, syncEngine: coordinator.syncEngine, settings: coordinator.settings, coordinator: coordinator)
        } label: {
            Image("MenuBarIcon").accessibilityLabel("NianBox")
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
