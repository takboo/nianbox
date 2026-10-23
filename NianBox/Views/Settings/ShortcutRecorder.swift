import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var settings: AppSettings

    func makeNSView(context: Context) -> RecordingButton {
        let button = RecordingButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = button
        button.action = #selector(RecordingButton.beginRecording)
        button.setAccessibilityIdentifier("quick-capture-shortcut")
        button.setAccessibilityLabel("Quick capture shortcut")
        button.setAccessibilityHelp("Click, then press a shortcut. Escape cancels. Delete disables it.")
        return button
    }

    func updateNSView(_ button: RecordingButton, context: Context) {
        button.shortcut = settings.captureShortcut
        button.onRecording = { settings.setShortcutRecording($0) }
        button.onError = { settings.shortcutError = $0 }
        button.onCapture = { candidate in
            do { try settings.updateCaptureShortcut(candidate) }
            catch { settings.shortcutError = error.localizedDescription; throw error }
        }
        if !button.recording { button.title = button.shortcut?.displayName ?? "Not set" }
    }

    static func dismantleNSView(_ button: RecordingButton, coordinator: ()) { button.finishRecording() }

    final class RecordingButton: NSButton {
        var shortcut: QuickCaptureShortcut?
        var onCapture: ((QuickCaptureShortcut?) throws -> Void)?
        var onRecording: ((Bool) -> Void)?
        var onError: ((String) -> Void)?
        private(set) var recording = false
        override var acceptsFirstResponder: Bool { true }

        @objc func beginRecording() {
            if recording { finishRecording(); return }
            recording = true
            onRecording?(true)
            title = "Press shortcut…"
            window?.makeFirstResponder(self)
        }

        func finishRecording() {
            guard recording else { return }
            recording = false
            onRecording?(false)
            title = shortcut?.displayName ?? "Not set"
        }

        override func resignFirstResponder() -> Bool { finishRecording(); return super.resignFirstResponder() }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == 53 { finishRecording(); return }
            do {
                let candidate: QuickCaptureShortcut?
                if [51, 117].contains(event.keyCode), event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                    candidate = nil
                } else { candidate = try QuickCaptureShortcut(event: event) }
                try onCapture?(candidate)
                shortcut = candidate
            } catch { onError?(error.localizedDescription) }
            finishRecording()
        }
    }
}
