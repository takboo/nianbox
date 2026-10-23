import XCTest

final class NianBoxUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["NIANBOX_UI_TESTING"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testCreateAdvanceCompleteAndOpenContextMenu() throws {
        let addButton = app.buttons["add-task-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.click()

        let titleField = app.textFields["new-task-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.click()
        titleField.typeText("Ship prototype")
        titleField.typeKey(.return, modifierFlags: [])

        let title = app.staticTexts["Ship prototype"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "task-row-")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).doubleClick()
        let inProgressSection = app.staticTexts["task-section-inProgress"]
        XCTAssertTrue(inProgressSection.waitForExistence(timeout: 2))

        let markDone = app.buttons.matching(NSPredicate(format: "label == %@", "Mark done")).firstMatch
        XCTAssertTrue(markDone.waitForExistence(timeout: 2))
        markDone.click()
        let doneSection = app.staticTexts["task-section-done"]
        XCTAssertTrue(doneSection.waitForExistence(timeout: 2))

        let actions = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "task-actions-")
        ).firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 2))
        actions.click()

        XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 2))

        let editTitle = app.menuItems["Edit title…"]
        XCTAssertTrue(editTitle.waitForExistence(timeout: 2))
        editTitle.click()

        let editField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "edit-task-title-")
        ).firstMatch
        XCTAssertTrue(editField.waitForExistence(timeout: 2))
    }

    func testLongTaskTitleWrapsInsteadOfTruncating() throws {
        app.buttons["add-task-button"].click()

        let longTitle = "A long task title that should wrap onto multiple lines instead of being cut off"
        let titleField = app.textFields["new-task-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.click()
        titleField.typeText(longTitle)
        titleField.typeKey(.return, modifierFlags: [])

        let title = app.staticTexts[longTitle]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(title.frame.height, 20)
    }

    func testDragReordersTasksWithMatchingPriority() throws {
        addTask(named: "Alpha")
        addTask(named: "Beta")

        let first = app.staticTexts["Alpha"]
        let second = app.staticTexts["Beta"]
        XCTAssertTrue(first.waitForExistence(timeout: 2))
        XCTAssertTrue(second.waitForExistence(timeout: 2))
        XCTAssertLessThan(second.frame.minY, first.frame.minY)

        second.press(forDuration: 0.6, thenDragTo: first)

        let deadline = Date().addingTimeInterval(2)
        while second.frame.minY <= first.frame.minY && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertGreaterThan(second.frame.minY, first.frame.minY)
    }

    func testSearchFiltersTasksByTitle() throws {
        addTask(named: "Book flights")

        XCTAssertTrue(app.staticTexts["Book flights"].waitForExistence(timeout: 2))

        let searchField = app.textFields["task-search-field"]
        XCTAssertFalse(searchField.exists)

        let searchButton = app.buttons["toggle-task-search"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 2))
        searchButton.click()
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.click()
        searchField.typeText("FLIGHTS")

        XCTAssertTrue(app.staticTexts["Book flights"].waitForExistence(timeout: 2))

        let clearSearch = app.buttons["clear-task-search"]
        XCTAssertTrue(clearSearch.waitForExistence(timeout: 2))
        clearSearch.click()
        XCTAssertTrue(app.staticTexts["Book flights"].waitForExistence(timeout: 2))

        searchField.click()
        searchField.typeText("trains")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Book flights"].exists)

        searchButton.click()
        XCTAssertFalse(searchField.exists)
        XCTAssertTrue(app.staticTexts["Book flights"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testHermesTaskAppearsAndMacCompletionReachesServer() async throws {
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".local/e2e.json")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw XCTSkip("Run Scripts/hermes_smoke.py against an isolated test server first")
        }
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
        let task = fixture["task"] as! [String: Any]
        let id = UUID(uuidString: task["id"] as! String)!
        app.terminate()
        app.launchEnvironment["NIANBOX_SYNC_FIXTURE"] = fixtureURL.path
        app.launch()
        let title = app.staticTexts[task["title"] as! String]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let complete = app.buttons["complete-task-\(id.uuidString)"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.click()
        let due = Date().addingTimeInterval(10)
        var done = false
        while Date() < due {
            var request = URLRequest(url: URL(string: fixture["url"] as! String)!.appendingPathComponent("v1/tasks/\(id.uuidString)"))
            request.setValue("Bearer \(fixture["token"] as! String)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            let saved = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            if saved["status"] as? String == "done" { done = true; break }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertTrue(done)
        XCTAssertTrue(title.exists)
    }

    private func addTask(named title: String) {
        let addButton = app.buttons["add-task-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 2))
        addButton.click()

        let titleField = app.textFields["new-task-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.click()
        titleField.typeText(title)
        app.buttons["save-task"].click()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
    }
}
