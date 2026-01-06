//
//  CanvasView.swift
//  splatr
//
//  Created by Kushagra Srivastava on 1/2/26.
//

import SwiftUI
import AppKit

struct CanvasView: NSViewRepresentable {
    @Binding var document: splatrDocument
    var currentColor: NSColor
    var brushSize: CGFloat
    var currentTool: Tool
    var showResizeHandles: Bool
    var onCanvasResize: (CGSize) -> Void
    var onCanvasUpdate: (NSImage) -> Void
    @Environment(\.undoManager) var undoManager
    
    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.delegate = context.coordinator
        view.currentColor = currentColor
        view.brushSize = brushSize
        view.currentTool = currentTool
        view.showResizeHandles = showResizeHandles
        
        // Load from document - document is source of truth
        // Notify navigator on initial load
        view.reloadFromDocument(data: document.canvasData, size: document.canvasSize, notifyNavigator: true)
        return view
    }
    
    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        context.coordinator.undoManager = undoManager
        
        nsView.currentColor = currentColor
        nsView.brushSize = brushSize
        nsView.currentTool = currentTool
        nsView.showResizeHandles = showResizeHandles
        
        // Check if document changed externally (undo, redo, clear, flip, etc.)
        if nsView.documentDataHash != document.canvasData.hashValue ||
           nsView.canvasSize != document.canvasSize {
            // Don't notify during update - just reload the image
            nsView.reloadFromDocument(data: document.canvasData, size: document.canvasSize, notifyNavigator: false)
        }
        
        nsView.setNeedsDisplay(nsView.bounds)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(document: $document, undoManager: undoManager, onCanvasResize: onCanvasResize, onCanvasUpdate: onCanvasUpdate)
    }
    
    class Coordinator {
        var document: Binding<splatrDocument>
        var undoManager: UndoManager?
        var onCanvasResize: (CGSize) -> Void
        var onCanvasUpdate: (NSImage) -> Void
        
        init(document: Binding<splatrDocument>, undoManager: UndoManager?, onCanvasResize: @escaping (CGSize) -> Void, onCanvasUpdate: @escaping (NSImage) -> Void) {
            self.document = document
            self.undoManager = undoManager
            self.onCanvasResize = onCanvasResize
            self.onCanvasUpdate = onCanvasUpdate
        }
        
        func saveToDocument(_ data: Data, image: NSImage) {
            document.wrappedValue.canvasData = data
            onCanvasUpdate(image)
        }
        
        func requestCanvasResize(_ size: CGSize) {
            onCanvasResize(size)
        }
        
        func colorPicked(_ color: NSColor) {
            DispatchQueue.main.async {
                ToolPaletteState.shared.foregroundColor = Color(nsColor: color)
            }
        }
        
        func saveWithUndo(newData: Data, image: NSImage, actionName: String) {
            guard let undoManager = undoManager else {
                saveToDocument(newData, image: image)
                return
            }
            
            let oldData = document.wrappedValue.canvasData
            guard oldData != newData else { return }
            
            undoManager.registerUndo(withTarget: self) { [weak self] _ in
                guard let self = self else { return }
                self.document.wrappedValue.canvasData = oldData
                if let img = NSImage(data: oldData) {
                    self.onCanvasUpdate(img)
                }
            }
            undoManager.setActionName(actionName)
            
            document.wrappedValue.canvasData = newData
            onCanvasUpdate(image)
        }
    }
}

class CanvasNSView: NSView {
    weak var delegate: CanvasView.Coordinator?
    
    // Canvas state - derived from document
    private var canvasImage: NSImage?
    var canvasSize: CGSize = CGSize(width: 800, height: 600)
    var documentDataHash: Int = 0
    
    // Tool state
    var currentColor: NSColor = .black
    var brushSize: CGFloat = 4.0
    var currentTool: Tool = .pencil
    var showResizeHandles: Bool = true
    
    // Drawing state
    private var currentPath: [NSPoint] = []
    private var lastPoint: NSPoint?
    
    // Shape tools
    private var shapeStartPoint: NSPoint?
    private var shapeEndPoint: NSPoint?
    
    // Curve tool
    private var curveBaseStart: NSPoint?
    private var curveBaseEnd: NSPoint?
    private var curveControlPoint1: NSPoint?
    private var curvePhase: Int = 0
    
    // Polygon tool
    private var polygonPoints: [NSPoint] = []
    
    // Selection tools
    private var selectionRect: NSRect?
    private var selectionImage: NSImage?
    private var originalSelectionRect: NSRect?
    private var isMovingSelection = false
    private var selectionOffset: NSPoint = .zero
    private var freeFormPath: [NSPoint] = []
    
