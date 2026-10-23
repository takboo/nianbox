import Foundation
import SwiftData

@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String? = nil
    var dueAt: Date? = nil
    var deletedAt: Date? = nil
    var serverVersion: Int64 = 0
    // Canonical fields before pending local patches; optional for existing stores.
    var serverSnapshot: Data? = nil
    var statusRaw: String = TaskStatus.todo.rawValue
    var priorityRaw: String = TaskPriority.none.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var completedAt: Date? = nil
    var manualOrder: Int64? = nil

    init(
        id: UUID = UUID(),
        title: String,
        status: TaskStatus = .todo,
        priority: TaskPriority = .none,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        completedAt: Date? = nil,
        manualOrder: Int64? = nil
    ) {
        self.id = id
        self.title = title
        statusRaw = status.rawValue
        priorityRaw = priority.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.completedAt = completedAt
        self.manualOrder = manualOrder
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }
}
