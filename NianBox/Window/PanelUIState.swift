import Combine
import Foundation

struct CaptureDraft {
    var title = ""
    var priority: TaskPriority = .none
}

enum CaptureFeedback: Equatable {
    case saved(UUID)
    case failed(UUID)
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
        isComposerPresented || editingTaskID != nil || isMenuTracking
    }

    func beginAdding() {
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
