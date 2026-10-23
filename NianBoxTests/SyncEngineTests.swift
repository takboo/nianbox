import XCTest
import SwiftData
@testable import NianBox

@MainActor
final class MemoryServer: SyncTransport {
    var endpoint = "https://test.nianbox.invalid"
    var serverId = "server-a"
    var history: [WireTask] = []
    var tasks: [UUID: WireTask] = [:]
    var receipts: [UUID: (MutationRequest, WireTask)] = [:]
    var failReads = false
    var loseNextReply = false
    var onWrite: (() -> Void)?
    var calls: [MutationRequest] = []

    func changes(after: Int64) async throws -> ChangePage {
        if failReads { throw URLError(.notConnectedToInternet) }
        return ChangePage(changes: history.filter { $0.version > after }, cursor: Int64(history.count), hasMore: false, serverId: serverId)
    }
    func mutate(_ request: MutationRequest) async throws -> WireTask {
        calls.append(request)
        if let (original, reply) = receipts[request.mutationId] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            XCTAssertEqual(try encoder.encode(original), try encoder.encode(request))
            return reply
        }
        let existing = tasks[request.taskId]
        if let existing, existing.deletedAt != nil, request.kind != "delete" {
            throw ServerRejection(error: "deleted", current: existing)
        }
        if let existing, request.kind != "delete", request.baseVersion != existing.version {
            throw ServerRejection(error: "version_conflict", current: existing)
        }
        var fields: [String: PatchValue] = existing.map { remote in
            ["title": .string(remote.title), "notes": remote.notes.map(PatchValue.string) ?? .null,
             "status": .string(remote.status.rawValue), "priority": .string(remote.priority.rawValue),
             "dueAt": remote.dueAt.map { .string(WireDate.string($0)) } ?? .null]
        } ?? ["title": .string(""), "notes": .null, "status": .string("todo"), "priority": .string("none"), "dueAt": .null]
        fields.merge(request.patch) { _, new in new }
        func value(_ key: String) -> String? { if case let .string(value) = fields[key] { return value }; return nil }
        let now = Date()
        let status = TaskStatus(rawValue: value("status")!)!
        let task = WireTask(id: request.taskId, title: value("title")!, notes: value("notes"), status: status,
            priority: TaskPriority(rawValue: value("priority")!)!, dueAt: try value("dueAt").map(WireDate.parse),
            createdAt: existing?.createdAt ?? now, updatedAt: now, completedAt: status == .done ? now : nil,
            deletedAt: request.kind == "delete" ? now : nil, version: Int64(history.count + 1))
        tasks[task.id] = task
        history.append(task)
        receipts[request.mutationId] = (request, task)
        onWrite?()
        if loseNextReply { loseNextReply = false; throw URLError(.networkConnectionLost) }
        return task
    }
    func external(id: UUID = UUID(), patch: [String: PatchValue] = ["title": .string("Remote")], kind: String = "create") async throws -> WireTask {
        try await mutate(MutationRequest(mutationId: UUID(), taskId: id, kind: kind, baseVersion: tasks[id]?.version ?? 0, patch: patch))
    }
}

@MainActor
final class SyncEngineTests: XCTestCase {
    func testOfflineCaptureThenTwoWaySyncAndCompletionHistory() async throws {
        let store = try makeTestStore()
        let local = try XCTUnwrap(store.create(title: "Offline"))
        let server = MemoryServer()
        server.failReads = true
        let engine = SyncEngine(store: store, transport: server)
        await engine.syncOnce()
        XCTAssertEqual(try store.pendingMutations().count, 1)
        server.failReads = false
        let remote = try await server.external(patch: ["title": .string("From Hermes"), "notes": .string("Keep detail"), "dueAt": .string("2026-10-24T09:00:00+08:00")])
        await engine.syncOnce()
        XCTAssertEqual(Set(store.tasks.map(\.title)), ["Offline", "From Hermes"])
        XCTAssertEqual(store.tasks.first { $0.id == remote.id }?.notes, "Keep detail")
        XCTAssertNotNil(store.tasks.first { $0.id == remote.id }?.dueAt)
        XCTAssertNotNil(server.tasks[local.id])
        XCTAssertEqual(try store.pendingMutations().count, 0)
        XCTAssertTrue(store.markDone(store.tasks.first { $0.id == local.id }!))
        await engine.syncOnce()
        store.refresh()
        XCTAssertEqual(store.tasks.first { $0.id == local.id }?.status, .done)
        XCTAssertNotNil(server.tasks[local.id]?.completedAt)
    }

