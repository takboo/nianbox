import Combine
import AppKit
import Foundation

struct CaptureDraft {
    var title = ""
    var priority: TaskPriority = .none
}

enum CaptureFeedback: Equatable {
    case saved(UUID)
    case failed(UUID)
}

struct TaskCopyFeedback: Equatable {
    let id = UUID()
    let taskID: UUID
    let message: String
    let succeeded: Bool
}

@MainActor
final class PanelUIState: ObservableObject {
    @Published var isComposerPresented = false
    @Published var editingTaskID: UUID?
    @Published var isMenuTracking = false
    @Published private(set) var selectedScope: TaskScope = .tasks
    @Published private(set) var draggedTaskID: UUID?
    @Published private var drafts: [TaskScope: CaptureDraft] = [:]
    @Published private(set) var captureFeedback: CaptureFeedback?
    @Published private(set) var captureError: String?
    @Published private(set) var selectedTaskID: UUID?
    @Published private(set) var copyFeedback: TaskCopyFeedback?
    @Published private(set) var presentedNotesTaskID: UUID?
    private var copyFeedbackTask: Task<Void, Never>?

    func presentNotes(for id: UUID) { presentedNotesTaskID = id }
    func dismissNotes(for id: UUID) {
        if presentedNotesTaskID == id { presentedNotesTaskID = nil }
    }

    func selectTask(_ id: UUID) { selectedTaskID = id }

    func reconcileSelection(visibleIDs: [UUID]) {
        if let selectedTaskID, !visibleIDs.contains(selectedTaskID) { self.selectedTaskID = nil }
        if let presentedNotesTaskID, !visibleIDs.contains(presentedNotesTaskID) { self.presentedNotesTaskID = nil }
    }

    func moveSelection(by offset: Int, visibleIDs: [UUID]) {
        guard !visibleIDs.isEmpty else { selectedTaskID = nil; return }
        let index = selectedTaskID.flatMap { visibleIDs.firstIndex(of: $0) }
        let next = index.map { min(max($0 + offset, 0), visibleIDs.count - 1) }
            ?? (offset < 0 ? visibleIDs.count - 1 : 0)
        selectedTaskID = visibleIDs[next]
    }

    func copy(_ task: TaskItem, format: TaskCopyFormat = .content) {
        reportCopy(task, format: format, succeeded: TaskClipboard.copy(task, format: format))
    }

    // SwiftUI's standard Copy command supplies these items to the pasteboard.
    // Keeping the command on the focused list leaves text editors in control
    // of their own selected text.
    func copyItems(for task: TaskItem) -> [NSItemProvider] {
        reportCopy(task, format: .content, succeeded: true)
        return [NSItemProvider(object: TaskCopyFormat.content.text(for: task) as NSString)]
    }

    private func reportCopy(_ task: TaskItem, format: TaskCopyFormat, succeeded: Bool) {
        let includesNotes = !(task.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let message: String
        switch format {
        case .content: message = includesNotes ? "Copied title and notes" : "Copied title"
        case .title: message = "Copied title"
        case .markdown: message = "Copied as Markdown"
        }
        let feedback = TaskCopyFeedback(taskID: task.id,
                                        message: succeeded ? message : "Could not copy. Try again.",
                                        succeeded: succeeded)
        copyFeedback = feedback
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.clearCopyFeedback(id: feedback.id)
        }
    }

    func clearCopyFeedback(id: UUID) {
        if copyFeedback?.id == id {
            copyFeedback = nil
            copyFeedbackTask?.cancel()
            copyFeedbackTask = nil
        }
    }

    var draftTitle: String {
        get { drafts[selectedScope]?.title ?? "" }
        set { var draft = drafts[selectedScope] ?? CaptureDraft(); draft.title = newValue; drafts[selectedScope] = draft }
    }

    var draftPriority: TaskPriority {
        get { drafts[selectedScope]?.priority ?? .none }
        set { var draft = drafts[selectedScope] ?? CaptureDraft(); draft.priority = newValue; drafts[selectedScope] = draft }
    }

    var isDraggingTask: Bool { draggedTaskID != nil }

    var isInteractionLocked: Bool {
        isComposerPresented || editingTaskID != nil || isMenuTracking || presentedNotesTaskID != nil
    }

    func beginAdding() {
        selectedTaskID = nil
        presentedNotesTaskID = nil
        editingTaskID = nil
        captureFeedback = nil
        captureError = nil
        isComposerPresented = true
    }

    func selectScope(_ scope: TaskScope) {
        guard selectedScope != scope else { return }
        editingTaskID = nil
        draggedTaskID = nil
        selectedScope = scope
        selectedTaskID = nil
        copyFeedback = nil
        presentedNotesTaskID = nil
        captureFeedback = nil
        captureError = nil
    }

    func endAdding() {
        isComposerPresented = false
    }

    func cancelAdding() {
        drafts.removeValue(forKey: selectedScope)
        captureFeedback = nil
        captureError = nil
        endAdding()
    }

    @discardableResult
    func saveCapture(in store: TaskStore) -> Bool {
        guard !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draftTitle.count <= 2000 else {
            captureError = "Enter a title of up to 2000 characters."
            return false
        }
        guard store.create(title: draftTitle, priority: draftPriority, status: selectedScope.creationStatus) != nil else {
            captureError = store.lastErrorMessage ?? "Could not save. Your draft is retained."
            captureFeedback = .failed(UUID())
            return false
        }
        drafts.removeValue(forKey: selectedScope)
        captureError = nil
        captureFeedback = .saved(UUID())
        endAdding()
        return true
    }

    func beginEditing(_ task: TaskItem) {
        selectedTaskID = nil
        presentedNotesTaskID = nil
        isComposerPresented = false
        editingTaskID = task.id
    }

    func endEditing() {
        editingTaskID = nil
    }

    func beginDragging(_ task: TaskItem) {
        draggedTaskID = task.id
    }

    func endDragging() {
        draggedTaskID = nil
    }

    func finishDragging(releasedOutsidePanel: Bool) -> UUID? {
        guard let draggedTaskID else { return nil }
        self.draggedTaskID = nil
        return releasedOutsidePanel ? draggedTaskID : nil
    }
}
