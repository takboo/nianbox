import AppKit
import XCTest
@testable import NianBox

@MainActor
final class TaskClipboardTests: XCTestCase {
    func testContentIncludesFullNotesAndPreservesTheirFormatting() {
        let task = TaskItem(title: "Prepare release")
        task.notes = "First line\n\n  Indented line\nThird line\nhttps://example.com\n"
        XCTAssertEqual(TaskCopyFormat.content.text(for: task),
                       "Prepare release\n\nFirst line\n\n  Indented line\nThird line\nhttps://example.com\n")
        XCTAssertEqual(TaskCopyFormat.title.text(for: task), "Prepare release")
    }

    func testMissingOrWhitespaceNotesDoNotAddBlankContent() {
        let task = TaskItem(title: "Only title")
        for notes: String? in [nil, "", " \n\t"] {
            task.notes = notes
            XCTAssertEqual(TaskCopyFormat.content.text(for: task), "Only title")
        }
    }

    func testMarkdownIncludesTaskMetadataButNoInternalIdentity() {
        let task = TaskItem(title: "Ship [v1] *today*\nFollow up", status: .done, priority: .high)
        task.notes = "Check package\nCheck server"
        task.dueAt = Date(timeIntervalSince1970: 1_800_000_000)
        task.serverVersion = 4321
        let text = TaskCopyFormat.markdown.text(for: task)
        XCTAssertTrue(text.hasPrefix("- [x] Ship \\[v1\\] \\*today\\*\n  Follow up"))
        XCTAssertTrue(text.contains("\n\n  Check package\n  Check server\n\n  Status: Done"))
        XCTAssertTrue(text.contains("  Priority: High\n  Due: "))
        XCTAssertFalse(text.contains(task.id.uuidString))
        XCTAssertFalse(text.contains("4321"))
        XCTAssertEqual(TaskCopyFormat.content.text(for: task),
                       "Ship [v1] *today*\nFollow up\n\nCheck package\nCheck server")
    }

    func testMarkdownOmitsUnsetPriorityAndDueDate() {
        let task = TaskItem(title: "Idea", status: .backlog)
        XCTAssertEqual(TaskCopyFormat.markdown.text(for: task), "- [ ] Idea\n\n  Status: Backlog")
    }

    func testEveryCopyFormatReplacesPasteboardWithItsFullPayload() {
        // Never touch the host user's general clipboard in unit tests.
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let task = TaskItem(title: "Copy me")
        task.notes = String(repeating: "完整备注\n", count: 100)
        for format in TaskCopyFormat.allCases {
            XCTAssertTrue(TaskClipboard.copy(task, format: format, to: pasteboard))
            XCTAssertEqual(pasteboard.string(forType: .string), format.text(for: task))
        }
    }

    func testKeyboardCopyItemCarriesFullPlainText() async throws {
        let state = PanelUIState()
        let task = TaskItem(title: "Keyboard copy")
        task.notes = "Line one\nLine two\nLine three"
        let provider = try XCTUnwrap(state.copyItems(for: task).first)
        let value: String = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let value = value as? String { continuation.resume(returning: value) }
                else { continuation.resume(throwing: CocoaError(.fileReadCorruptFile)) }
            }
        }
        XCTAssertEqual(value, "Keyboard copy\n\nLine one\nLine two\nLine three")
    }

    func testSelectionFollowsVisibleOrderAndStopsAtBoundaries() {
        let state = PanelUIState()
        let ids = [UUID(), UUID(), UUID()]
        state.moveSelection(by: 1, visibleIDs: ids)
        XCTAssertEqual(state.selectedTaskID, ids[0])
        state.moveSelection(by: 1, visibleIDs: ids)
        XCTAssertEqual(state.selectedTaskID, ids[1])
        state.moveSelection(by: 1, visibleIDs: ids.reversed())
        XCTAssertEqual(state.selectedTaskID, ids[0])
        state.moveSelection(by: 1, visibleIDs: ids.reversed())
        XCTAssertEqual(state.selectedTaskID, ids[0])
        state.moveSelection(by: -1, visibleIDs: ids)
        XCTAssertEqual(state.selectedTaskID, ids[0])
    }

    func testFilteringOrDeletingSelectionClearsItInsteadOfCopyingAnInvisibleTask() {
        let state = PanelUIState()
        let ids = [UUID(), UUID()]
        state.selectTask(ids[0])
        state.reconcileSelection(visibleIDs: ids)
        XCTAssertEqual(state.selectedTaskID, ids[0])
        state.reconcileSelection(visibleIDs: [ids[1]])
        XCTAssertNil(state.selectedTaskID)
        state.moveSelection(by: -1, visibleIDs: ids)
        XCTAssertEqual(state.selectedTaskID, ids[1])
        state.moveSelection(by: 1, visibleIDs: [])
        XCTAssertNil(state.selectedTaskID)
    }

    func testNotesKeepPanelOpenAndReleaseLockWhenDismissedOrFiltered() {
        let state = PanelUIState()
        let id = UUID()
        state.presentNotes(for: id)
        XCTAssertTrue(state.isInteractionLocked)
        state.dismissNotes(for: UUID())
        XCTAssertTrue(state.isInteractionLocked)
        state.dismissNotes(for: id)
        XCTAssertFalse(state.isInteractionLocked)
        state.presentNotes(for: id)
        state.reconcileSelection(visibleIDs: [])
        XCTAssertNil(state.presentedNotesTaskID)
        XCTAssertFalse(state.isInteractionLocked)
    }

    func testEditingCaptureAndScopeChangeClearListSelectionAndNotes() {
        let state = PanelUIState()
        let task = TaskItem(title: "Existing")
        state.selectTask(task.id)
        state.presentNotes(for: task.id)
        state.beginEditing(task)
        XCTAssertNil(state.selectedTaskID)
        XCTAssertNil(state.presentedNotesTaskID)
        state.selectTask(task.id)
        state.beginAdding()
        XCTAssertNil(state.selectedTaskID)
        state.selectTask(task.id)
        state.presentNotes(for: task.id)
        state.selectScope(.backlog)
        XCTAssertNil(state.selectedTaskID)
        XCTAssertNil(state.presentedNotesTaskID)
    }

    func testRepeatedCopyDoesNotLetOldFeedbackClearTheLatestResult() throws {
        let state = PanelUIState()
        let task = TaskItem(title: "First")
        _ = state.copyItems(for: task)
        let first = try XCTUnwrap(state.copyFeedback)
        XCTAssertEqual(first.message, "Copied title")
        task.notes = "Full notes"
        _ = state.copyItems(for: task)
        let second = try XCTUnwrap(state.copyFeedback)
        XCTAssertEqual(second.message, "Copied title and notes")
        state.clearCopyFeedback(id: first.id)
        XCTAssertEqual(state.copyFeedback, second)
        state.clearCopyFeedback(id: second.id)
        XCTAssertNil(state.copyFeedback)
    }
}
