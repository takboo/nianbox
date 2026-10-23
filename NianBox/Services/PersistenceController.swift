import Foundation
import SwiftData

enum PersistenceController {
    static func makeContainer(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("NianBox", isDirectory: true)
            let url = storeURL ?? directory.appendingPathComponent("nianbox.store")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            configuration = ModelConfiguration("NianBox", url: url, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: TaskItem.self, PendingMutation.self, SyncCheckpoint.self, configurations: configuration)
    }
}
