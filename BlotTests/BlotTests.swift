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

}
