import Foundation

/// Patch fields are strings or explicit null. Omitted fields keep their server value.
enum PatchValue: Codable, Equatable {
    case string(String)
    case null
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        self = value.decodeNil() ? .null : .string(try value.decode(String.self))
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case let .string(string): try value.encode(string)
        }
    }
}

enum WireDate {
    static func string(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: true).timeSeparator(.colon).timeZone(separator: .colon))
    }
    static func parse(_ string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: string) else { throw SyncFailure.message("Invalid server date") }
        return date
    }
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { try parse($0.singleValueContainer().decode(String.self)) }
        return decoder
    }
}

struct TaskFields: Equatable {
    let patch: [String: PatchValue]
    let deleted: Bool
    init(_ item: TaskItem) {
        patch = ["title": .string(item.title), "notes": item.notes.map(PatchValue.string) ?? .null,
                 "status": .string(item.statusRaw), "priority": .string(item.priorityRaw),
                 "dueAt": item.dueAt.map { .string(WireDate.string($0)) } ?? .null]
        deleted = item.deletedAt != nil
    }
    func changes(from old: TaskFields) -> [String: PatchValue] {
        patch.filter { old.patch[$0.key] != $0.value }
    }
}

struct WireTask: Codable {
    let id: UUID
    let title: String
    let notes: String?
    let status: TaskStatus
    let priority: TaskPriority
    let dueAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
    let deletedAt: Date?
    let version: Int64
}
struct ChangePage: Decodable {
    let changes: [WireTask]
    let cursor: Int64
    let hasMore: Bool
    let serverId: String
}
struct MutationRequest: Codable {
    let mutationId: UUID
    let taskId: UUID
    let kind: String
    let baseVersion: Int64
    let patch: [String: PatchValue]
}
struct MutationReply: Decodable { let task: WireTask }
struct ServerRejection: Decodable, Error {
    let error: String
    let current: WireTask?
}
enum SyncFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case let .message(message): return message }
    }
}

@MainActor
protocol SyncTransport {
    var endpoint: String { get }
    func changes(after: Int64) async throws -> ChangePage
    func mutate(_ request: MutationRequest) async throws -> WireTask
}
