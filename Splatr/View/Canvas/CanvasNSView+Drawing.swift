//
//  CanvasNSView+Drawing.swift
//  Splatr
//
//  Created by Kushagra Srivastava on 1/16/26.
//

import AppKit

// MARK: - Drawing Tools (Pencil, Brush, Eraser, Airbrush)

extension CanvasNSView {
    
    /// Tool-specific effective stroke size.
    func getDrawSize() -> CGFloat {
        switch currentTool {
        case .brush: return brushSize * 2.5
        case .eraser: return brushSize * 3
        default: return brushSize
        }
    }
    
    /// Commits the current stroke to the canvas image (with undo support).
    func commitStroke() {
        guard currentPath.count > 0, let image = canvasImage else { return }
        
        let drawColor = currentTool == .eraser ? NSColor.white : currentColor
        let drawSize = getDrawSize()
        
        let newImage = NSImage(size: canvasSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))
        
        drawColor.setStroke()
        drawColor.setFill()
        
        if currentPath.count == 1 {
            let pt = currentPath[0]
            NSBezierPath(ovalIn: NSRect(x: pt.x - drawSize/2, y: pt.y - drawSize/2,
                                        width: drawSize, height: drawSize)).fill()
        } else {
            let path = NSBezierPath()
            path.lineWidth = drawSize
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: currentPath[0])
            for i in 1..<currentPath.count { path.line(to: currentPath[i]) }
            path.stroke()
        }
        
        newImage.unlockFocus()
        canvasImage = newImage
        saveToDocument(actionName: currentTool == .eraser ? "Erase" : "Draw")
    }
    
    // MARK: - Airbrush
    
    /// Starts a timer to periodically spray dots around the airbrush location.
    func startAirbrush() {
        airbrushTimer?.invalidate()
        airbrushTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.sprayAirbrush()
        }
        sprayAirbrush()
    }
    
    /// Applies one "spray" by drawing random dots within a radius.
    func sprayAirbrush() {
        guard isAirbrushActive, let image = canvasImage else { return }
        
        let newImage = NSImage(size: canvasSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))
        
        currentColor.setFill()
        
        let radius = brushSize * 2
        let density = Int(brushSize * 3)
        
        for _ in 0..<density {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let dist = sqrt(CGFloat.random(in: 0...1)) * radius
            let x = airbrushLocation.x + cos(angle) * dist
            let y = airbrushLocation.y + sin(angle) * dist
            
            if x >= 0 && x <= canvasSize.width && y >= 0 && y <= canvasSize.height {
                let dotSize: CGFloat = 1.0
                NSBezierPath(ovalIn: NSRect(x: x - dotSize/2, y: y - dotSize/2,
                                            width: dotSize, height: dotSize)).fill()
            }
        }
        
        newImage.unlockFocus()
        canvasImage = newImage
        setNeedsDisplay(bounds)
    }
    
    /// Stops the airbrush timer and saves.
    func stopAirbrush() {
        isAirbrushActive = false
        airbrushTimer?.invalidate()
        airbrushTimer = nil
        saveToDocument(actionName: "Airbrush")
    }
}