    func testLostReplyReusesPersistedRequestExactly() async throws {
        let store = try makeTestStore()
        _ = store.create(title: "Once")
        let server = MemoryServer()
        server.loseNextReply = true
        await SyncEngine(store: store, transport: server).syncOnce()
        let pending = try XCTUnwrap(store.pendingMutations().first)
        XCTAssertTrue(pending.prepared)
        let firstId = pending.mutationId
        await SyncEngine(store: store, transport: server).syncOnce()
        XCTAssertEqual(server.calls.map(\.mutationId), [firstId, firstId])
        XCTAssertEqual(server.history.count, 1)
        XCTAssertEqual(try store.pendingMutations().count, 0)
    }

    func testNewEditWhileWriteInFlightRemainsQueued() async throws {
        let store = try makeTestStore()
        let local = try XCTUnwrap(store.create(title: "First"))
        let server = MemoryServer()
        server.onWrite = {
            server.onWrite = nil
            XCTAssertTrue(store.rename(local, to: "Second"))
        }
        await SyncEngine(store: store, transport: server).syncOnce()
        XCTAssertEqual(server.tasks[local.id]?.title, "Second")
        XCTAssertEqual(store.tasks.first?.title, "Second")
        XCTAssertEqual(server.history.count, 2)
        XCTAssertEqual(try store.pendingMutations().count, 0)
    }

    func testConflictRebasesOnlyLocalFieldsAndKeepsRemoteFields() async throws {
        let store = try makeTestStore()
        let server = MemoryServer()
        let remote = try await server.external()
        let engine = SyncEngine(store: store, transport: server)
        await engine.syncOnce()
        let local = try XCTUnwrap(store.tasks.first)
        XCTAssertTrue(store.rename(local, to: "My title"))
        // Prepare before a remote edit to reproduce an actual in-flight CAS conflict.
        _ = try store.prepare(try XCTUnwrap(store.pendingMutations().first))
        _ = try await server.external(id: remote.id, patch: ["notes": .string("Remote notes"), "priority": .string("high")], kind: "update")
        await engine.syncOnce()
        XCTAssertEqual(server.tasks[local.id]?.title, "My title")
        XCTAssertEqual(server.tasks[local.id]?.notes, "Remote notes")
        XCTAssertEqual(store.tasks.first?.priority, .high)
        XCTAssertEqual(try store.pendingMutations().count, 0)
    }

    func testRemoteDeleteWinsAndRetainsUnsentEditForExport() async throws {
        let store = try makeTestStore()
        let server = MemoryServer()
        let remote = try await server.external()
        let engine = SyncEngine(store: store, transport: server)
        await engine.syncOnce()
        XCTAssertTrue(store.rename(try XCTUnwrap(store.tasks.first), to: "Unique offline detail"))
        _ = try await server.external(id: remote.id, patch: [:], kind: "delete")
        await engine.syncOnce()
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertEqual(try store.pendingMutations().count, 0)
        XCTAssertEqual(try store.pendingMutations(includeBlocked: true).count, 1)
        XCTAssertTrue(String(data: try store.exportLocalData(), encoding: .utf8)!.contains("Unique offline detail"))
        XCTAssertEqual(engine.blockedCount, 1)
    }

