//
//  CanvasNSView+Fill.swift
//  Splatr
//
//  Created by Kushagra Srivastava on 1/16/26.
//

import AppKit
import SwiftUI

// MARK: - Fill Tool & Color Picker

extension CanvasNSView {
    
    /// Reads the pixel color at the given point and updates the foreground color.
    func pickColor(at point: NSPoint) {
        guard let image = canvasImage,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return }
        
        let scaleX = CGFloat(bitmap.pixelsWide) / image.size.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / image.size.height
        
        let px = Int((point.x * scaleX).rounded(.down))
        let py = Int(((canvasSize.height - point.y) * scaleY).rounded(.down))
        
        guard px >= 0, px < bitmap.pixelsWide, py >= 0, py < bitmap.pixelsHigh,
              let color = bitmap.colorAt(x: px, y: py) else { return }
        
        delegate?.colorPicked(color)
        
        if let previous = previousToolBeforePicker {
            previousToolBeforePicker = nil
            DispatchQueue.main.async {
                ToolPaletteState.shared.currentTool = previous
            }
        }
    }
    
    /// Flood fill using direct pixel buffer manipulation.
    func floodFill(at point: NSPoint) {
        guard let image = canvasImage else { return }
        
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)
        
        guard width > 0, height > 0 else { return }
        
        // Create a new bitmap with known format: 32-bit RGBA
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else { return }
        
        // Draw current canvas into our controlled bitmap
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: bitmap) {
            NSGraphicsContext.current = ctx
            NSColor.white.setFill()
            NSRect(origin: .zero, size: canvasSize).fill()
            image.draw(in: NSRect(origin: .zero, size: canvasSize),
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .sourceOver,
                       fraction: 1.0)
        }
        NSGraphicsContext.restoreGraphicsState()
        
        guard let pixelData = bitmap.bitmapData else { return }
        
        // Convert click point to pixel coordinates (flip Y)
        let clickX = Int(point.x)
        let clickY = height - 1 - Int(point.y)
        
        guard clickX >= 0, clickX < width, clickY >= 0, clickY < height else { return }
        
        // Get target color at click point
        let targetOffset = (clickY * width + clickX) * 4
        let targetR = pixelData[targetOffset]
        let targetG = pixelData[targetOffset + 1]
        let targetB = pixelData[targetOffset + 2]
        
        // Get fill color components
        let fillColor = currentColor.usingColorSpace(.deviceRGB) ?? currentColor
        let fillR = UInt8(fillColor.redComponent * 255)
        let fillG = UInt8(fillColor.greenComponent * 255)
        let fillB = UInt8(fillColor.blueComponent * 255)
        
        // Don't fill if clicking on same color
        let tolerance: Int = 32
        if colorMatchesRGB(targetR, targetG, targetB, fillR, fillG, fillB, tolerance: 1) {
            return
        }
        
        // Scanline flood fill
        var visited = [Bool](repeating: false, count: width * height)
        var stack: [(Int, Int)] = [(clickX, clickY)]
        
        func matchesTarget(_ x: Int, _ y: Int) -> Bool {
            let offset = (y * width + x) * 4
            let r = pixelData[offset]
            let g = pixelData[offset + 1]
            let b = pixelData[offset + 2]
            return colorMatchesRGB(r, g, b, targetR, targetG, targetB, tolerance: tolerance)
        }
        
        func setPixel(_ x: Int, _ y: Int) {
            let offset = (y * width + x) * 4
            pixelData[offset] = fillR
            pixelData[offset + 1] = fillG
            pixelData[offset + 2] = fillB
            pixelData[offset + 3] = 255
        }
        
        while !stack.isEmpty {
            let (seedX, seedY) = stack.removeLast()
            
            if seedY < 0 || seedY >= height { continue }
            let idx = seedY * width + seedX
            if visited[idx] { continue }
            
            var leftX = seedX
            while leftX > 0 && matchesTarget(leftX - 1, seedY) && !visited[seedY * width + leftX - 1] {
                leftX -= 1
            }
            
            var rightX = seedX
            while rightX < width - 1 && matchesTarget(rightX + 1, seedY) && !visited[seedY * width + rightX + 1] {
                rightX += 1
            }
            
            var aboveAdded = false
            var belowAdded = false
            
            for x in leftX...rightX {
                let currentIdx = seedY * width + x
                if visited[currentIdx] { continue }
                if !matchesTarget(x, seedY) { continue }
                
                visited[currentIdx] = true
                setPixel(x, seedY)
                
                if seedY > 0 {
                    let aboveIdx = (seedY - 1) * width + x
                    if !visited[aboveIdx] && matchesTarget(x, seedY - 1) {
                        if !aboveAdded {
                            stack.append((x, seedY - 1))
                            aboveAdded = true
                        }
                    } else {
                        aboveAdded = false
                    }
                }
                
                if seedY < height - 1 {
                    let belowIdx = (seedY + 1) * width + x
                    if !visited[belowIdx] && matchesTarget(x, seedY + 1) {
                        if !belowAdded {
                            stack.append((x, seedY + 1))
                            belowAdded = true
                        }
                    } else {
                        belowAdded = false
                    }
                }
            }
        }
        
        bitmap.size = canvasSize
        let newImage = NSImage(size: canvasSize)
        newImage.addRepresentation(bitmap)
        canvasImage = newImage
        saveToDocument(actionName: "Fill")
        setNeedsDisplay(bounds)
    }
    
    /// Compare two RGB colors within a tolerance.
    func colorMatchesRGB(_ r1: UInt8, _ g1: UInt8, _ b1: UInt8,
                         _ r2: UInt8, _ g2: UInt8, _ b2: UInt8,
                         tolerance: Int) -> Bool {
        let dr = abs(Int(r1) - Int(r2))
        let dg = abs(Int(g1) - Int(g2))
        let db = abs(Int(b1) - Int(b2))
        return dr <= tolerance && dg <= tolerance && db <= tolerance
    }
    
    /// Zooms in or out via shared state.
    func handleMagnifier(at point: NSPoint, zoomIn: Bool) {
        let state = ToolPaletteState.shared
        if zoomIn {
            state.zoomLevel = min(8, state.zoomLevel * 2)
        } else {
            state.zoomLevel = max(1, state.zoomLevel / 2)
        }
    }
}
