import Foundation
import SwiftData

@MainActor
extension TaskStore {
    func checkpoint() throws -> SyncCheckpoint {
        if let checkpoint = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first { return checkpoint }
        let checkpoint = SyncCheckpoint()
        context.insert(checkpoint)
        return checkpoint
    }

    func pendingMutations(includeBlocked: Bool = false) throws -> [PendingMutation] {
        try context.fetch(FetchDescriptor<PendingMutation>(sortBy: [SortDescriptor(\.order)]))
            .filter { includeBlocked || $0.blockedReason == nil }
    }

    func queueChanges() throws {
        let stored = try context.fetch(FetchDescriptor<TaskItem>())
        var seen = Set<UUID>()
        for task in stored.sorted(by: { $0.updatedAt > $1.updatedAt }) where seen.insert(task.id).inserted {
            let fields = TaskFields(task)
            let old = savedFields[task.id]
            if fields == old { continue }
            let kind: String
            let patch: [String: PatchValue]
            if fields.deleted {
                if old?.deleted == true { continue }
                kind = "delete"
                patch = [:]
            } else if let old {
                patch = fields.changes(from: old)
                if patch.isEmpty { continue }
                kind = "update"
            } else {
                kind = "create"
                patch = fields.patch
            }
            let state = try checkpoint()
            state.nextOrder += 1
            context.insert(PendingMutation(taskId: task.id, kind: kind,
                patchData: try JSONEncoder().encode(patch), baseVersion: task.serverVersion, order: state.nextOrder))
        }
    }

    func captureSavedFields() throws {
        let stored = try context.fetch(FetchDescriptor<TaskItem>())
        savedFields = Dictionary(stored.sorted { $0.updatedAt > $1.updatedAt }.map { ($0.id, TaskFields($0)) },
                                 uniquingKeysWith: { first, _ in first })
    }

    func bindServer(_ transport: any SyncTransport) throws {
        let state = try checkpoint()
        if let endpoint = state.endpoint, endpoint != transport.endpoint {
            throw SyncFailure.message("This cache belongs to another server URL. Export data before migrating servers.")
        }
        state.endpoint = transport.endpoint
        // Phase 1/local-only stores can contain tasks predating the outbox schema.
        let queued = Set(try pendingMutations(includeBlocked: true).map(\.taskId))
        for task in try context.fetch(FetchDescriptor<TaskItem>()) where task.serverVersion == 0 && !queued.contains(task.id) {
            savedFields.removeValue(forKey: task.id)
        }
        try queueChanges()
        try saveSyncTransaction()
    }

