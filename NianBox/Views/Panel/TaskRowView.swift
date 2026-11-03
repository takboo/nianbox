import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TaskRowView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var uiState: PanelUIState
    let task: TaskItem
    let select: () -> Void

    @State private var editTitle = ""
    @State private var isHovering = false
    @State private var isDropTargeted = false
    @FocusState private var isRenameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEditing: Bool { uiState.editingTaskID == task.id }

    var body: some View {
        HStack(spacing: 8) {
            TaskStatusButton(status: task.status, priority: task.priority) {
                store.performPrimaryAction(task)
            }
            .accessibilityIdentifier("complete-task-\(task.id.uuidString)")

            Group {
                if isEditing {
                    TextField("Task title", text: $editTitle, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .focused($isRenameFocused)
                        .onSubmit(commitRename)
                        .onExitCommand(perform: cancelRename)
                        .accessibilityIdentifier("edit-task-title-\(task.id.uuidString)")
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                            .strikethrough(task.status == .done, color: .secondary)
                            .foregroundStyle(task.status == .done ? .secondary : .primary)
                            .accessibilityLabel(task.title)
                        if let notes = task.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button { uiState.presentNotes(for: task.id) } label: {
                                Text(notes).font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(2).multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain)
                            .help("Show full notes and select text")
                            .accessibilityLabel("Show full notes")
                            .accessibilityIdentifier("task-notes-\(task.id.uuidString)")
                            .popover(isPresented: Binding(
                                get: { uiState.presentedNotesTaskID == task.id },
                                set: { if !$0 { uiState.dismissNotes(for: task.id) } }
                            )) {
                                notesDetail(notes)
                            }
                        }
                        if let dueAt = task.dueAt {
                            Text(dueAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                }
            }
            .font(.system(size: 13, weight: task.status == .inProgress ? .medium : .regular, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingAction
        }
        .padding(.vertical, 2)
        .frame(minHeight: NianBoxStyle.rowHeight)
        .padding(.horizontal, 4)
        .background(
            Color.accentColor.opacity(uiState.selectedTaskID == task.id ? 0.12 : 0),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .background(
            Color.primary.opacity(isHovering ? 0.055 : 0),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        // Says what the drop will do before the mouse is released: a line on
        // the edge the task will land against, or a filled row when the exact
        // slot is decided by the section and priority rules instead.
        .background(
            Color.accentColor.opacity(dropPlacement == .join ? 0.16 : 0),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(alignment: .top) { dropEdgeIndicator(for: .above) }
        .overlay(alignment: .bottom) { dropEdgeIndicator(for: .below) }
        .opacity(isBeingDragged ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: handleDoubleClick)
        .onTapGesture {
            guard !isEditing else { return }
            select()
        }
        .help(progressToggleHelp)
        .contextMenu { taskActions }
        .onDrag {
            dragItemProvider()
        } preview: {
            dragPreview
        }
        .onDrop(of: [TaskDragPayload.internalTaskType], isTargeted: $isDropTargeted) { providers, _ in
            acceptDrop(from: providers)
        }
        .animation(reduceMotion ? nil : NianBoxMotion.quick, value: dropPlacement)
        .animation(reduceMotion ? nil : NianBoxMotion.quick, value: isBeingDragged)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : NianBoxMotion.quick) {
                isHovering = hovering
            }
        }
        .animation(reduceMotion ? nil : NianBoxMotion.spring, value: task.statusRaw)
        .animation(reduceMotion ? nil : NianBoxMotion.quick, value: task.priorityRaw)
        .onChange(of: isEditing) { _, nowEditing in
            guard nowEditing else { return }
            editTitle = task.title
            DispatchQueue.main.async { isRenameFocused = true }
        }
        .onDisappear { uiState.dismissNotes(for: task.id) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(uiState.selectedTaskID == task.id ? [.isSelected] : [])
        .accessibilityIdentifier("task-row-\(task.id.uuidString)")
    }

    private var isBeingDragged: Bool { uiState.draggedTaskID == task.id }

    /// Only while this row is the drop target, and only for a drag the store
    /// would actually honour — a rejected drop must not advertise a landing
    /// spot it will refuse.
    private var dropPlacement: TaskDropPlacement? {
        guard isDropTargeted, let draggedTaskID = uiState.draggedTaskID else { return nil }
        return store.dropPlacement(taskID: draggedTaskID, onto: task.id)
    }

    @ViewBuilder
    private func dropEdgeIndicator(for edge: TaskDropPlacement) -> some View {
        Capsule()
            .fill(Color.accentColor.opacity(dropPlacement == edge ? 0.65 : 0))
            .frame(height: 2)
            .padding(.horizontal, 8)
    }

    private var dragPreview: some View {
        HStack(spacing: 7) {
            TaskStatusMark(status: task.status, priority: task.priority, size: 13)
            Text(task.title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func dragItemProvider() -> NSItemProvider {
        uiState.beginDragging(task)
        return TaskDragPayload(taskID: task.id, title: task.title).itemProvider()
    }

    private func acceptDrop(from providers: [NSItemProvider]) -> Bool {
        TaskDragPayload.loadTaskID(from: providers) { draggedTaskID in
            uiState.endDragging()
            _ = store.drop(taskID: draggedTaskID, onto: task.id)
        }
    }

    @ViewBuilder
    private var trailingAction: some View {
        if isEditing {
            Button(action: commitRename) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Save title")
            .accessibilityLabel("Save title")
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else {
            HStack(spacing: 0) {
                Button { uiState.copy(task) } label: {
                    Image(systemName: copyFeedback?.succeeded == true ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(copyFeedback?.succeeded == true ? Color.accentColor : Color.secondary)
                .opacity(isHovering || uiState.selectedTaskID == task.id || copyFeedback != nil ? 1 : 0)
                .help(copyFeedback?.message ?? "Copy title and full notes")
                .accessibilityLabel(copyFeedback?.message ?? "Copy content")
                .accessibilityIdentifier("copy-task-\(task.id.uuidString)")

                Menu {
                    taskActions
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity(isHovering ? 1 : 0.38)
                .help("Edit task")
                .accessibilityLabel("Edit task")
                .accessibilityIdentifier("task-actions-\(task.id.uuidString)")
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
    }

    private var copyFeedback: TaskCopyFeedback? {
        uiState.copyFeedback.flatMap { $0.taskID == task.id ? $0 : nil }
    }

    private func notesDetail(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(task.title).font(.headline).textSelection(.enabled)
                Spacer()
                Button { uiState.dismissNotes(for: task.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Close notes")
                    .accessibilityIdentifier("close-task-notes-\(task.id.uuidString)")
            }
            ScrollView {
                Text(notes).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    .accessibilityIdentifier("full-task-notes-\(task.id.uuidString)")
            }
            .frame(maxHeight: 280)
            Button(copyFeedback?.message ?? "Copy content") { uiState.copy(task) }
        }
        .padding(16)
        .frame(width: 320)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-notes-detail-\(task.id.uuidString)")
    }

    private var taskActions: some View {
        TaskActionsMenu(store: store, task: task, editLabel: "Edit title…", edit: {
            uiState.beginEditing(task)
        }, copy: { uiState.copy(task, format: $0) })
    }

    private func commitRename() {
        if store.rename(task, to: editTitle) {
            uiState.endEditing()
        }
    }

    private func cancelRename() {
        uiState.endEditing()
    }

    private func handleDoubleClick() {
        guard !isEditing else { return }
        store.performDoubleClickAction(task)
    }

    private var progressToggleHelp: String {
        task.status.doubleClickTitle
    }
}