    func testOfflineCreateAndDeleteNeverReappears() async throws {
        let store = try makeTestStore()
        let task = try XCTUnwrap(store.create(title: "Discarded"))
        XCTAssertTrue(store.delete(task))
        let server = MemoryServer()
        await SyncEngine(store: store, transport: server).syncOnce()
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertNotNil(server.tasks[task.id]?.deletedAt)
        XCTAssertEqual(try store.pendingMutations().count, 0)
    }

    func testQueueAndPreparedBodySurviveReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        var request: MutationRequest!
        do {
            let store = TaskStore(container: try PersistenceController.makeContainer(storeURL: url))
            _ = store.create(title: "Durable")
            request = try store.prepare(try XCTUnwrap(store.pendingMutations().first))
        }
        let reopened = TaskStore(container: try PersistenceController.makeContainer(storeURL: url))
        let pending = try XCTUnwrap(reopened.pendingMutations().first)
        let replay = try reopened.prepare(pending)
        XCTAssertEqual(replay.mutationId, request.mutationId)
        XCTAssertEqual(replay.patch, request.patch)
        XCTAssertTrue(pending.prepared)
        XCTAssertEqual(reopened.tasks.first?.title, "Durable")
    }

    func testFailedLocalTransactionCannotLeaveOrphanMutation() throws {
        let gate = PersistenceGate()
        let store = try makeTestStore(persist: gate.save)
        gate.shouldFail = true
        XCTAssertNil(store.create(title: "Failed"))
        XCTAssertEqual(try store.pendingMutations().count, 0)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testPageAndCursorCommitTogetherAndReplayAfterFailure() async throws {
        let gate = PersistenceGate()
        let store = try makeTestStore(persist: gate.save)
        let server = MemoryServer()
        _ = try await server.external()
        let page = try await server.changes(after: 0)
        gate.shouldFail = true
        XCTAssertThrowsError(try store.applyPage(page))
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertEqual(try store.checkpoint().cursor, 0)
        gate.shouldFail = false
        try store.applyPage(page)
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(try store.checkpoint().cursor, 1)
        XCTAssertEqual(try store.pendingMutations().count, 0)
    }

    func testServerIdentityAndEndpointChangeStopsBeforeUpload() async throws {
        let store = try makeTestStore()
        let server = MemoryServer()
        let engine = SyncEngine(store: store, transport: server)
        await engine.syncOnce()
        _ = store.create(title: "Protected")
        server.serverId = "different"
        await engine.syncOnce()
        XCTAssertTrue(server.calls.isEmpty)
        XCTAssertEqual(try store.pendingMutations().count, 1)
        server.endpoint = "https://other.invalid"
        await engine.syncOnce()
        XCTAssertTrue(server.calls.isEmpty)
    }

    func testWriteReceiptDoesNotAdvancePullCursorPastOtherTasks() async throws {
        let store = try makeTestStore()
        let server = MemoryServer()
        _ = store.create(title: "Local")
        server.onWrite = {
            server.onWrite = nil
            let other = WireTask(id: UUID(), title: "Concurrent remote", notes: nil, status: .todo, priority: .none,
                dueAt: nil, createdAt: Date(), updatedAt: Date(), completedAt: nil, deletedAt: nil, version: Int64(server.history.count + 1))
            server.history.append(other)
            server.tasks[other.id] = other
        }
        await SyncEngine(store: store, transport: server).syncOnce()
        XCTAssertEqual(Set(store.tasks.map(\.title)), ["Local", "Concurrent remote"])
    }

    func testClientRejectsUnsafeURLs() {
        for url in ["http://example.com", "https://user:secret@example.com", "https://example.com/?token=x", "https://example.com/mcp/", "file:///tmp/x"] {
            XCTAssertThrowsError(try ServerClient.validatedURL(url))
        }
        XCTAssertNoThrow(try ServerClient.validatedURL("http://127.0.0.1:8088"))
        XCTAssertNoThrow(try ServerClient.validatedURL("https://nianbox.example.ts.net"))
    }
}