    func prepare(_ pending: PendingMutation) throws -> MutationRequest {
        if !pending.prepared {
            let id = pending.taskId
            let task = try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id == id }
            pending.baseVersion = pending.kind == "create" ? 0 : (task?.serverVersion ?? pending.baseVersion)
            pending.prepared = true
            try saveSyncTransaction()
        }
        return MutationRequest(mutationId: pending.mutationId, taskId: pending.taskId, kind: pending.kind,
            baseVersion: pending.baseVersion, patch: try JSONDecoder().decode([String: PatchValue].self, from: pending.patchData))
    }

    func accept(_ task: WireTask, for pending: PendingMutation) throws {
        do {
            let local = try context.fetch(FetchDescriptor<TaskItem>()).filter { $0.id == task.id }
                .max { $0.serverVersion < $1.serverVersion }
            let canonical: WireTask
            if let local, local.serverVersion > task.version {
                guard let data = local.serverSnapshot else {
                    throw SyncFailure.message("A newer server snapshot is needed before acknowledging this retry. Local changes retained; export and reconcile.")
                }
                canonical = try JSONDecoder().decode(WireTask.self, from: data)
                guard canonical.version == local.serverVersion else {
                    throw SyncFailure.message("Invalid cached server snapshot. Local changes retained.")
                }
            } else { canonical = task }
            context.delete(pending)
            // A replay receipt can predate a record already imported by the leading pull.
            // Rebuild from that canonical record after removing only this queue entry.
            try applyRemote(canonical)
            try saveSyncTransaction()
        } catch {
            context.rollback()
            refresh()
            throw error
        }
    }

    func rebase(_ pending: PendingMutation, onto task: WireTask) throws {
        // A rejected CAS has no receipt. Give the deliberate new request a fresh identity.
        pending.mutationId = UUID()
        pending.baseVersion = task.version
        pending.prepared = false
        if pending.kind == "create" { pending.kind = "update" }
        try applyRemote(task)
        try saveSyncTransaction()
    }

    func applyPage(_ page: ChangePage) throws {
        let state = try checkpoint()
        if let serverId = state.serverId, serverId != page.serverId {
            throw SyncFailure.message("Server database identity changed. Local data is preserved; reconcile before resuming.")
        }
        guard page.cursor >= state.cursor, !page.hasMore || page.cursor > state.cursor else {
            throw SyncFailure.message("Invalid server cursor")
        }
        state.serverId = page.serverId
        for task in page.changes { try applyRemote(task) }
        state.cursor = page.cursor
        state.cursorDigest = page.cursorDigest
        try saveSyncTransaction()
    }

    private func applyRemote(_ remote: WireTask) throws {
        let replicas = try context.fetch(FetchDescriptor<TaskItem>()).filter { $0.id == remote.id }
        let tasks: [TaskItem]
        if replicas.isEmpty {
            let task = TaskItem(id: remote.id, title: remote.title)
            context.insert(task)
            tasks = [task]
        } else { tasks = replicas }
        let pending = try pendingMutations().filter { $0.taskId == remote.id }
        for task in tasks {
            guard remote.version >= task.serverVersion else { continue }
            task.serverSnapshot = try JSONEncoder().encode(remote)
            task.title = remote.title
            task.notes = remote.notes
            task.status = remote.status
            task.priority = remote.priority
            task.dueAt = remote.dueAt
            task.createdAt = remote.createdAt
            task.updatedAt = remote.updatedAt
            task.completedAt = remote.completedAt
            task.deletedAt = remote.deletedAt
            task.serverVersion = remote.version
            if remote.deletedAt != nil {
                // Keep the original local edit payload for export; never resurrect the UUID.
                for operation in pending where operation.kind != "delete" { operation.blockedReason = "deleted_on_server" }
            } else {
                for operation in pending {
                    if operation.kind == "delete" { task.deletedAt = Date(); continue }
                    let patch = try JSONDecoder().decode([String: PatchValue].self, from: operation.patchData)
                    try overlay(patch, on: task)
                }
            }
        }
    }

    private func overlay(_ patch: [String: PatchValue], on task: TaskItem) throws {
        for (field, value) in patch {
            let string: String? = if case let .string(string) = value { string } else { nil }
            switch field {
            case "title": if let string { task.title = string }
            case "notes": task.notes = string
            case "status":
                if let string, let status = TaskStatus(rawValue: string) {
                    task.status = status
                    task.completedAt = status == .done ? (task.completedAt ?? Date()) : nil
                }
            case "priority": if let string, let priority = TaskPriority(rawValue: string) { task.priority = priority }
            case "dueAt": task.dueAt = try string.map(WireDate.parse)
            default: break
            }
        }
    }

    /// Imported data, receipts and cursors share the same transaction. This path never queues writes.
    func saveSyncTransaction() throws {
        do {
            try persist(context)
            try reloadTasks()
            try captureSavedFields()
        } catch {
            context.rollback()
            refresh()
            throw SyncFailure.storage
        }
    }

    func exportLocalData() throws -> Data {
        let tasks = try context.fetch(FetchDescriptor<TaskItem>()).map { task -> [String: Any] in
            var json: [String: Any] = ["id": task.id.uuidString, "title": task.title,
                "status": task.statusRaw, "priority": task.priorityRaw, "version": task.serverVersion,
                "createdAt": WireDate.string(task.createdAt), "updatedAt": WireDate.string(task.updatedAt)]
            json["notes"] = task.notes ?? NSNull() as Any
            json["dueAt"] = task.dueAt.map(WireDate.string) ?? NSNull() as Any
            json["completedAt"] = task.completedAt.map(WireDate.string) ?? NSNull() as Any
            json["deletedAt"] = task.deletedAt.map(WireDate.string) ?? NSNull() as Any
            return json
        }
        let outbox = try pendingMutations(includeBlocked: true).map { pending -> [String: Any] in
            ["mutationId": pending.mutationId.uuidString, "taskId": pending.taskId.uuidString,
             "kind": pending.kind, "baseVersion": pending.baseVersion, "prepared": pending.prepared,
             "blockedReason": pending.blockedReason ?? NSNull() as Any,
             "patch": try JSONSerialization.jsonObject(with: pending.patchData)]
        }
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "tasks": tasks, "outbox": outbox], options: [.prettyPrinted, .sortedKeys])
    }
}
