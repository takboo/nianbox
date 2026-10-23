// Compile with the production model, TaskStore, ServerClient and SyncEngine sources.
import Foundation
import SwiftData

@main
struct SyncSmoke {
    @MainActor
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass the ignored integration fixture path") }
        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
        let remote = fixture["task"] as! [String: Any]
        let id = UUID(uuidString: remote["id"] as! String)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nianbox-smoke-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("offline.store")
        let container = try PersistenceController.makeContainer(storeURL: storeURL)
        let store = TaskStore(container: container)
        let offline = store.create(title: "Mac offline capture integration")!
        let offlineId = offline.id
        // Reopen to prove offline capture and the durable queue survive process-store reattachment.
        let reopened = TaskStore(container: try PersistenceController.makeContainer(storeURL: storeURL))
        let queuedBefore = try reopened.pendingMutations().count
        precondition(queuedBefore == 1)
        let client = try ServerClient(url: fixture["url"] as! String, token: fixture["token"] as! String)
        let engine = SyncEngine(store: reopened, transport: client)
        await engine.syncOnce()
        guard let imported = reopened.tasks.first(where: { $0.id == id }) else {
            fatalError("Hermes task did not import: \(engine.status)")
        }
        precondition(imported.title == remote["title"] as! String)
        precondition(imported.notes == remote["notes"] as? String)
        precondition(imported.priority == .high && imported.dueAt != nil)
        guard try reopened.pendingMutations().isEmpty else { fatalError("Queue not drained: \(engine.status)") }
        precondition(reopened.markDone(imported))
        await engine.syncOnce()
        guard try reopened.pendingMutations().isEmpty else { fatalError("Queue not drained: \(engine.status)") }
        let page = try await client.changes(after: 0)
        precondition(page.changes.contains { $0.id == id && $0.status == .done && $0.completedAt != nil })
        precondition(page.changes.contains { $0.id == offlineId && $0.title == "Mac offline capture integration" })
        let final = TaskStore(container: try PersistenceController.makeContainer(storeURL: storeURL))
        precondition(final.tasks.contains { $0.id == id && $0.status == .done })
        print("PASS: Hermes task imported into disk-backed SwiftData; reopened offline capture uploaded; Mac completion persisted on server and survived local reopen")
    }
}
