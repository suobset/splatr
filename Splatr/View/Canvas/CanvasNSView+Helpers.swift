//
//  CanvasNSView+Helpers.swift
//  Splatr
//
//  Created by Kushagra Srivastava on 1/16/26.
//

import AppKit

// MARK: - Helper Functions & Properties

extension CanvasNSView {
    
    override var acceptsFirstResponder: Bool { true }
    
    override var intrinsicContentSize: NSSize {
        NSSize(width: canvasSize.width + (showResizeHandles ? handleSize : 0),
               height: canvasSize.height + (showResizeHandles ? handleSize : 0))
    }
    
    /// Clamp a point to the canvas bounds.
    func clamp(_ point: NSPoint) -> NSPoint {
        NSPoint(x: max(0, min(point.x, canvasSize.width)), y: max(0, min(point.y, canvasSize.height)))
    }

    /// Returns the center point of a rect.
    func rectCenter(_ rect: NSRect) -> NSPoint {
        NSPoint(x: rect.midX, y: rect.midY)
    }
    
    /// Construct a rect from two corner points.
    func rectFromPoints(_ p1: NSPoint, _ p2: NSPoint) -> NSRect {
        NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
               width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }
    
    /// Constrain to square/circle or 45-degree line when holding Shift.
    func constrainedPoint(from start: NSPoint, to end: NSPoint) -> NSPoint {
        let dx = abs(end.x - start.x)
        let dy = abs(end.y - start.y)
        let d = max(dx, dy)
        return NSPoint(x: start.x + d * (end.x > start.x ? 1 : -1),
                       y: start.y + d * (end.y > start.y ? 1 : -1))
    }
    
    /// Rotate a point around a center by an angle (radians).
    func rotatePoint(_ point: NSPoint, around center: NSPoint, by angle: CGFloat) -> NSPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cosA = cos(angle)
        let sinA = sin(angle)
        return NSPoint(
            x: center.x + dx * cosA - dy * sinA,
            y: center.y + dx * sinA + dy * cosA
        )
    }
    
    /// Serializes the current canvas image as PNG and saves to the document.
    func saveToDocument(actionName: String?) {
        guard let image = canvasImage,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        
        documentDataHash = pngData.hashValue
        
        if let name = actionName {
            delegate?.saveWithUndo(newData: pngData, image: image, actionName: name)
        } else {
            delegate?.saveToDocument(pngData, image: image)
        }
    }
}
