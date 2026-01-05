//
//  BlotTests.swift
//  BlotTests
//
//  Created by Kushagra Srivastava on 1/2/26.
//

import XCTest
@testable import Blot

final class BlotTests: XCTestCase {

    var doc: BlotDocument!
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        doc = BlotDocument()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        doc = nil
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
    // Adding some Document tests here
    func testDocumentHasCorrectDefaultSize() throws {
        XCTAssertEqual(doc.canvasSize.width, 800)
        XCTAssertEqual(doc.canvasSize.height, 600)
    }
    
    func testDocumentHasNoEmptyData() throws {
        XCTAssertFalse(self.doc.canvasData.isEmpty)
    }
    
    func testColorsMatchWithSimilarColor() throws {
        let red1 = NSColor(red: 1.0, green: 0, blue: 0, alpha: 1)
        let red2 = NSColor(red: 0.95, green: 0.02, blue: 0.02, alpha: 1)
        XCTAssertTrue(red1.isClose(to: red2, tolerance: 0.1))
    }
    
    func testColorsDontMatchWhenDifferent() throws {
        XCTAssertFalse(NSColor.red.isClose(to: NSColor.blue, tolerance: 0.1))
    }
}
