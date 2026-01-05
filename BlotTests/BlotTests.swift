//
//  BlotTests.swift
//  BlotTests
//
//  Created by Kushagra Srivastava on 1/2/26.
//

import XCTest
@testable import Blot
import SwiftUI
import UniformTypeIdentifiers

#if TESTING || DEBUG
extension BlotDocument {
    /// Test-only initializer to bypass FileDocumentReadConfiguration's inaccessible initializer
    init(testFileWrapper: FileWrapper, contentType: UTType) throws {
        // If your BlotDocument has an initializer like init(size:) set a default first
        self.init()
        // Mirror the read logic used in init(configuration:)
        if contentType == .png || contentType == .jpeg || contentType == .bmp || contentType == .tiff {
            guard let data = testFileWrapper.regularFileContents else {
                throw NSError(domain: "BlotTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing file contents"])
            }
            self.canvasData = data
            if let img = NSImage(data: data) {
                self.canvasSize = img.size
            }
            return
        }
        if contentType == .blot {
            guard let data = testFileWrapper.regularFileContents else {
                throw NSError(domain: "BlotTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing .blot contents"])
            }
            // Expect first 16 bytes as Float64 width/height header
            let headerSize = 16
            guard data.count > headerSize else {
                throw NSError(domain: "BlotTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid .blot header"])
            }
            let header = data.prefix(headerSize)
            let body = data.dropFirst(headerSize)
            let w = header.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Double.self) }
            let h = header.withUnsafeBytes { $0.load(fromByteOffset: 8, as: Double.self) }
            self.canvasSize = CGSize(width: w, height: h)
            self.canvasData = Data(body)
            return
        }
        throw NSError(domain: "BlotTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unsupported content type: \(contentType)"])
    }
}
#endif

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

    // MARK: - Helpers
    private func colorFromImageData(_ data: Data, x: Int, y: Int) -> NSColor? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        let px = max(0, min(x, bitmap.pixelsWide - 1))
        let py = max(0, min(y, bitmap.pixelsHigh - 1))
        return bitmap.colorAt(x: px, y: py)
    }

    // MARK: - BlotDocument format tests
    func testReadableContentTypesIncludeCommonImages() throws {
        let readable = Set(BlotDocument.readableContentTypes)
        XCTAssertTrue(readable.contains(.png))
        XCTAssertTrue(readable.contains(.jpeg))
        XCTAssertTrue(readable.contains(.bmp))
        XCTAssertTrue(readable.contains(.tiff))
        XCTAssertTrue(readable.contains(.blot))
    }

    func testCreateBlankCanvasIsWhite() throws {
        let size = CGSize(width: 8, height: 8)
        let data = BlotDocument.createBlankCanvas(size: size)
        let centerColor = colorFromImageData(data, x: 4, y: 4)
        XCTAssertNotNil(centerColor)
        XCTAssertTrue(centerColor!.isClose(to: .white, tolerance: 0.02))
    }

    func testReadPNGDeterminesCanvasSize() throws {
        // Create a known 40x30 PNG and ensure the reader picks up that size
        let size = CGSize(width: 40, height: 30)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.green.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to create PNG test data")
            return
        }

        let wrapper = FileWrapper(regularFileWithContents: png)
        let readDoc = try BlotDocument(testFileWrapper: wrapper, contentType: .png)
        XCTAssertEqual(Int(readDoc.canvasSize.width), 40)
        XCTAssertEqual(Int(readDoc.canvasSize.height), 30)
    }

    func testCustomBlotFormatHeaderParsing() throws {
        // Build a .blot file: 16-byte header (Float64 width/height) + PNG data
        let size = CGSize(width: 321, height: 123)
        let doc = BlotDocument(size: size)
        let pngData = doc.canvasData

        var header = Data()
        var w = Float64(size.width)
        var h = Float64(size.height)
        header.append(Data(bytes: &w, count: 8))
        header.append(Data(bytes: &h, count: 8))
        let blotData = header + pngData

        let wrapper = FileWrapper(regularFileWithContents: blotData)
        let readDoc = try BlotDocument(testFileWrapper: wrapper, contentType: .blot)

        XCTAssertEqual(readDoc.canvasSize.width, size.width, accuracy: 0.5)
        XCTAssertEqual(readDoc.canvasSize.height, size.height, accuracy: 0.5)

        // Ensure the image data is decodable and matches size
        guard let img = NSImage(data: readDoc.canvasData) else {
            return XCTFail("Decoded canvas data was not a valid image")
        }
        XCTAssertEqual(Int(img.size.width), Int(size.width))
        XCTAssertEqual(Int(img.size.height), Int(size.height))
    }
}

