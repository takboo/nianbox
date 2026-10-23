import Combine
import Foundation
import SwiftData

struct TaskSectionSnapshot: Identifiable {
    let status: TaskStatus
    let tasks: [TaskItem]

    var id: TaskStatus { status }
}

struct TaskScopeSnapshot {
    let sections: [TaskSectionSnapshot]
    let visibleCount: Int
    let activeCount: Int
}

/// How a drop onto a row resolves, so a drag indicator can promise exactly
/// what will happen: a precise insertion edge, or joining the target's
/// neighbourhood when priority or section rules decide the final slot.
enum TaskDropPlacement: Equatable {
    case above
    case below
    case join
}

private struct TaskReplicaSnapshot: Equatable {
    let id: UUID
    let title: String
    let statusRaw: String
    let priorityRaw: String
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
    let manualOrder: Int64?
    let fields: TaskFields
    let version: Int64
    let deletedAt: Date?

    init(_ task: TaskItem) {
        id = task.id
        title = task.title
        statusRaw = task.statusRaw
        priorityRaw = task.priorityRaw
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        completedAt = task.completedAt
        manualOrder = task.manualOrder
        fields = TaskFields(task)
        version = task.serverVersion
        deletedAt = task.deletedAt
    }
}

private enum TaskReplicaMutationError: LocalizedError {
    case missingReplica(UUID)

