import Foundation
import SwiftData

/// A durable, immutable request once prepared. New edits always get a new queue entry.
@Model
final class PendingMutation {
    var mutationId: UUID = UUID()
    var taskId: UUID = UUID()
    var kind: String = "update"
    var patchData: Data = Data()
    var baseVersion: Int64 = 0
    var order: Int64 = 0
    var prepared: Bool = false
    var blockedReason: String? = nil

    init(taskId: UUID, kind: String, patchData: Data, baseVersion: Int64, order: Int64) {
        self.taskId = taskId
        self.kind = kind
        self.patchData = patchData
        self.baseVersion = baseVersion
        self.order = order
    }
}

@Model
final class SyncCheckpoint {
    var key: String = "nianbox"
    var cursor: Int64 = 0
    var nextOrder: Int64 = 0
    var serverId: String? = nil
    var endpoint: String? = nil
    init() {}
}
