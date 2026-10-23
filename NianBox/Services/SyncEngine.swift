import AppKit
import Combine
import Foundation
import Network

enum SyncActivity: Equatable {
    case localOnly, idle, waiting, transferring, offline, connectionError, conflict, storageFailure
}

@MainActor
final class SyncEngine: ObservableObject {
    @Published private(set) var status = "Local only"
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var pendingCount = 0
    @Published private(set) var blockedCount = 0
    @Published private(set) var configuredURL: String
    @Published private(set) var activity: SyncActivity = .localOnly
    @Published private(set) var successRevision: UInt64 = 0

    private let store: TaskStore
    private let defaults: UserDefaults
    private var transport: (any SyncTransport)?
    private var scheduled: Task<Void, Never>?
    private var periodic: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var observations: [NSObjectProtocol] = []
    private var needsAnotherPass = false
    private var running = false
    private var transferredChanges = false

    init(store: TaskStore, defaults: UserDefaults = .standard, transport: (any SyncTransport)? = nil) {
        self.store = store
        self.defaults = defaults
        self.transport = transport
        configuredURL = defaults.string(forKey: "serverURL") ?? ""
        updateCounts()
        activity = transport == nil ? .localOnly : (blockedCount > 0 ? .conflict : pendingCount > 0 ? .waiting : .idle)
    }

    func configure(url: String, token: String) throws {
        guard !isSyncing else { throw SyncFailure.message("Wait for the current sync before changing configuration.") }
        let resolvedToken = token.isEmpty ? try ServerTokenStore().load() ?? "" : token
        let client = try ServerClient(url: url, token: resolvedToken)
        try store.bindServer(client)
        if !token.isEmpty { try ServerTokenStore().save(token) }
        transport = client
        activity = .waiting
        configuredURL = client.endpoint
        defaults.set(client.endpoint, forKey: "serverURL")
        defaults.set(true, forKey: "syncEnabled")
        if !running { start() }
        requestSync()
    }

    func disable() {
        defaults.set(false, forKey: "syncEnabled")
        stop()
        transport = nil
        status = "Local only · changes retained"
        activity = .localOnly
        store.onLocalChange = { [weak self] in self?.updateCounts() }
    }

    func start() {
        guard !running else { return }
        running = true
        if transport == nil, defaults.bool(forKey: "syncEnabled") {
            do {
                transport = try ServerClient(url: configuredURL, token: try ServerTokenStore().load() ?? "")
                activity = .idle
            } catch { status = error.localizedDescription; activity = .connectionError }
        }
        store.onLocalChange = { [weak self] in
            guard let self else { return }
            self.updateCounts()
            if !self.isSyncing, self.transport != nil {
                self.activity = self.blockedCount > 0 ? .conflict : self.pendingCount > 0 ? .waiting : .idle
            }
            self.requestSync()
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.requestSync() }
        }
        monitor.start(queue: DispatchQueue(label: "org.nianbox.sync-path"))
        pathMonitor = monitor
        let center = NotificationCenter.default
        observations.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.requestSync() }
        })
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.requestSync() }
        })
        periodic = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.requestSync()
            }
        }
        requestSync()
    }

    func stop() {
        running = false
        scheduled?.cancel()
        periodic?.cancel()
        scheduled = nil
        periodic = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        observations.forEach { token in
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        observations.removeAll()
        store.onLocalChange = nil
    }

    func requestSync() {
        guard transport != nil else { return }
        if isSyncing { needsAnotherPass = true; return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await self?.syncOnce()
        }
    }

    /// Callable independently of the app UI and tested against both a faulting transport and real HTTP.
    func syncOnce() async {
        guard !isSyncing, let transport else { return }
        isSyncing = true
        needsAnotherPass = false
        transferredChanges = false
        status = "Syncing…"
        updateCounts()
        if pendingCount > 0 { showTransfer() }
        defer {
            isSyncing = false
            updateCounts()
            if needsAnotherPass && running { requestSync() }
        }
        do {
            try store.bindServer(transport)
            // Check database identity and import remote tombstones before any upload.
            try await pull(transport)
            var conflicts: [UUID: Int] = [:]
            for _ in 0..<100 {
                try Task.checkCancellation()
                guard let pending = try store.pendingMutations().first else { break }
                let request = try store.prepare(pending)
                do {
                    let task = try await transport.mutate(request)
                    try store.accept(task, for: pending)
                    transferredChanges = true
                    showTransfer()
                } catch let rejection as ServerRejection {
                    if rejection.error == "version_conflict", let current = rejection.current {
                        conflicts[pending.taskId, default: 0] += 1
                        guard conflicts[pending.taskId, default: 0] <= 3 else {
                            throw SyncFailure.message("Concurrent edits are busy; retrying later. Local changes retained.")
                        }
                        try store.rebase(pending, onto: current)
                    } else if rejection.error == "deleted", let current = rejection.current {
                        try store.rebase(pending, onto: current)
                    } else { throw rejection }
                }
            }
            try await pull(transport)
            guard updateCounts() else { throw SyncFailure.storage }
            if blockedCount > 0 {
                activity = .conflict
                status = "\(blockedCount) deleted-task edits saved for export"
            } else if pendingCount > 0 {
                activity = .waiting
                status = "\(pendingCount) changes waiting"
                needsAnotherPass = true
            } else {
                lastSuccess = Date()
                status = "Synced"
                activity = .idle
                if transferredChanges { successRevision &+= 1 }
            }
        } catch let rejection as ServerRejection {
            activity = .connectionError
            status = "Sync paused: \(rejection.error) · local changes retained"
        } catch is CancellationError {
            activity = pendingCount > 0 ? .waiting : .idle
            status = "Sync paused · local changes retained"
        } catch {
            activity = error is URLError ? .offline : .connectionError
            if let failure = error as? SyncFailure, case .storage = failure { activity = .storageFailure }
            status = "Sync unavailable · local changes retained"
            // Present actionable local errors without printing endpoints, tokens or task contents.
            if let failure = error as? SyncFailure { status = failure.localizedDescription }
        }
    }

    private func pull(_ transport: any SyncTransport) async throws {
        // Bound work per activation; the next scheduled pass continues from the committed cursor.
        for _ in 0..<100 {
            try Task.checkCancellation()
            let checkpoint = try store.checkpoint()
            let page = try await transport.changes(after: checkpoint.cursor, digest: checkpoint.cursorDigest)
            try store.applyPage(page)
            if !page.changes.isEmpty { transferredChanges = true; showTransfer() }
            if !page.hasMore { return }
        }
        throw SyncFailure.message("More history to import; the next sync will continue.")
    }

    private func showTransfer() {
        activity = blockedCount > 0 ? .conflict : .transferring
    }

    @discardableResult
    private func updateCounts() -> Bool {
        do {
            let pending = try store.pendingMutations(includeBlocked: true)
            pendingCount = pending.filter { $0.blockedReason == nil }.count
            blockedCount = pending.filter { $0.blockedReason != nil }.count
            return true
        } catch {
            status = "Cannot read sync queue; local store preserved"
            activity = .storageFailure
            return false
        }
    }
}
