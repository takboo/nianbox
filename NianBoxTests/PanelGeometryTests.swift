import XCTest
@testable import NianBox

final class PanelGeometryTests: XCTestCase {
    @MainActor
    func testScopeSwitchDoesNotDestroyAnOpenCaptureSession() {
        let state = PanelUIState()
        state.beginAdding()
        state.selectScope(.backlog)
        XCTAssertTrue(state.isComposerPresented)
        XCTAssertEqual(state.selectedScope, .backlog)
    }

    @MainActor
    func testDraftsAndPrioritiesSurviveScopeChangesAndComposerRecreation() {
        let state = PanelUIState()
        state.beginAdding()
        state.draftTitle = "Tasks thought"
        state.draftPriority = .high
        state.selectScope(.backlog)
        XCTAssertEqual(state.draftTitle, "")
        state.draftTitle = "Backlog thought"
        state.draftPriority = .low
        state.endAdding()
        state.beginAdding()
        XCTAssertEqual(state.draftTitle, "Backlog thought")
        state.selectScope(.tasks)
        XCTAssertEqual(state.draftTitle, "Tasks thought")
        XCTAssertEqual(state.draftPriority, .high)
        state.cancelAdding()
        state.beginAdding()
        XCTAssertEqual(state.draftTitle, "")
        state.selectScope(.backlog)
        XCTAssertEqual(state.draftTitle, "Backlog thought")
        XCTAssertEqual(state.draftPriority, .low)
    }

    @MainActor
    func testCaptureFailureRetainsDraftAndOnlyCommittedSaveReportsSuccess() throws {
        let gate = PersistenceGate()
        let store = try makeTestStore(persist: gate.save)
        let state = PanelUIState()
        state.selectScope(.backlog)
        state.beginAdding()
        state.draftTitle = "Keep this thought"
        gate.shouldFail = true
        XCTAssertFalse(state.saveCapture(in: store))
        XCTAssertEqual(state.draftTitle, "Keep this thought")
        XCTAssertTrue(state.isComposerPresented)
        guard case .failed = state.captureFeedback else { return XCTFail("No save failure feedback") }
        gate.shouldFail = false
        XCTAssertTrue(state.saveCapture(in: store))
        XCTAssertEqual(state.draftTitle, "")
        XCTAssertFalse(state.isComposerPresented)
        XCTAssertEqual(store.tasks.first?.status, .backlog)
        guard case .saved = state.captureFeedback else { return XCTFail("No committed save feedback") }
    }

    func testPanelUsesLargeRoundedWidthAndThirtyPercentLargerHeight() {
        XCTAssertEqual(PanelGeometry.panelWidth, 410, accuracy: 0.001)
        XCTAssertEqual(PanelGeometry.minimumHeight, 494, accuracy: 0.001)
        XCTAssertEqual(PanelGeometry.maximumHeight, 910, accuracy: 0.001)
    }

    func testHotspotsOccupyExactScreenCorners() {
        let frame = CGRect(x: -1_440, y: 0, width: 1_440, height: 900)
        XCTAssertEqual(PanelGeometry.hotspot(in: frame, corner: .topLeft), CGRect(x: -1_440, y: 884, width: 16, height: 16))
        XCTAssertEqual(PanelGeometry.hotspot(in: frame, corner: .topRight), CGRect(x: -16, y: 884, width: 16, height: 16))
        XCTAssertEqual(PanelGeometry.hotspot(in: frame, corner: .bottomLeft), CGRect(x: -1_440, y: 0, width: 16, height: 16))
        XCTAssertEqual(PanelGeometry.hotspot(in: frame, corner: .bottomRight), CGRect(x: -16, y: 0, width: 16, height: 16))
    }

    func testPanelAnchorsInsideVisibleFrame() {
        let frame = CGRect(x: 0, y: 25, width: 1_920, height: 1_030)
        let size = CGSize(width: 340, height: 400)

        XCTAssertEqual(
            PanelGeometry.panelFrame(in: frame, size: size, corner: .topRight),
            CGRect(x: 1_568, y: 643, width: 340, height: 400)
        )
        XCTAssertEqual(
            PanelGeometry.panelFrame(in: frame, size: size, corner: .bottomLeft),
            CGRect(x: 12, y: 37, width: 340, height: 400)
        )
    }

    func testPreferredHeightIsClamped() {
        XCTAssertEqual(PanelGeometry.preferredHeight(taskCount: 0, sectionCount: 0, isComposing: false), PanelGeometry.minimumHeight)
        XCTAssertEqual(PanelGeometry.preferredHeight(taskCount: 100, sectionCount: 3, isComposing: true), PanelGeometry.maximumHeight)
    }
}
