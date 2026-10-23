import AppKit
import XCTest
@testable import NianBox

@MainActor
final class MenuBarLifecycleTests: XCTestCase {
    func testActualCaptureAndCommittedSaveHaveSeparateFeedbackFromServerAcknowledgement() async throws {
        let store = try makeTestStore()
        let server = MemoryServer()
        let engine = SyncEngine(store: store, transport: server)
        let ui = PanelUIState()
        var now = 100.0
        let menu = MenuBarLifecycle(store: store, syncEngine: engine, uiState: ui, clock: { now }, reducedMotion: false, schedulesFrames: false)
        ui.beginAdding()
        XCTAssertEqual(menu.frame.paperY, MenuBarIconFrame.idle.paperY)
        now += 0.27; menu.refresh()
        XCTAssertLessThan(menu.frame.paperY, 1.65)
        XCTAssertGreaterThan(menu.frame.paperY, 0.25)
        now += 0.3; menu.refresh()
        XCTAssertEqual(menu.frame.paperY, 0.25, accuracy: 0.001)
        ui.draftTitle = "Captured locally"
        XCTAssertTrue(ui.saveCapture(in: store))
        XCTAssertNotEqual(menu.frame.mark, .synced)
        now += 0.7; menu.refresh()
        XCTAssertEqual(menu.frame.paperY, 1.65, accuracy: 0.001)
        await engine.syncOnce()
        XCTAssertEqual(menu.frame.mark, .synced)
        ui.beginAdding()
        now += 0.6; menu.refresh()
        XCTAssertEqual(menu.frame.paperY, 0.25, accuracy: 0.001)
        XCTAssertTrue(menu.accessibilityLabel.contains("not yet saved"))
        now += 1; menu.refresh()
        XCTAssertEqual(menu.frame.mark, .none)
        XCTAssertEqual(menu.frame.paperY, 0.25, accuracy: 0.001)
    }

    func testEmptyPollDoesNotChangeImageOrCelebrate() async throws {
        let store = try makeTestStore()
        let engine = SyncEngine(store: store, transport: MemoryServer())
        let menu = MenuBarLifecycle(store: store, syncEngine: engine, uiState: PanelUIState(), reducedMotion: false, schedulesFrames: false)
        let frame = menu.frame
        let pixels = menu.image.tiffRepresentation
        await engine.syncOnce()
        XCTAssertEqual(menu.frame, frame)
        XCTAssertEqual(menu.image.tiffRepresentation, pixels)
        XCTAssertEqual(engine.successRevision, 0)
    }

    func testFailedSaveRetainsInputAndUsesCrossUntilACommittedRetry() throws {
        let gate = PersistenceGate()
        let store = try makeTestStore(persist: gate.save)
        let ui = PanelUIState()
        let menu = MenuBarLifecycle(store: store, syncEngine: SyncEngine(store: store), uiState: ui, reducedMotion: true, schedulesFrames: false)
        ui.beginAdding(); ui.draftTitle = "Do not lose"
        gate.shouldFail = true
        XCTAssertFalse(ui.saveCapture(in: store))
        XCTAssertEqual(menu.frame.mark, .saveFailure)
        XCTAssertEqual(ui.draftTitle, "Do not lose")
        store.refresh()
        XCTAssertEqual(menu.frame.mark, .saveFailure)
        gate.shouldFail = false
        XCTAssertTrue(ui.saveCapture(in: store))
        XCTAssertNotEqual(menu.frame.mark, .saveFailure)
        XCTAssertNotEqual(menu.frame.mark, .synced)
    }

    func testReducedMotionKeepsCaptureStaticAndRetainsDistinctOfflineAndConflictStates() async throws {
        let store = try makeTestStore()
        let server = MemoryServer()
        let engine = SyncEngine(store: store, transport: server)
        let ui = PanelUIState()
        var now = 50.0
        let menu = MenuBarLifecycle(store: store, syncEngine: engine, uiState: ui, clock: { now }, reducedMotion: true, schedulesFrames: false)
        ui.beginAdding()
        let raised = menu.frame
        now += 0.2; menu.refresh()
        XCTAssertEqual(menu.frame, raised)
        ui.draftTitle = "Offline capture"
        XCTAssertTrue(ui.saveCapture(in: store))
        server.failReads = true
        await engine.syncOnce()
        XCTAssertEqual(menu.frame.mark, .offline)
        server.failReads = false
        await engine.syncOnce()
        let id = try XCTUnwrap(store.tasks.first).id
        XCTAssertTrue(store.rename(try XCTUnwrap(store.tasks.first), to: "Local edit"))
        _ = try await server.external(id: id, patch: [:], kind: "delete")
        let priorSuccess = engine.lastSuccess
        await engine.syncOnce()
        XCTAssertEqual(menu.frame.mark, .conflict)
        XCTAssertEqual(engine.lastSuccess, priorSuccess)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testNativeTemplateErrorGlyphsAreDistinctAtOneAndTwoTimesScale() throws {
        for pixels in [18, 36] {
            var representations = Set<Data>()
            for mark in [MenuBarMark.connectionFailure, .saveFailure, .conflict] {
                var frame = MenuBarIconFrame.idle; frame.mark = mark
                let image = MenuBarIconRenderer.image(for: frame)
                XCTAssertTrue(image.isTemplate)
                let rep = try XCTUnwrap(image.representations.compactMap { $0 as? NSBitmapImageRep }.first { $0.pixelsWide == pixels })
                XCTAssertEqual(rep.pixelsHigh, pixels)
                representations.insert(try XCTUnwrap(rep.representation(using: .png, properties: [:])))
            }
            XCTAssertEqual(representations.count, 3)
        }
    }
}
