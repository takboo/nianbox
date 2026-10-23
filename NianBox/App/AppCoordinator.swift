import AppKit
import Combine
import SwiftData

@MainActor
final class AppCoordinator {
    static let shared = AppCoordinator()

    let settings: AppSettings
    let store: TaskStore
    let syncEngine: SyncEngine
    let loginItemService: LoginItemService
    let uiState: PanelUIState

    private let panelController: PeekPanelController
    private let settingsWindowController: SettingsWindowController
    private let hoverMonitor: CornerHoverMonitor
    private let isUITesting: Bool
    private let isRunningTests: Bool
    private var menuNotificationTokens: [NSObjectProtocol] = []
    private var hasStarted = false
    private lazy var newTaskHotKey = GlobalHotKey { [weak self] in
        self?.showNewTask()
    }

    private init() {
        let environment = ProcessInfo.processInfo.environment
        isUITesting = environment["NIANBOX_UI_TESTING"] == "1"
        isRunningTests = environment["NIANBOX_TESTING"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil

        let settings = AppSettings()
        let container: ModelContainer
        do {
            container = try PersistenceController.makeContainer(inMemory: isUITesting || isRunningTests)
        } catch {
            fatalError("Unable to open NianBox store; existing files were preserved: \(error)")
        }

        let store = TaskStore(container: container)
        let syncEngine: SyncEngine
        if isUITesting, let path = environment["NIANBOX_SYNC_FIXTURE"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let fixture = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let url = fixture["url"] as? String, let token = fixture["token"] as? String,
           let client = try? ServerClient(url: url, token: token) {
            syncEngine = SyncEngine(store: store, transport: client)
        } else {
            syncEngine = SyncEngine(store: store)
        }
        let uiState = PanelUIState()
        let loginItemService = LoginItemService()
        let settingsWindowController = SettingsWindowController(
            settings: settings, loginItemService: loginItemService, store: store, syncEngine: syncEngine
        )
        let panelController = PeekPanelController(store: store, settings: settings, uiState: uiState)

        self.settings = settings
        self.store = store
        self.syncEngine = syncEngine
        self.uiState = uiState
        self.panelController = panelController
        self.loginItemService = loginItemService
        self.settingsWindowController = settingsWindowController
        hoverMonitor = CornerHoverMonitor(
            settings: settings,
            panelController: panelController,
            uiState: uiState,
            store: store
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        observeMenuTracking()

        if isUITesting {
            hoverMonitor.keepVisibleForUITesting()
            if ProcessInfo.processInfo.environment["NIANBOX_SYNC_FIXTURE"] != nil { syncEngine.start() }
            return
        }

        guard !isRunningTests else { return }
        syncEngine.start()
        settings.registerShortcut = { [weak self] shortcut in try self?.newTaskHotKey.replace(with: shortcut) }
        settings.shortcutRecordingChanged = { [weak self] recording in
            guard let self else { return }
            if recording { self.newTaskHotKey.unregister() }
            else { try self.newTaskHotKey.replace(with: self.settings.captureShortcut) }
        }
        do { try newTaskHotKey.replace(with: settings.captureShortcut) }
        catch { settings.shortcutError = error.localizedDescription }
        hoverMonitor.start()
        if !settings.hasShownWelcome {
            settings.markWelcomeShown()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.openSettings()
            }
        }
    }

    func stop() {
        syncEngine.stop()
        hoverMonitor.stop()
        newTaskHotKey.unregister()
        menuNotificationTokens.forEach(NotificationCenter.default.removeObserver)
        menuNotificationTokens.removeAll()
        hasStarted = false
    }

    func showPanel() {
        syncEngine.requestSync()
        hoverMonitor.revealProgrammatically()
    }

    func showNewTask() {
        hoverMonitor.revealProgrammatically(openComposer: true, scope: .tasks)
    }

    func openSettings() {
        settingsWindowController.show()
    }

    private func observeMenuTracking() {
        let center = NotificationCenter.default
        menuNotificationTokens = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.uiState.isMenuTracking = true }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.uiState.isMenuTracking = false }
            }
        ]
    }
}
