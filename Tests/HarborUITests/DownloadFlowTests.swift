import XCTest

final class DownloadFlowTests: XCTestCase {
    @MainActor func testPlaylistRequiresSelectionBeforeDownloading() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let base = try? String(contentsOf: root.appendingPathComponent("build/ui-fixture-url"), encoding: .utf8) else { throw XCTSkip("Start local fixtures first") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HarborUITest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = XCUIApplication()
        app.launchEnvironment["HARBOR_UI_TEST_ROOT"] = folder.path
        app.launch()
        let add = app.buttons["Add a Link…"]
        XCTAssertTrue(add.waitForExistence(timeout: 15)); add.click()
        let editor = app.textViews["download-links"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.click(); editor.typeText(base + "/playlist")
        app.buttons["Inspect Links"].click()
        let selectAll = app.buttons["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Download 0 Items"].isEnabled)
        selectAll.click()
        XCTAssertTrue(app.buttons["Download 2 Items"].isEnabled)
        app.buttons["Clear"].click()
        XCTAssertFalse(app.buttons["Download 0 Items"].isEnabled)
        app.buttons["Cancel"].click()
        app.terminate()
    }
    @MainActor func testPasteInspectDownloadAndHistoryRecovery() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let config = root.appendingPathComponent("build/ui-fixture-url")
        guard let base = try? String(contentsOf: config, encoding: .utf8), base.hasPrefix("http://127.0.0.1:") else {
            throw XCTSkip("Run python3 Scripts/integration_test.py --ui to start the local fixtures.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HarborUITest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = XCUIApplication()
        app.launchEnvironment["HARBOR_UI_TEST_ROOT"] = folder.path
        app.launch()
        let add = app.buttons["Add a Link…"]
        XCTAssertTrue(add.waitForExistence(timeout: 15)); add.click()
        let editor = app.textViews["download-links"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.click(); editor.typeText(base + "/file")
        app.buttons["Inspect Links"].click()
        let download = app.buttons["Download"]
        XCTAssertTrue(download.waitForExistence(timeout: 15)); XCTAssertTrue(download.isEnabled); download.click()
        let output = folder.appendingPathComponent("Harbor fixture.bin")
        let completed = NSPredicate { _, _ in FileManager.default.fileExists(atPath: output.path) }
        expectation(for: completed, evaluatedWith: nil)
        waitForExpectations(timeout: 25)
        XCTAssertEqual(try Data(contentsOf: output).count, 8_388_608)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Add a Link…"].waitForExistence(timeout: 15))
        let completedRow = app.descendants(matching: .any).matching(identifier: "collection-Completed").firstMatch
        XCTAssertTrue(completedRow.waitForExistence(timeout: 5)); completedRow.click()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "download-completed").firstMatch.waitForExistence(timeout: 10))
        app.terminate()
    }
}
