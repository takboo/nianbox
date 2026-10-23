import AppKit
import Combine
import Foundation

enum MenuBarMark: Equatable {
    case none, waiting, syncing, synced, offline, connectionFailure, saveFailure, conflict
}

struct MenuBarIconFrame: Equatable {
    var paperY: CGFloat = 1.65
    var paperAngle: CGFloat = -0.13
    var bodyY: CGFloat = 0
    var mark: MenuBarMark = .none
    var rotation: CGFloat = 0
    static let idle = MenuBarIconFrame()
}

/// Observes committed capture results and typed sync activity, independently of menu tracking.
@MainActor
final class MenuBarLifecycle: ObservableObject {
    @Published private(set) var image = MenuBarIconRenderer.image(for: .idle)
    private(set) var frame = MenuBarIconFrame.idle
    private(set) var accessibilityLabel = "NianBox"

    private let clock: () -> TimeInterval
    private let schedulesFrames: Bool
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var accessibilityObserver: NSObjectProtocol?
    private let accessibilityCenter: NotificationCenter
    private var reducedMotion: Bool
    private var capturing = false
    private var captureFailed = false
    private var storageFailed = false
    private var activity: SyncActivity = .localOnly
    private var syncDescription = "Local only"
    private var transferStarted: TimeInterval = 0
    private var savedUntil: TimeInterval = 0
    private var syncedUntil: TimeInterval = 0
    private var poseFrom = MenuBarIconFrame.idle
    private var poseTarget = MenuBarIconFrame.idle
    private var poseStarted: TimeInterval = 0
    private var poseDuration: TimeInterval = 0
    private var settlingSave = false

