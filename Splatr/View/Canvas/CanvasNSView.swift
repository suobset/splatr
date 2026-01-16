//
//  CanvasNSView.swift
//  Splatr
//
//  Created by Kushagra Srivastava on 1/6/26.
//

import AppKit
import SwiftUI

/// AppKit canvas view that performs pixel-level drawing and previews.
/// The view maintains an NSImage as backing store and draws previews for
/// in-progress strokes, shapes, selections, etc. It communicates changes
/// back through the CanvasView.Coordinator.
class CanvasNSView: NSView {
    weak var delegate: CanvasView.Coordinator?
    
    // MARK: - Canvas State
    
    var canvasImage: NSImage?
    var canvasSize: CGSize = CGSize(width: 800, height: 600)
    /// Hash of the last saved document data to detect external changes.
    var documentDataHash: Int = 0
    
    // MARK: - Tool State
    
    var currentColor: NSColor = .black
    var brushSize: CGFloat = 4.0
    var currentTool: Tool = .pencil {
        didSet {
            if currentTool == .colorPicker, oldValue != .colorPicker {
                previousToolBeforePicker = oldValue
            }
        }
    }
    var previousToolBeforePicker: Tool? = nil
    var showResizeHandles: Bool = true
    
    // MARK: - Drawing State (strokes)
    
    var currentPath: [NSPoint] = []
    var lastPoint: NSPoint?
    
    // MARK: - Shape Tools State
    
    var shapeStartPoint: NSPoint?
    var shapeEndPoint: NSPoint?
    
    // Curve tool
    var curveBaseStart: NSPoint?
    var curveBaseEnd: NSPoint?
    var curveControlPoint1: NSPoint?
    var curvePhase: Int = 0
    
    // Polygon tool
    var polygonPoints: [NSPoint] = []
    
    // MARK: - Selection State
    
    var selectionRect: NSRect?
    var selectionImage: NSImage?
    var originalSelectionRect: NSRect?
    var isMovingSelection = false
    var selectionOffset: NSPoint = .zero
    var freeFormPath: [NSPoint] = []
    var selectionPath: NSBezierPath?
    var lastSelectionOrigin: NSPoint?
    var hasActiveSelection: Bool = false
    var selectionRotation: CGFloat = 0
    
    // MARK: - Transform State
    
    enum SelectionHandle {
        case none, topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, rotate
    }
    var activeHandle: SelectionHandle = .none
    var transformStartRect: NSRect?
    var transformOriginalImage: NSImage?
    var transformOriginalPath: NSBezierPath?
    var transformStartAngle: CGFloat = 0
    var lastMousePoint: NSPoint = .zero
    var transformStartRotation: CGFloat = 0
    
    // MARK: - Text Tool State
    
    var textField: NSTextField?
    var textInsertPoint: NSPoint?
    var isTextSelection: Bool = false
    var hasActiveTextBox: Bool = false
    var textBoxStart: NSPoint?
    var textBoxEnd: NSPoint?
    var isDraggingTextBox: Bool = false
    var lastTextString: String?
    
    // MARK: - Canvas Resize State
    
    var isResizing = false
    var resizeEdge: ResizeEdge = .none
    var resizeStartSize: CGSize = .zero
    let handleSize: CGFloat = 8
    
    enum ResizeEdge {
        case none, right, bottom, corner
    }
    
    // MARK: - Airbrush State
    
    var airbrushTimer: Timer?
    var airbrushLocation: NSPoint = .zero
    var isAirbrushActive = false
    
    // MARK: - Document Loading
    
    /// Reload canvas from document data - this is the ONLY way to set canvas content
    /// from the outside.
    func reloadFromDocument(data: Data, size: CGSize, notifyNavigator: Bool = true) {
        documentDataHash = data.hashValue
        canvasSize = size
        
        if data.isEmpty {
            createBlankCanvas()
            return
        }
        
        if let image = NSImage(data: data) {
            let sizedImage = NSImage(size: size)
            sizedImage.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            image.draw(in: NSRect(origin: .zero, size: size))
            sizedImage.unlockFocus()
            canvasImage = sizedImage
            
            if notifyNavigator {
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.onCanvasUpdate(sizedImage)
                }
            }
        } else {
            createBlankCanvas()
        }
        
