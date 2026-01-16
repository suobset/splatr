//
//  CanvasNSView+Shapes.swift
//  Splatr
//
//  Created by Kushagra Srivastava on 1/16/26.
//

import AppKit
import SwiftUI

// MARK: - Shape Tools (Line, Rectangle, Ellipse, RoundedRect, Curve, Polygon)

extension CanvasNSView {
    
    /// Commits a line shape to the canvas image.
    func commitLine() {
        guard let start = shapeStartPoint, let end = shapeEndPoint, let image = canvasImage else {
            resetShapeState()
            return
        }
        
        let newImage = NSImage(size: canvasSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))
        
        currentColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = ToolPaletteState.shared.lineWidth
        path.lineCapStyle = .round
        path.move(to: start)
        path.line(to: end)
        path.stroke()
        
        newImage.unlockFocus()
        canvasImage = newImage
        resetShapeState()
        saveToDocument(actionName: "Line")
    }
    
    /// Commits a rectangle/ellipse/rounded-rect shape to the canvas image.
    func commitShape() {
        guard let start = shapeStartPoint, let end = shapeEndPoint, let image = canvasImage else {
            resetShapeState()
            return
        }
        
        let newImage = NSImage(size: canvasSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))
        
        let rect = rectFromPoints(start, end)
        let lineWidth = ToolPaletteState.shared.lineWidth
        
        var path: NSBezierPath
        switch currentTool {
        case .rectangle: path = NSBezierPath(rect: rect)
        case .ellipse: path = NSBezierPath(ovalIn: rect)
        case .roundedRectangle:
            let r = min(rect.width, rect.height) * 0.25
            path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        default: path = NSBezierPath()
        }
        
        path.lineWidth = lineWidth
        let style = ToolPaletteState.shared.shapeStyle
        
        switch style {
        case .outline:
            currentColor.setStroke()
            path.stroke()
        case .filledWithOutline:
            NSColor(ToolPaletteState.shared.backgroundColor).setFill()
            path.fill()
            currentColor.setStroke()
            path.stroke()
        case .filledNoOutline:
            currentColor.setFill()
            path.fill()
        }
        
        newImage.unlockFocus()
        canvasImage = newImage
        resetShapeState()
        saveToDocument(actionName: "Shape")
    }
    
    // MARK: - Curve Tool
    
    /// First click: establish base line for curve.
    func handleCurveMouseDown(at point: NSPoint) {
        if curvePhase == 0 {
            shapeStartPoint = point
            shapeEndPoint = point
        }
    }
    
    /// Subsequent clicks: set control points and commit on final phase.
    func handleCurveMouseUp(at point: NSPoint) {
        if curvePhase == 0 {
            curveBaseStart = shapeStartPoint
            curveBaseEnd = shapeEndPoint
            curvePhase = 1
        } else if curvePhase == 1 {
            curveControlPoint1 = point
            curvePhase = 2
        } else if curvePhase == 2 {
            commitCurve(controlPoint2: point)
        }
    }
    
    /// Draws the final curve and commits to the canvas.
    func commitCurve(controlPoint2: NSPoint) {
        guard let start = curveBaseStart, let end = curveBaseEnd, let image = canvasImage else {
            resetCurveState()
            return
        }
        
        let newImage = NSImage(size: canvasSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))
        
        currentColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = ToolPaletteState.shared.lineWidth
        path.move(to: start)
        path.curve(to: end, controlPoint1: curveControlPoint1 ?? start, controlPoint2: controlPoint2)
        path.stroke()
        
        newImage.unlockFocus()
        canvasImage = newImage
        resetCurveState()
        saveToDocument(actionName: "Curve")
    }
    
    /// Resets curve state machine.
    func resetCurveState() {
        curvePhase = 0
        curveBaseStart = nil
        curveBaseEnd = nil
        curveControlPoint1 = nil
        shapeStartPoint = nil
        shapeEndPoint = nil
    }
    
    // MARK: - Polygon Tool
    
    /// Closes and commits the polygon.
    func commitPolygon() {
        guard polygonPoints.count >= 2, let image = canvasImage else {
            polygonPoints = []
            return
        }
        
        let newImage = NSImage(size: canvasSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))
        
        let path = NSBezierPath()
        path.lineWidth = ToolPaletteState.shared.lineWidth
        path.move(to: polygonPoints[0])
        for i in 1..<polygonPoints.count { path.line(to: polygonPoints[i]) }
        path.close()
        
        let style = ToolPaletteState.shared.shapeStyle
        switch style {
        case .outline:
            currentColor.setStroke()
            path.stroke()
        case .filledWithOutline:
            NSColor(ToolPaletteState.shared.backgroundColor).setFill()
            path.fill()
            currentColor.setStroke()
            path.stroke()
        case .filledNoOutline:
            currentColor.setFill()
            path.fill()
        }
        
        newImage.unlockFocus()
        canvasImage = newImage
        polygonPoints = []
        shapeEndPoint = nil
        saveToDocument(actionName: "Polygon")
    }
    
    /// Clears shape preview state.
    func resetShapeState() {
        shapeStartPoint = nil
        shapeEndPoint = nil
    }
}
