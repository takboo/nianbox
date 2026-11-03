// Compile with the production model and PersistenceController sources.
// Creates synthetic offline data only in a fresh, isolated VirtualMac guest.
import Foundation
import SwiftData

@main
struct VMCopyFixture {
    @MainActor
    static func main() throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        process.arguments = ["-n", "hw.model"]
        process.standardOutput = pipe
        try process.run(); process.waitUntilExit()
        let model = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard model.hasPrefix("VirtualMac") else { fatalError("Refusing fixture creation on a physical Mac") }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/org.nianbox.NianBox/Data/Library/Application Support/NianBox/nianbox.store")
        guard !FileManager.default.fileExists(atPath: url.path) else {
            fatalError("Existing guest store preserved; fixture creation requires a fresh guest")
        }
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = container.mainContext
        let title = "COPY-notes 中文发布检查"
        let notes = "COPY-NOTES first line\n\n  Keep this indentation\nhttps://example.com/nianbox\n"
            + (1...35).map { "Line \($0): 完整备注必须可以复制，浮层支持滚动和局部选择。" }.joined(separator: "\n")
            + "\nEND-OF-FULL-NOTES"
        let task = TaskItem(title: title, priority: .high)
        task.notes = notes
        task.dueAt = ISO8601DateFormatter().date(from: "2026-11-04T10:00:00Z")
        let plain = TaskItem(title: "COPY-title-only")
        context.insert(task); context.insert(plain)
        try context.save()
        let fixture: [String: Any] = [
            "task": ["id": task.id.uuidString, "title": title, "notes": notes],
            "plainTask": ["id": plain.id.uuidString, "title": plain.title],
            "store": url.path, "guestModel": model.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        let data = try JSONSerialization.data(withJSONObject: fixture, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