        invalidateIntrinsicContentSize()
        setNeedsDisplay(bounds)
    }
    
    /// Creates a white background image for the current canvas size.
    func createBlankCanvas() {
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()
        image.unlockFocus()
        canvasImage = image
    }
    
    // MARK: - Main Draw
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Canvas background
        NSColor.white.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()
        
        // Main image
        canvasImage?.draw(in: NSRect(origin: .zero, size: canvasSize))
        
        // Previews
        drawCurrentStroke()
        drawShapePreview()
        drawCurvePreview()
        drawPolygonPreview()
        drawSelection()
        
        if showResizeHandles {
            drawResizeHandles()
        }
    }
    
    // MARK: - Preview Drawing
    
    /// Renders the temporary stroke preview as the user drags with pencil/brush/eraser.
    func drawCurrentStroke() {
        guard currentPath.count > 0 else { return }
        
        let drawColor = currentTool == .eraser ? NSColor.white : currentColor
        let drawSize = getDrawSize()
        
        drawColor.setStroke()
        drawColor.setFill()
        
        if currentPath.count == 1 {
            let point = currentPath[0]
            NSBezierPath(ovalIn: NSRect(x: point.x - drawSize/2, y: point.y - drawSize/2,
                                        width: drawSize, height: drawSize)).fill()
        } else {
            let path = NSBezierPath()
            path.lineWidth = drawSize
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: currentPath[0])
            for i in 1..<currentPath.count {
                path.line(to: currentPath[i])
            }
            path.stroke()
        }
    }
    
    /// Renders previews for line/rectangle/ellipse/rounded-rectangle as the user drags.
    func drawShapePreview() {
        guard let start = shapeStartPoint, let end = shapeEndPoint else { return }
        guard [.line, .rectangle, .ellipse, .roundedRectangle].contains(currentTool) else { return }
        
        currentColor.setStroke()
        let lineWidth = ToolPaletteState.shared.lineWidth
        let rect = rectFromPoints(start, end)
        
        switch currentTool {
        case .line:
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.move(to: start)
            path.line(to: end)
            path.stroke()
            
        case .rectangle:
            drawStyledShape(NSBezierPath(rect: rect), lineWidth: lineWidth)
            
        case .ellipse:
            drawStyledShape(NSBezierPath(ovalIn: rect), lineWidth: lineWidth)
            
        case .roundedRectangle:
            let radius = min(rect.width, rect.height) * 0.25
            drawStyledShape(NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius), lineWidth: lineWidth)
            
        default: break
        }
    }
    
    /// Renders preview for the curve tool.
    func drawCurvePreview() {
        guard currentTool == .curve else { return }
        
        currentColor.setStroke()
        let lineWidth = ToolPaletteState.shared.lineWidth
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        
        if curvePhase == 0, let start = shapeStartPoint, let end = shapeEndPoint {
            path.move(to: start)
            path.line(to: end)
            path.stroke()
        } else if curvePhase >= 1, let start = curveBaseStart, let end = curveBaseEnd {
            path.move(to: start)
            let cp1 = curveControlPoint1 ?? start
            let cp2 = shapeEndPoint ?? end
            if curvePhase == 1 {
                path.curve(to: end, controlPoint1: cp1, controlPoint2: cp1)
            } else {
                path.curve(to: end, controlPoint1: cp1, controlPoint2: cp2)
            }
            path.stroke()
        }
    }
    
    /// Renders preview for polygon tool.
    func drawPolygonPreview() {
        guard currentTool == .polygon, polygonPoints.count > 0 else { return }
        
        currentColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = ToolPaletteState.shared.lineWidth
        
        path.move(to: polygonPoints[0])
        for i in 1..<polygonPoints.count {
            path.line(to: polygonPoints[i])
        }
        if let end = shapeEndPoint {
            path.line(to: end)
        }
        path.stroke()
    }
    
    /// Draws selection rectangle/image, marching ants/path, and interactive handles.
    func drawSelection() {
        // In-progress freehand path drawing
        if currentTool == .freeFormSelect && freeFormPath.count > 1 && selectionImage == nil && selectionPath == nil {
            NSColor.gray.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1
            path.setLineDash([2, 2], count: 2, phase: 0)
            path.move(to: freeFormPath[0])
            for i in 1..<freeFormPath.count {
                path.line(to: freeFormPath[i])
            }
            path.stroke()
        }

        // Draw selection image if present, with rotation
        if let rect = selectionRect, let selImage = selectionImage {
            let ctx = NSGraphicsContext.current?.cgContext
            ctx?.saveGState()
            let center = rectCenter(rect)
            ctx?.translateBy(x: center.x, y: center.y)
            ctx?.rotate(by: selectionRotation)
            ctx?.translateBy(x: -center.x, y: -center.y)
            selImage.draw(in: rect, from: NSRect(origin: .zero, size: rect.size), operation: .sourceOver, fraction: 1.0)
            
            // Marching ants
            let phase = CGFloat(CACurrentMediaTime() * 10).truncatingRemainder(dividingBy: 8)
            if let path = selectionPath {
                let ants = path.copy() as! NSBezierPath
                ants.lineWidth = 1
                NSColor.white.setStroke()
                ants.stroke()
                ants.setLineDash([4, 4], count: 2, phase: phase)
                NSColor.black.setStroke()
                ants.stroke()
            } else {
                let ants = NSBezierPath(rect: rect)
                ants.lineWidth = 1
                NSColor.white.setStroke()
                ants.stroke()
                ants.setLineDash([4, 4], count: 2, phase: phase)
                NSColor.black.setStroke()
                ants.stroke()
            }
            drawSelectionHandles(rect, rotation: 0)
            ctx?.restoreGState()
            return
        }

        // Marching ants for non-floating selection
        if let path = selectionPath {
            let ants = path.copy() as! NSBezierPath
            ants.lineWidth = 1
            NSColor.white.setStroke()
            ants.stroke()
            let phase = CGFloat(CACurrentMediaTime() * 10).truncatingRemainder(dividingBy: 8)
            ants.setLineDash([4, 4], count: 2, phase: phase)
            NSColor.black.setStroke()
            ants.stroke()
        } else if let rect = selectionRect {
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 1
            NSColor.white.setStroke()
            path.stroke()
            path.setLineDash([4, 4], count: 2, phase: CGFloat(CACurrentMediaTime() * 10).truncatingRemainder(dividingBy: 8))
            NSColor.black.setStroke()
            path.stroke()
        }
        
        // Text box preview while dragging
        if currentTool == .text, isDraggingTextBox, let start = textBoxStart, let end = textBoxEnd {
            let rect = rectFromPoints(start, end)
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: rect)
            path.setLineDash([4, 2], count: 2, phase: 0)
            path.lineWidth = 1.5
            path.stroke()
            drawSelectionHandles(rect, rotation: 0)
        }

        // Handles around active text field
        if let tf = textField {
            let tfRect = tf.frame
            drawSelectionHandles(tfRect, rotation: 0)
        }
    }
    
    /// Draws canvas resize handles.
    func drawResizeHandles() {
        NSColor.controlAccentColor.setFill()
        
        NSBezierPath(roundedRect: NSRect(x: canvasSize.width, y: canvasSize.height/2 - 4, width: 6, height: 8),
                     xRadius: 2, yRadius: 2).fill()
        NSBezierPath(roundedRect: NSRect(x: canvasSize.width/2 - 4, y: -6, width: 8, height: 6),
                     xRadius: 2, yRadius: 2).fill()
        NSBezierPath(roundedRect: NSRect(x: canvasSize.width, y: -6, width: 6, height: 6),
                     xRadius: 2, yRadius: 2).fill()
    }
    
    /// Applies style (outline/filled) to a shape path.
    func drawStyledShape(_ path: NSBezierPath, lineWidth: CGFloat) {
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
    }
}
