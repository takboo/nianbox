import AppKit
import Foundation

enum TaskCopyFormat: CaseIterable, Hashable {
    case content, title, markdown

    var menuTitle: String {
        switch self {
        case .content: "Copy content"
        case .title: "Copy title only"
        case .markdown: "Copy as Markdown"
        }
    }

    func text(for task: TaskItem) -> String {
        let notes = task.notes.flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        }
        switch self {
        case .title:
            return task.title
        case .content:
            return [task.title, notes].compactMap { $0 }.joined(separator: "\n\n")
        case .markdown:
            let title = task.title.map { character -> String in
                "\\`*_{}[]<>#!|".contains(character) ? "\\\(character)" : String(character)
            }.joined().replacingOccurrences(of: "\n", with: "\n  ")
            var lines = ["- [\(task.status == .done ? "x" : " ")] \(title)"]
            if let notes {
                lines.append("")
                lines.append(notes.components(separatedBy: "\n").map { "  \($0)" }.joined(separator: "\n"))
            }
            lines.append("")
            lines.append("  Status: \(task.status.title)")
            if task.priority != .none { lines.append("  Priority: \(task.priority.title)") }
            if let dueAt = task.dueAt {
                lines.append("  Due: \(dueAt.formatted(date: .abbreviated, time: .shortened))")
            }
            return lines.joined(separator: "\n")
        }
    }
}

@MainActor
enum TaskClipboard {
    @discardableResult
    static func copy(_ task: TaskItem, format: TaskCopyFormat = .content,
                     to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(format.text(for: task), forType: .string)
    }
}
