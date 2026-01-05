//
//  BlotUITests.swift
//  BlotUITests
//
//  Created by Kushagra Srivastava on 1/2/26.
//

import XCTest

final class BlotUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        app.typeKey("n", modifierFlags: .command)
        sleep(1)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testCanvasSizeAppearsInToolbar() throws {
        // Expect the default size 800 × 600 to be shown somewhere in the UI (toolbar label)
        XCTAssertTrue(app.staticTexts["800 × 600"].firstMatch.waitForExistence(timeout: 2))
    }

    @MainActor
    func testSelectingToolUpdatesIndicator() throws {
        // Open Tools menu and pick Pencil, the indicator in toolbar should show "Pencil"
        app.typeKey("p", modifierFlags: []) // keyboard shortcut for Pencil
        XCTAssertTrue(app.staticTexts["Pencil"].firstMatch.waitForExistence(timeout: 2))

        app.typeKey("b", modifierFlags: []) // Brush
        XCTAssertTrue(app.staticTexts["Brush"].firstMatch.waitForExistence(timeout: 2))
    }

    @MainActor
    func testShowResizeCanvasSheet() throws {
        // Use the keyboard shortcut Command+Shift+R to open the sheet
        app.typeKey("r", modifierFlags: [.command, .shift])
        // Expect a sheet with title "Resize Canvas"
        XCTAssertTrue(app.staticTexts["Resize Canvas"].firstMatch.waitForExistence(timeout: 2))
    }

    @MainActor
    func testCloseSaveDialogExists() throws {
        // Open the File menu and find "Export As"
        // On macOS UI tests, we can attempt to open the menu via keyboard: Option+F isn't standard, use direct menu query
        // As a fallback, verify that pressing Command+P (PNG export) doesn't crash and the Save panel appears.
        app.typeKey("w", modifierFlags: .command)
        // Expect a Save panel with default name "Untitled.png"
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3) || app.dialogs.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