    // Text tool
    private var textField: NSTextField?
    private var textInsertPoint: NSPoint?
    
    // Resize handles
    private var isResizing = false
    private var resizeEdge: ResizeEdge = .none
    private var resizeStartSize: CGSize = .zero
    private let handleSize: CGFloat = 8
    
    // Airbrush
    private var airbrushTimer: Timer?
    private var airbrushLocation: NSPoint = .zero
    private var isAirbrushActive = false
    
    enum ResizeEdge {
        case none, right, bottom, corner
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override var intrinsicContentSize: NSSize {
        NSSize(width: canvasSize.width + (showResizeHandles ? handleSize : 0),
               height: canvasSize.height + (showResizeHandles ? handleSize : 0))
    }
    
    // MARK: - Document Loading
    
    /// Reload canvas from document data - this is the ONLY way to set canvas content
    func reloadFromDocument(data: Data, size: CGSize, notifyNavigator: Bool = true) {
        documentDataHash = data.hashValue
        canvasSize = size
        
        if data.isEmpty {
            createBlankCanvas()
            return
        }
        
        if let image = NSImage(data: data) {
            // Ensure image is rendered at correct size
            let sizedImage = NSImage(size: size)
            sizedImage.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            image.draw(in: NSRect(origin: .zero, size: size))
            sizedImage.unlockFocus()
            canvasImage = sizedImage
            
            // Only notify navigator if not during a view update
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
    
    private func createBlankCanvas() {
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()
        image.unlockFocus()
        canvasImage = image
    }
    
    // MARK: - Drawing
    
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
    
    private func drawCurrentStroke() {
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
    
    private func drawShapePreview() {
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
    
    private func drawCurvePreview() {
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
    
    private func drawPolygonPreview() {
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
    
    private func drawSelection() {
        if currentTool == .freeFormSelect && freeFormPath.count > 1 {
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
        
        guard let rect = selectionRect else { return }
        
        if let selImage = selectionImage {
            selImage.draw(in: rect)
        }
        
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        NSColor.white.setStroke()
        path.stroke()
        
        path.setLineDash([4, 4], count: 2, phase: CGFloat(CACurrentMediaTime() * 10).truncatingRemainder(dividingBy: 8))
        NSColor.black.setStroke()
        path.stroke()
    }
    
    private func drawResizeHandles() {
        NSColor.controlAccentColor.setFill()
        
        NSBezierPath(roundedRect: NSRect(x: canvasSize.width, y: canvasSize.height/2 - 4, width: 6, height: 8),
                     xRadius: 2, yRadius: 2).fill()
        NSBezierPath(roundedRect: NSRect(x: canvasSize.width/2 - 4, y: -6, width: 8, height: 6),
                     xRadius: 2, yRadius: 2).fill()
        NSBezierPath(roundedRect: NSRect(x: canvasSize.width, y: -6, width: 6, height: 6),
                     xRadius: 2, yRadius: 2).fill()
    }
    
    private func drawStyledShape(_ path: NSBezierPath, lineWidth: CGFloat) {
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
    
    // MARK: - Mouse Events
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeInActiveApp, .mouseMoved, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }
    
    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }
    
    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }
    
    private func updateCursor(at point: NSPoint) {
        if showResizeHandles && resizeEdgeAt(point) != .none {
            switch resizeEdgeAt(point) {
            case .right: NSCursor.resizeLeftRight.set()
            case .bottom: NSCursor.resizeUpDown.set()
            case .corner: NSCursor.crosshair.set()
            default: break
            }
        } else {
            NSCursor.crosshair.set()
        }
    }
    
    private func resizeEdgeAt(_ point: NSPoint) -> ResizeEdge {
        guard showResizeHandles else { return .none }
        
        if NSRect(x: canvasSize.width - 12, y: -6, width: 18, height: 18).contains(point) { return .corner }
        if NSRect(x: canvasSize.width - 4, y: 12, width: 12, height: canvasSize.height - 24).contains(point) { return .right }
        if NSRect(x: 12, y: -6, width: canvasSize.width - 24, height: 12).contains(point) { return .bottom }
        return .none
    }
    
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        
        if showResizeHandles {
            resizeEdge = resizeEdgeAt(point)
            if resizeEdge != .none {
                isResizing = true
                resizeStartSize = canvasSize
                return
            }
        }
        
        let p = clamp(point)
        
        switch currentTool {
        case .pencil, .brush, .eraser:
            currentPath = [p]
            lastPoint = p
            
        case .airbrush:
            airbrushLocation = p
            isAirbrushActive = true
            startAirbrush()
            
        case .fill:
            floodFill(at: p)
            
        case .colorPicker:
            pickColor(at: p)
            
        case .magnifier:
            handleMagnifier(at: p, zoomIn: !event.modifierFlags.contains(.option))
            
        case .text:
            handleTextTool(at: p)
            
        case .line, .rectangle, .ellipse, .roundedRectangle:
            shapeStartPoint = p
            shapeEndPoint = p
            
        case .curve:
            handleCurveMouseDown(at: p)
            
        case .polygon:
            if polygonPoints.isEmpty {
                polygonPoints = [p]
            }
            shapeEndPoint = p
            
        case .freeFormSelect:
            if let rect = selectionRect, rect.contains(p) {
                startMovingSelection(at: p)
            } else {
                commitSelection()
                freeFormPath = [p]
            }
            
        case .rectangleSelect:
            if let rect = selectionRect, rect.contains(p) {
                startMovingSelection(at: p)
            } else {
                commitSelection()
                shapeStartPoint = p
                shapeEndPoint = p
            }
        }
        
        setNeedsDisplay(bounds)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        if isResizing {
            handleResizeDrag(to: point)
            return
        }
        
        let p = clamp(point)
        
        switch currentTool {
        case .pencil, .brush, .eraser:
            if let last = lastPoint {
                let distance = hypot(p.x - last.x, p.y - last.y)
                let steps = max(1, Int(distance / 2))
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    let interp = NSPoint(x: last.x + (p.x - last.x) * t, y: last.y + (p.y - last.y) * t)
                    currentPath.append(interp)
                }
            }
            lastPoint = p
            setNeedsDisplay(bounds)
            
        case .airbrush:
            airbrushLocation = p
            
        case .line, .rectangle, .ellipse, .roundedRectangle:
            shapeEndPoint = event.modifierFlags.contains(.shift) ? constrainedPoint(from: shapeStartPoint!, to: p) : p
            setNeedsDisplay(bounds)
            
        case .curve:
            shapeEndPoint = p
            setNeedsDisplay(bounds)
            
        case .polygon:
            shapeEndPoint = p
            setNeedsDisplay(bounds)
            
        case .freeFormSelect:
            if isMovingSelection {
                moveSelection(to: p)
            } else {
                freeFormPath.append(p)
            }
            setNeedsDisplay(bounds)
            
        case .rectangleSelect:
            if isMovingSelection {
                moveSelection(to: p)
            } else {
                shapeEndPoint = p
                selectionRect = rectFromPoints(shapeStartPoint!, p)
            }
            setNeedsDisplay(bounds)
            
        default:
            setNeedsDisplay(bounds)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if isResizing {
            isResizing = false
            resizeEdge = .none
            return
        }
        
        let p = clamp(convert(event.locationInWindow, from: nil))
        
        switch currentTool {
        case .pencil, .brush, .eraser:
            commitStroke()
            currentPath = []
            lastPoint = nil
            
        case .airbrush:
            stopAirbrush()
            
        case .line:
            commitLine()
            
        case .rectangle, .ellipse, .roundedRectangle:
            commitShape()
            
        case .curve:
            handleCurveMouseUp(at: p)
            
        case .polygon:
            if event.clickCount >= 2 {
                commitPolygon()
            } else {
                polygonPoints.append(p)
            }
            
        case .freeFormSelect:
            if isMovingSelection {
                isMovingSelection = false
            } else if freeFormPath.count > 2 {
                finalizeFreeFormSelection()
            }
            
        case .rectangleSelect:
            if isMovingSelection {
                isMovingSelection = false
            } else if let start = shapeStartPoint {
                selectionRect = rectFromPoints(start, p)
                captureSelection()
                shapeStartPoint = nil
                shapeEndPoint = nil
            }
            
        default: break
        }
        
        setNeedsDisplay(bounds)
    }
    
    // MARK: - Tool Implementations
    
    private func getDrawSize() -> CGFloat {
        switch currentTool {
        case .brush: return brushSize * 2.5
        case .eraser: return brushSize * 3
        default: return brushSize
        }
    }
    
    private func commitStroke() {
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
    
    private func startAirbrush() {
        airbrushTimer?.invalidate()
        airbrushTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.sprayAirbrush()
        }
        sprayAirbrush()
    }
    
    private func sprayAirbrush() {
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
    
    private func stopAirbrush() {
        isAirbrushActive = false
        airbrushTimer?.invalidate()
        airbrushTimer = nil
        saveToDocument(actionName: "Airbrush")
    }
    
    // MARK: - Shape Tools
    
    private func commitLine() {
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
    
    private func commitShape() {
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
    
    private func handleCurveMouseDown(at point: NSPoint) {
        if curvePhase == 0 {
            shapeStartPoint = point
            shapeEndPoint = point
        }
    }
    
    private func handleCurveMouseUp(at point: NSPoint) {
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
    
    private func commitCurve(controlPoint2: NSPoint) {
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
    
    private func resetCurveState() {
        curvePhase = 0
        curveBaseStart = nil
        curveBaseEnd = nil
        curveControlPoint1 = nil
        shapeStartPoint = nil
        shapeEndPoint = nil
    }
    
    // MARK: - Polygon Tool
    
    private func commitPolygon() {
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
    
    // MARK: - Selection Tools
    
    private func startMovingSelection(at point: NSPoint) {
        guard let rect = selectionRect else { return }
        isMovingSelection = true
        selectionOffset = NSPoint(x: point.x - rect.origin.x, y: point.y - rect.origin.y)
        
        if selectionImage != nil && originalSelectionRect == nil {
            originalSelectionRect = rect
            clearRect(rect)
        }
    }
    
    private func moveSelection(to point: NSPoint) {
        guard var rect = selectionRect else { return }
        rect.origin = NSPoint(x: point.x - selectionOffset.x, y: point.y - selectionOffset.y)
        selectionRect = rect
    }
    
    private func finalizeFreeFormSelection() {
        guard freeFormPath.count > 2 else {
            freeFormPath = []
            return
        }
        
        let xs = freeFormPath.map { $0.x }
        let ys = freeFormPath.map { $0.y }
        let rect = NSRect(x: xs.min()!, y: ys.min()!,
                          width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        
        selectionRect = rect
        captureSelection()
        freeFormPath = []
    }
    
    private func captureSelection() {
        guard let rect = selectionRect, rect.width > 0, rect.height > 0, let image = canvasImage else { return }
        
        let captured = NSImage(size: rect.size)
        captured.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: rect.size), from: rect, operation: .copy, fraction: 1.0)
        captured.unlockFocus()
        
        selectionImage = captured
    }
    
    private func commitSelection() {
        guard let rect = selectionRect, let selImage = selectionImage, let image = canvasImage else {
            selectionRect = nil
            selectionImage = nil
            originalSelectionRect = nil
            return
        }
        
        let newImage = NSImage(size: canvasSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))
        selImage.draw(in: rect)
        newImage.unlockFocus()
        
        canvasImage = newImage
        selectionRect = nil
        selectionImage = nil
        originalSelectionRect = nil
        saveToDocument(actionName: "Move Selection")
    }
    
    private func clearRect(_ rect: NSRect) {
        guard let image = canvasImage else { return }
        
        let newImage = NSImage(size: canvasSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))
        NSColor.white.setFill()
        rect.fill()
        newImage.unlockFocus()
        
        canvasImage = newImage
    }
    
    // MARK: - Color Picker & Fill
    
    private func pickColor(at point: NSPoint) {
        guard let image = canvasImage,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return }
        
        let x = Int(point.x)
        let y = Int(canvasSize.height - point.y)
        
        guard x >= 0, x < bitmap.pixelsWide, y >= 0, y < bitmap.pixelsHigh,
              let color = bitmap.colorAt(x: x, y: y) else { return }
        
        delegate?.colorPicked(color)
    }
    
    private func floodFill(at point: NSPoint) {
        guard let image = canvasImage,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return }
        
        let startX = Int(point.x)
        let startY = Int(canvasSize.height - point.y)
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        
        guard startX >= 0 && startX < width && startY >= 0 && startY < height else { return }
        guard let targetColor = bitmap.colorAt(x: startX, y: startY) else { return }
        
        if colorsMatch(targetColor, currentColor) { return }
        
        var visited = [Bool](repeating: false, count: width * height)
        var stack: [(Int, Int)] = [(startX, startY)]
        
        while !stack.isEmpty {
            let (x, y) = stack.removeLast()
            let idx = y * width + x
            
            if x < 0 || x >= width || y < 0 || y >= height { continue }
            if visited[idx] { continue }
            
            guard let pixelColor = bitmap.colorAt(x: x, y: y),
                  colorsMatch(pixelColor, targetColor) else { continue }
            
            visited[idx] = true
            bitmap.setColor(currentColor, atX: x, y: y)
            
            stack.append((x + 1, y))
            stack.append((x - 1, y))
            stack.append((x, y + 1))
            stack.append((x, y - 1))
        }
        
        let newImage = NSImage(size: canvasSize)
        newImage.addRepresentation(bitmap)
        canvasImage = newImage
        saveToDocument(actionName: "Fill")
        setNeedsDisplay(bounds)
    }
    
    private func colorsMatch(_ c1: NSColor, _ c2: NSColor) -> Bool {
        guard let rgb1 = c1.usingColorSpace(.deviceRGB),
              let rgb2 = c2.usingColorSpace(.deviceRGB) else { return false }
        let tolerance: CGFloat = 0.1
        return abs(rgb1.redComponent - rgb2.redComponent) < tolerance &&
               abs(rgb1.greenComponent - rgb2.greenComponent) < tolerance &&
               abs(rgb1.blueComponent - rgb2.blueComponent) < tolerance
    }
    
    // MARK: - Magnifier
    
    private func handleMagnifier(at point: NSPoint, zoomIn: Bool) {
        let state = ToolPaletteState.shared
        if zoomIn {
            state.zoomLevel = min(8, state.zoomLevel * 2)
        } else {
            state.zoomLevel = max(1, state.zoomLevel / 2)
        }
    }
    
    // MARK: - Text Tool
    
    private func handleTextTool(at point: NSPoint) {
        if let tf = textField {
            commitText()
            tf.removeFromSuperview()
            textField = nil
        }
        
        textInsertPoint = point
        
        let tf = NSTextField(frame: NSRect(x: point.x, y: point.y - 20, width: 200, height: 24))
        tf.isBordered = true
        tf.backgroundColor = .white
        tf.font = NSFont(name: ToolPaletteState.shared.fontName, size: ToolPaletteState.shared.fontSize)
        tf.textColor = currentColor
        tf.target = self
        tf.action = #selector(textFieldEntered(_:))
        addSubview(tf)
        tf.becomeFirstResponder()
        textField = tf
    }
    
    @objc private func textFieldEntered(_ sender: NSTextField) {
        commitText()
        sender.removeFromSuperview()
        textField = nil
    }
    
    private func commitText() {
        guard let tf = textField, let point = textInsertPoint, let image = canvasImage else { return }
        
        let text = tf.stringValue
        guard !text.isEmpty else { return }
        
        let newImage = NSImage(size: canvasSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: tf.font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: currentColor
        ]
        
        let attrString = NSAttributedString(string: text, attributes: attrs)
        attrString.draw(at: point)
        
        newImage.unlockFocus()
        canvasImage = newImage
        textInsertPoint = nil
        saveToDocument(actionName: "Text")
    }
    
    // MARK: - Resize Handling
    
    private func handleResizeDrag(to point: NSPoint) {
        var newSize = canvasSize
        
        switch resizeEdge {
        case .right:
            newSize.width = max(50, point.x)
        case .bottom:
            // Bottom handle: dragging down increases height
            newSize.height = max(50, resizeStartSize.height + (resizeStartSize.height - point.y))
        case .corner:
            newSize.width = max(50, point.x)
            newSize.height = max(50, resizeStartSize.height + (resizeStartSize.height - point.y))
        case .none:
            return
        }
        
        // Request resize through ContentView (which handles the actual resize)
        delegate?.requestCanvasResize(newSize)
    }
    
    // MARK: - Helpers
    
    private func clamp(_ point: NSPoint) -> NSPoint {
        NSPoint(x: max(0, min(point.x, canvasSize.width)), y: max(0, min(point.y, canvasSize.height)))
    }
    
    private func rectFromPoints(_ p1: NSPoint, _ p2: NSPoint) -> NSRect {
        NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
               width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }
    
    private func constrainedPoint(from start: NSPoint, to end: NSPoint) -> NSPoint {
        let dx = abs(end.x - start.x)
        let dy = abs(end.y - start.y)
        let d = max(dx, dy)
        return NSPoint(x: start.x + d * (end.x > start.x ? 1 : -1),
                       y: start.y + d * (end.y > start.y ? 1 : -1))
    }
    
    private func resetShapeState() {
        shapeStartPoint = nil
        shapeEndPoint = nil
    }
    
    private func saveToDocument(actionName: String?) {
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

// MARK: - Color Extension
extension NSColor {
    func isClose(to other: NSColor?, tolerance: CGFloat = 0.1) -> Bool {
        guard let other = other,
              let c1 = self.usingColorSpace(.deviceRGB),
              let c2 = other.usingColorSpace(.deviceRGB) else { return false }
        
        return abs(c1.redComponent - c2.redComponent) < tolerance &&
               abs(c1.greenComponent - c2.greenComponent) < tolerance &&
               abs(c1.blueComponent - c2.blueComponent) < tolerance
    }
}