    var errorDescription: String? {
        switch self {
        case let .missingReplica(id):
            "The task replicas for \(id.uuidString) could not be loaded safely."
        }
    }
}

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var revision: UInt64 = 0

    let container: ModelContainer
    var context: ModelContext
    private let now: () -> Date
    let persist: (ModelContext) throws -> Void
    var savedFields: [UUID: TaskFields] = [:]
    var onLocalChange: (() -> Void)?
    private var snapshotCache: [TaskScope: (revision: UInt64, snapshot: TaskScopeSnapshot)] = [:]
    private static let manualOrderStride: Int64 = 1_024

    init(
        container: ModelContainer,
        now: @escaping () -> Date = Date.init,
        persist: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.container = container
        context = ModelContext(container)
        context.autosaveEnabled = false
        self.now = now
        self.persist = persist
        refresh()
    }

    @discardableResult
    func create(
        title: String,
        priority: TaskPriority = .none,
        status: TaskStatus = .todo
    ) -> TaskItem? {
        let normalizedTitle = Self.normalized(title)
        guard !normalizedTitle.isEmpty, normalizedTitle.count <= 2000 else { return nil }

        let timestamp = now()
        let manualOrder: Int64?
        do {
            manualOrder = try nextManualOrder(
                status: status,
                priority: priority,
                updatedAt: timestamp
            )
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
        let task = TaskItem(
            title: normalizedTitle,
            status: status,
            priority: priority,
            createdAt: timestamp,
            completedAt: status == .done ? timestamp : nil,
            manualOrder: manualOrder
        )
        context.insert(task)
        tasks.append(task)
        guard save() else { return nil }
        return task
    }

    @discardableResult
    func rename(_ task: TaskItem, to title: String) -> Bool {
        update(task, title: title)
    }

    @discardableResult
    func setPriority(_ priority: TaskPriority, for task: TaskItem) -> Bool {
        update(task, priority: priority)
    }

    @discardableResult
    func setStatus(_ status: TaskStatus, for task: TaskItem) -> Bool {
        update(task, status: status)
    }

    /// Applies a task edit as one SwiftData transaction so callers never see
    /// a partially persisted title, priority, or status change.
    @discardableResult
    func update(
        _ task: TaskItem,
        title: String? = nil,
        priority: TaskPriority? = nil,
        status: TaskStatus? = nil
    ) -> Bool {
        guard let task = tasks.first(where: { $0.id == task.id }) else { return false }
        let replicas: [TaskItem]
        do {
            replicas = try storedTasks(matching: task.id)
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
        let normalizedTitle = title.map(Self.normalized)
        if let normalizedTitle, normalizedTitle.isEmpty || normalizedTitle.count > 2000 { return false }

        let destinationTitle = normalizedTitle ?? task.title
        let destinationPriority = priority ?? task.priority
        let destinationStatus = status ?? task.status
        let titleChanged = destinationTitle != task.title
        let priorityChanged = destinationPriority != task.priority
        let statusChanged = destinationStatus != task.status
        let visibleSnapshot = TaskReplicaSnapshot(task)
        let replicasNeedRepair = replicas.contains {
            TaskReplicaSnapshot($0) != visibleSnapshot
        }
        guard titleChanged || priorityChanged || statusChanged || replicasNeedRepair else {
            return true
        }

        let timestamp = now()
        let destinationManualOrder: Int64?
        if priorityChanged || statusChanged {
            do {
                destinationManualOrder = try nextManualOrder(
                    status: destinationStatus,
                    priority: destinationPriority,
                    excluding: task.id,
                    updatedAt: timestamp
                )
            } catch {
                lastErrorMessage = error.localizedDescription
                return false
            }
        } else {
            destinationManualOrder = task.manualOrder
        }
        let destinationCompletedAt: Date?
        if statusChanged {
            destinationCompletedAt = destinationStatus == .done ? timestamp : nil
        } else {
            destinationCompletedAt = task.completedAt
        }

        for replica in replicas {
            replica.title = destinationTitle
            replica.priority = destinationPriority
            replica.status = destinationStatus
            replica.createdAt = task.createdAt
            replica.manualOrder = destinationManualOrder
            replica.completedAt = destinationCompletedAt
            replica.updatedAt = timestamp
        }
        return save()
    }

    @discardableResult
    func advanceToInProgress(_ task: TaskItem) -> Bool {
        guard let task = tasks.first(where: { $0.id == task.id }) else { return false }
        guard task.status == .todo else { return false }
        return setStatus(.inProgress, for: task)
    }

    @discardableResult
    func performDoubleClickAction(_ task: TaskItem) -> Bool {
        guard let task = tasks.first(where: { $0.id == task.id }) else { return false }
        guard let destination = task.status.doubleClickDestination else { return false }
        return setStatus(destination, for: task)
    }

    @discardableResult
    func markDone(_ task: TaskItem) -> Bool {
        guard let task = tasks.first(where: { $0.id == task.id }) else { return false }
        guard task.status != .done else { return true }
        return setStatus(.done, for: task)
    }

    @discardableResult
    func performPrimaryAction(_ task: TaskItem) -> Bool {
        guard let task = tasks.first(where: { $0.id == task.id }) else { return false }
        return setStatus(task.status.primaryActionDestination, for: task)
    }

    @discardableResult
    func delete(_ task: TaskItem) -> Bool {
        guard let task = tasks.first(where: { $0.id == task.id }) else { return false }
        let replicas: [TaskItem]
        do {
            replicas = try storedTasks(matching: task.id)
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
        let timestamp = now()
        for replica in replicas { replica.deletedAt = timestamp; replica.updatedAt = timestamp }
        tasks.removeAll { $0.id == task.id }
        return save()
    }

    func orderedTasks(for status: TaskStatus) -> [TaskItem] {
        tasks
            .filter { $0.status == status }
            .sorted { lhs, rhs in
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank > rhs.priority.sortRank
                }
                switch (lhs.manualOrder, rhs.manualOrder) {
                case let (.some(lhsOrder), .some(rhsOrder)) where lhsOrder != rhsOrder:
                    return lhsOrder > rhsOrder
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    break
                }
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// Memoized per revision: SwiftUI evaluates view bodies far more often
    /// than tasks change, so repeated calls between edits are O(1). Every
    /// mutation path goes through save()/reloadTasks(), which bump `revision`.
    func snapshot(for scope: TaskScope) -> TaskScopeSnapshot {
        if let cached = snapshotCache[scope], cached.revision == revision {
            return cached.snapshot
        }

        let sections = scope.statuses.compactMap { status -> TaskSectionSnapshot? in
            let statusTasks = orderedTasks(for: status)
            guard !statusTasks.isEmpty else { return nil }
            return TaskSectionSnapshot(status: status, tasks: statusTasks)
        }
        let activeStatuses = Set(scope.countedStatuses)
        let snapshot = TaskScopeSnapshot(
            sections: sections,
            visibleCount: sections.reduce(0) { $0 + $1.tasks.count },
            activeCount: sections.reduce(0) { count, section in
                count + (activeStatuses.contains(section.status) ? section.tasks.count : 0)
            }
        )
        snapshotCache[scope] = (revision, snapshot)
        return snapshot
    }

    @discardableResult
    func startAfterExternalDrag(taskID: UUID) -> Bool {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return false }
        switch task.status {
        case .todo, .backlog:
            return setStatus(.inProgress, for: task)
        case .inProgress:
            return true
        case .done:
            return false
        }
    }

    /// Drop onto another row: same section reorders, a different section
    /// adopts that section's status (placing the task near the target row
    /// when their priorities allow it).
    @discardableResult
    func drop(taskID: UUID, onto targetID: UUID) -> Bool {
        guard taskID != targetID,
              let task = tasks.first(where: { $0.id == taskID }),
              let target = tasks.first(where: { $0.id == targetID }) else {
            return false
        }

        if task.status == target.status {
            return place(taskID: taskID, near: targetID)
        }

        guard setStatus(target.status, for: task) else { return false }
        // The task keeps the manual order it had in its old section, which puts
        // it somewhere arbitrary in the new one. Place it against the row it was
        // dropped on, clamped to its own priority group like any other drop.
        place(taskID: taskID, near: targetID)
        return true
    }

    /// Where a drop on `targetID` would land, for drag indicators. Mirrors
    /// `drop(taskID:onto:)`: an exact insertion edge only when both rows sit in
    /// the same section and priority group, because otherwise the placement
    /// rules clamp the task to its own group and it cannot reach that edge.
    func dropPlacement(taskID: UUID, onto targetID: UUID) -> TaskDropPlacement? {
        guard taskID != targetID,
              let task = tasks.first(where: { $0.id == taskID }),
              let target = tasks.first(where: { $0.id == targetID }) else {
            return nil
        }
        guard task.status == target.status, task.priority == target.priority else { return .join }

        let group = orderedTasks(for: task.status).filter { $0.priority == task.priority }
        guard let sourceIndex = group.firstIndex(where: { $0.id == taskID }),
              let targetIndex = group.firstIndex(where: { $0.id == targetID }) else {
            return .join
        }
        return targetIndex < sourceIndex ? .above : .below
    }

    /// Drop onto a section's own area (header, gaps, empty placeholder).
    @discardableResult
    func drop(taskID: UUID, into status: TaskStatus) -> Bool {
        guard let task = tasks.first(where: { $0.id == taskID }),
              task.status != status else {
            return false
        }
        return setStatus(status, for: task)
    }

    /// Drag placement inside one section. `reorder` only accepts a target from
    /// the same priority group, but a drag can cross those invisible group
    /// boundaries. Priority outranks manual order, so instead of rejecting the
    /// drop — which leaves the dragged row snapping back to where it started —
    /// move the task as far as its own priority group allows.
    @discardableResult
    func place(taskID: UUID, near targetID: UUID) -> Bool {
        guard taskID != targetID,
              let task = tasks.first(where: { $0.id == taskID }),
              let target = tasks.first(where: { $0.id == targetID }),
              task.status == target.status else {
            return false
        }
        if task.priority == target.priority {
            return reorder(taskID: taskID, relativeTo: targetID)
        }

        let section = orderedTasks(for: task.status)
        guard let sourceIndex = section.firstIndex(where: { $0.id == taskID }),
              let targetIndex = section.firstIndex(where: { $0.id == targetID }) else {
            return false
        }
        let group = section.filter { $0.priority == task.priority }
        guard let anchor = targetIndex < sourceIndex ? group.first : group.last,
              anchor.id != taskID else {
            return false
        }
        return reorder(taskID: taskID, relativeTo: anchor.id)
    }

    @discardableResult
    func reorder(taskID: UUID, relativeTo targetID: UUID) -> Bool {
        guard taskID != targetID,
              let task = tasks.first(where: { $0.id == taskID }),
              let target = tasks.first(where: { $0.id == targetID }),
              task.status == target.status,
              task.priority == target.priority else {
            return false
        }

        var group = orderedTasks(for: task.status).filter { $0.priority == task.priority }
        guard let sourceIndex = group.firstIndex(where: { $0.id == taskID }),
              let targetIndex = group.firstIndex(where: { $0.id == targetID }) else {
            return false
        }

        let movedTask = group.remove(at: sourceIndex)
        group.insert(movedTask, at: min(targetIndex, group.count))

        guard let destinationIndex = group.firstIndex(where: { $0.id == taskID }) else {
            return false
        }
        let timestamp = now()
        do {
            if let sparseOrder = sparseManualOrder(at: destinationIndex, in: group) {
                for replica in try storedTasks(matching: task.id) {
                    replica.manualOrder = sparseOrder
                    replica.updatedAt = timestamp
                }
            } else {
                // Legacy stores can have missing or tightly packed values. Pay the
                // O(n) rebalance once, then normal reorders only dirty the moved row.
                try assignSpacedManualOrders(to: group, updatedAt: timestamp)
            }
        } catch {
            context.rollback()
            refresh()
            lastErrorMessage = error.localizedDescription
            return false
        }
        return save()
    }

    func refresh() {
        do {
            try reloadTasks()
            try captureSavedFields()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try queueChanges()
            try persist(context)
            try captureSavedFields()
            lastErrorMessage = nil
            revision &+= 1
            onLocalChange?()
            return true
        } catch {
            let saveError = error.localizedDescription
            context.rollback()
            do {
                try reloadTasks()
                try captureSavedFields()
                lastErrorMessage = saveError
            } catch {
                lastErrorMessage = "\(saveError) · Reload failed: \(error.localizedDescription)"
            }
            return false
        }
    }

    func reloadTasks() throws {
        let refreshedContext = ModelContext(container)
        refreshedContext.autosaveEnabled = false
        let fetched = try refreshedContext.fetch(FetchDescriptor<TaskItem>())
        let visible = visibleUniqueTasks(from: fetched).filter { $0.deletedAt == nil }
        guard !matchesPublishedTasks(visible) else { return }
        context = refreshedContext
        tasks = visible
        revision &+= 1
    }

    private func matchesPublishedTasks(_ fetched: [TaskItem]) -> Bool {
        guard fetched.count == tasks.count else { return false }
        let published = Dictionary(
            tasks.map { ($0.id, TaskReplicaSnapshot($0)) },
            uniquingKeysWith: { current, _ in current }
        )
        return fetched.allSatisfy { published[$0.id] == TaskReplicaSnapshot($0) }
    }

    /// Present one row per UUID without destructively repairing imported data.
    private func visibleUniqueTasks(from fetched: [TaskItem]) -> [TaskItem] {
        var newestByID: [UUID: TaskItem] = [:]

        for task in fetched {
            guard let existing = newestByID[task.id] else {
                newestByID[task.id] = task
                continue
            }

            if task.updatedAt > existing.updatedAt {
                newestByID[task.id] = task
            } else if task.updatedAt == existing.updatedAt,
                      Self.tieBreakKey(for: task) > Self.tieBreakKey(for: existing) {
                newestByID[task.id] = task
            }
        }

        return fetched.filter { task in
            newestByID[task.id] === task
        }
    }

    private func storedTasks(matching id: UUID) throws -> [TaskItem] {
        let groups = try storedTaskGroups(matching: [id])
        guard let replicas = groups[id], !replicas.isEmpty else {
            throw TaskReplicaMutationError.missingReplica(id)
        }
        return replicas
    }

    private func storedTaskGroups(
        matching ids: Set<UUID>
    ) throws -> [UUID: [TaskItem]] {
        let stored = try context.fetch(FetchDescriptor<TaskItem>())
        let groups = Dictionary(grouping: stored.filter { ids.contains($0.id) }, by: \.id)
        if let missingID = ids.first(where: { groups[$0]?.isEmpty != false }) {
            throw TaskReplicaMutationError.missingReplica(missingID)
        }
        return groups
    }

    private func nextManualOrder(
        status: TaskStatus,
        priority: TaskPriority,
        excluding excludedID: UUID? = nil,
        updatedAt: Date
    ) throws -> Int64? {
        let group = tasks.filter {
            $0.id != excludedID && $0.status == status && $0.priority == priority
        }
        guard let maximum = group.compactMap(\.manualOrder).max() else { return nil }
        guard maximum <= .max - Self.manualOrderStride else {
            let orderedGroup = orderedTasks(for: status).filter {
                $0.id != excludedID && $0.priority == priority
            }
            try assignSpacedManualOrders(to: orderedGroup, updatedAt: updatedAt)
            return Int64(orderedGroup.count + 1) * Self.manualOrderStride
        }
        return maximum + Self.manualOrderStride
    }

    private func sparseManualOrder(at index: Int, in orderedGroup: [TaskItem]) -> Int64? {
        guard orderedGroup.indices.contains(index) else { return nil }
        if orderedGroup.count == 1 { return Self.manualOrderStride }

        if index == 0 {
            guard let lower = orderedGroup[1].manualOrder,
                  lower <= .max - Self.manualOrderStride else { return nil }
            return lower + Self.manualOrderStride
        }

        if index == orderedGroup.count - 1 {
            guard let upper = orderedGroup[index - 1].manualOrder,
                  upper >= .min + Self.manualOrderStride else { return nil }
            return upper - Self.manualOrderStride
        }

        guard let upper = orderedGroup[index - 1].manualOrder,
              let lower = orderedGroup[index + 1].manualOrder,
              upper > lower else { return nil }
        let (distance, overflowed) = upper.subtractingReportingOverflow(lower)
        guard !overflowed, distance > 1 else { return nil }
        return lower + (distance / 2)
    }

    private func assignSpacedManualOrders(
        to orderedGroup: [TaskItem],
        updatedAt: Date
    ) throws {
        let groups = try storedTaskGroups(matching: Set(orderedGroup.map(\.id)))
        for (index, item) in orderedGroup.enumerated() {
            let order = Int64(orderedGroup.count - index) * Self.manualOrderStride
            for replica in groups[item.id] ?? [] {
                replica.manualOrder = order
                replica.updatedAt = updatedAt
            }
        }
    }

    private static func normalized(_ title: String) -> String {
        title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func tieBreakKey(for task: TaskItem) -> String {
        [
            task.title,
            task.statusRaw,
            task.priorityRaw,
            String(task.createdAt.timeIntervalSinceReferenceDate.bitPattern),
            task.completedAt.map { String($0.timeIntervalSinceReferenceDate.bitPattern) } ?? "",
            task.manualOrder.map(String.init) ?? "",
            String(reflecting: task.persistentModelID)
        ].joined(separator: "\u{1F}")
    }
}
