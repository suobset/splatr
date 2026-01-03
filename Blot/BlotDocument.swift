//
//  BlotDocument.swift
//  Blot
//
//  Created by Kushagra Srivastava on 1/2/26.
//

import SwiftUI
import UniformTypeIdentifiers

// Custom .blot format
extension UTType {
    static var blot: UTType {
        UTType(exportedAs: "com.blot.drawing")
    }
}

struct BlotDocument: FileDocument {
    var canvasData: Data
    var canvasSize: CGSize
    
    static let defaultSize = CGSize(width: 800, height: 600)
    
    init(size: CGSize = BlotDocument.defaultSize) {
        self.canvasSize = size
        self.canvasData = BlotDocument.createBlankCanvas(size: size)
    }
    
    // Read PNG, JPEG, BMP, TIFF, and our custom .blot
    static var readableContentTypes: [UTType] { [.blot, .png, .jpeg, .bmp, .tiff] }
    
    // Save as .blot by default
    static var writableContentTypes: [UTType] { [.blot, .png, .jpeg, .pdf] }
    
    init(configuration: ReadConfiguration) throws {
        let contentType = configuration.contentType
        
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        if contentType == .blot {
            // .blot is a simple format: 8 bytes for width/height as Float64, then PNG data
            guard data.count > 16 else { throw CocoaError(.fileReadCorruptFile) }
            
            let width = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Float64.self) }
            let height = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: Float64.self) }
            let imageData = data.dropFirst(16)
            
            self.canvasSize = CGSize(width: width, height: height)
            self.canvasData = Data(imageData)
        } else {
            // Regular image format
            guard let nsImage = NSImage(data: data),
                  let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData)
            else {
                throw CocoaError(.fileReadCorruptFile)
            }
            
            self.canvasSize = CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            
            if let pngData = bitmap.representation(using: .png, properties: [:]) {
                self.canvasData = pngData
            } else {
                self.canvasData = data
            }
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let contentType = configuration.contentType
        
        guard let image = NSImage(data: canvasData),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        let outputData: Data
        
        switch contentType {
        case .blot:
            // Custom format: size header + PNG data
            var header = Data()
            var width = Float64(canvasSize.width)
            var height = Float64(canvasSize.height)
            header.append(Data(bytes: &width, count: 8))
            header.append(Data(bytes: &height, count: 8))
            
            guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            outputData = header + pngData
            
        case .jpeg:
            guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            outputData = jpegData
            
        case .pdf:
            let pdfData = NSMutableData()
            let consumer = CGDataConsumer(data: pdfData as CFMutableData)!
            var rect = CGRect(origin: .zero, size: canvasSize)
            let context = CGContext(consumer: consumer, mediaBox: &rect, nil)!
            context.beginPDFPage(nil)
            if let cgImage = bitmap.cgImage {
                context.draw(cgImage, in: rect)
            }
            context.endPDFPage()
            context.closePDF()
            outputData = pdfData as Data
            
        default: // PNG
            guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            outputData = pngData
        }
        
        return FileWrapper(regularFileWithContents: outputData)
    }
    
    static func createBlankCanvas(size: CGSize) -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return Data()
        }
        return pngData
    }
}
