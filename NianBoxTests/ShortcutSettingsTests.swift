import Carbon.HIToolbox
import XCTest
@testable import NianBox

@MainActor
final class ShortcutSettingsTests: XCTestCase {
    private func preferences() -> UserDefaults {
        let name = "org.nianbox.shortcut-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testDefaultAndSavedShortcutSurviveNewSettingsInstance() throws {
        let defaults = preferences()
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.captureShortcut, .default)
        let custom = QuickCaptureShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey))
        var registered: QuickCaptureShortcut?
        settings.registerShortcut = { registered = $0 }
        try settings.updateCaptureShortcut(custom)
        XCTAssertEqual(registered, custom)
        XCTAssertEqual(AppSettings(defaults: defaults).captureShortcut, custom)
        XCTAssertTrue(custom.displayName.hasPrefix("⇧⌘"))
    }

    func testDisableAndRestoreDefaultArePersistent() throws {
        let defaults = preferences()
        let settings = AppSettings(defaults: defaults)
        try settings.updateCaptureShortcut(nil)
        XCTAssertNil(AppSettings(defaults: defaults).captureShortcut)
        try settings.updateCaptureShortcut(.default)
        XCTAssertEqual(AppSettings(defaults: defaults).captureShortcut, .default)
    }

    func testRegistrationConflictDoesNotChangePreferences() throws {
        let defaults = preferences()
        let settings = AppSettings(defaults: defaults)
        let previous = QuickCaptureShortcut(keyCode: 40, modifiers: UInt32(controlKey | optionKey))
        try settings.updateCaptureShortcut(previous)
        settings.registerShortcut = { _ in throw ShortcutError.registration(-9878) }
        XCTAssertThrowsError(try settings.updateCaptureShortcut(.default))
        XCTAssertEqual(settings.captureShortcut, previous)
        XCTAssertEqual(AppSettings(defaults: defaults).captureShortcut, previous)
    }

    func testUnsafeOrCorruptShortcutCannotBecomeActive() throws {
        let defaults = preferences()
        let settings = AppSettings(defaults: defaults)
        for shortcut in [QuickCaptureShortcut(keyCode: 0, modifiers: 0),
                         QuickCaptureShortcut(keyCode: 0, modifiers: UInt32(shiftKey)),
                         QuickCaptureShortcut(keyCode: 55, modifiers: UInt32(cmdKey)),
                         QuickCaptureShortcut(keyCode: 999, modifiers: UInt32(cmdKey))] {
            XCTAssertThrowsError(try settings.updateCaptureShortcut(shortcut))
        }
        defaults.set(Data("corrupt".utf8), forKey: "quickCaptureShortcut")
        XCTAssertEqual(AppSettings(defaults: defaults).captureShortcut, .default)
    }

    func testRecordingCanSuspendAndResumeWithoutChangingPreference() throws {
        let settings = AppSettings(defaults: preferences())
        var events: [Bool] = []
        settings.shortcutRecordingChanged = { events.append($0) }
        settings.setShortcutRecording(true)
        settings.setShortcutRecording(false)
        XCTAssertEqual(events, [true, false])
        XCTAssertEqual(settings.captureShortcut, .default)
    }
}