    init(store: TaskStore, syncEngine: SyncEngine, uiState: PanelUIState,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         reducedMotion: Bool? = nil, schedulesFrames: Bool = true) {
        self.clock = clock
        self.schedulesFrames = schedulesFrames
        self.reducedMotion = reducedMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        accessibilityCenter = NSWorkspace.shared.notificationCenter
        uiState.$isComposerPresented.sink { [weak self] in self?.captureChanged($0) }.store(in: &subscriptions)
        uiState.$captureFeedback.sink { [weak self] in self?.captureResult($0) }.store(in: &subscriptions)
        store.$lastSaveFailed.sink { [weak self] failed in
            self?.storageFailed = failed
            self?.refresh()
        }.store(in: &subscriptions)
        syncEngine.$activity.sink { [weak self] in self?.syncChanged($0) }.store(in: &subscriptions)
        syncEngine.$status.sink { [weak self] status in
            self?.syncDescription = status
            self?.refresh()
        }.store(in: &subscriptions)
        syncEngine.$successRevision.dropFirst().sink { [weak self] _ in
            guard let self, !self.captureFailed, !self.storageFailed, self.activity == .idle else { return }
            self.syncedUntil = self.clock() + 1.45
            self.refresh()
        }.store(in: &subscriptions)
        if reducedMotion == nil {
            accessibilityObserver = accessibilityCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.setReducedMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
            }
        }
        refresh()
    }

    deinit {
        timer?.invalidate()
        if let accessibilityObserver { accessibilityCenter.removeObserver(accessibilityObserver) }
    }

    func setReducedMotion(_ enabled: Bool) {
        reducedMotion = enabled
        poseFrom = poseTarget
        poseDuration = 0
        refresh()
    }

    /// Also allows deterministic verification without running timers or desktop input.
    func refresh() {
        let now = clock()
        var next = currentPose(at: now)
        if captureFailed || storageFailed || activity == .storageFailure { next.mark = .saveFailure }
        else {
            switch activity {
            case .connectionError: next.mark = .connectionFailure
            case .conflict: next.mark = .conflict
            case .offline: next.mark = .offline
            case .waiting: next.mark = now >= savedUntil ? .waiting : .none
            case .transferring:
                next.mark = now - transferStarted >= 0.6 ? .syncing : .none
                next.rotation = reducedMotion ? -0.6 : CGFloat((now - transferStarted - 0.6) / 1.1 * .pi * 2)
            case .idle: next.mark = now < syncedUntil ? .synced : .none
            case .localOnly, .storageFailure: next.mark = .none
            }
        }
        let captureDescription: String
        if next.mark == .saveFailure { captureDescription = "Local save failed; unsaved input is retained" }
        else if now < savedUntil { captureDescription = "Saved to this Mac" }
        else if capturing { captureDescription = "Draft open; not yet saved" }
        else { captureDescription = "Ready to capture" }
        accessibilityLabel = "NianBox · \(captureDescription) · \(syncDescription)"
        if next != frame {
            frame = next
            image = MenuBarIconRenderer.image(for: next)
        } else {
            // Text can change during a silent poll without changing any pixels.
            objectWillChange.send()
        }
        scheduleNextFrame(at: now)
    }

    private func captureChanged(_ presented: Bool) {
        guard capturing != presented else { return }
        capturing = presented
        if presented { savedUntil = 0 }
        retarget(duration: presented ? 0.54 : 0.3)
    }

    private func captureResult(_ feedback: CaptureFeedback?) {
        switch feedback {
        case .saved:
            captureFailed = false
            savedUntil = clock() + 0.68
            retarget(duration: 0.46, saving: true)
        case .failed:
            captureFailed = true
            syncedUntil = 0
            refresh()
        case nil:
            captureFailed = false
            refresh()
        }
    }

    private func syncChanged(_ newActivity: SyncActivity) {
        if newActivity == .transferring, activity != .transferring { transferStarted = clock() }
        if newActivity != .idle { syncedUntil = 0 }
        activity = newActivity
        refresh()
    }

    private func retarget(duration: TimeInterval, saving: Bool = false) {
        let now = clock()
        var target = MenuBarIconFrame.idle
        if capturing, now >= savedUntil { target.paperY = 0.25; target.paperAngle = -0.045 }
        guard target != poseTarget || saving else { refresh(); return }
        poseFrom = currentPose(at: now)
        poseTarget = target
        poseStarted = now
        poseDuration = duration
        settlingSave = saving
        refresh()
    }

    private func currentPose(at now: TimeInterval) -> MenuBarIconFrame {
        guard !reducedMotion, poseDuration > 0, now < poseStarted + poseDuration else { return poseTarget }
        let p = max(0, min(1, (now - poseStarted) / poseDuration))
        let lift = Self.smooth(p)
        let rotation = settlingSave ? lift : Self.smooth((now - poseStarted - 0.045) / max(0.001, poseDuration - 0.045))
        let settle = settlingSave ? 16 * p * p * (1 - p) * (1 - p) : 0
        var result = MenuBarIconFrame.idle
        result.paperY = poseFrom.paperY + (poseTarget.paperY - poseFrom.paperY) * CGFloat(lift) + CGFloat(0.12 * settle)
        result.paperAngle = poseFrom.paperAngle + (poseTarget.paperAngle - poseFrom.paperAngle) * CGFloat(rotation)
        result.bodyY = poseFrom.bodyY * CGFloat(1 - lift) + CGFloat(0.22 * settle)
        return result
    }

    private static func smooth(_ value: Double) -> Double {
        let x = max(0, min(1, value))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    private func scheduleNextFrame(at now: TimeInterval) {
        timer?.invalidate()
        timer = nil
        guard schedulesFrames else { return }
        let moving = !reducedMotion && (now < poseStarted + poseDuration || frame.mark == .syncing)
        let deadlines = [savedUntil, syncedUntil, activity == .transferring ? transferStarted + 0.6 : 0].filter { $0 > now }
        guard moving || !deadlines.isEmpty else { return }
        let interval = moving ? 1.0 / 30 : max(0.016, deadlines.min()! - now)
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }
}
