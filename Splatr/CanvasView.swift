//
//  CanvasView.swift
//  splatr
//
//  Created by Kushagra Srivastava on 1/2/26.
//

import SwiftUI
import AppKit

/// SwiftUI wrapper for an AppKit-based canvas view that handles pixel drawing,
/// tools (pencil, brush, eraser, airbrush, shapes, selection, text, color picker),
/// resize handles, and undo integration. The view synchronizes with the document
/// model and notifies the Navigator palette of updates.
struct CanvasView: NSViewRepresentable {
    @Binding var document: splatrDocument
    /// Foreground drawing color (converted from SwiftUI Color by the caller).
    var currentColor: NSColor
    /// Base brush size (interpreted per tool).
    var brushSize: CGFloat
    /// Currently selected tool from the shared tool palette state.
    var currentTool: Tool
    /// Whether to render resize handles and accept resize drags.
    var showResizeHandles: Bool
    /// Callback to request a canvas resize (delegated to ContentView).
    var onCanvasResize: (CGSize) -> Void
    /// Callback to update the Navigator image after changes.
    var onCanvasUpdate: (NSImage) -> Void
    /// Undo manager injected from SwiftUI environment for registration.
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
        // Keep undo manager up-to-date for new windows/contexts.
        context.coordinator.undoManager = undoManager
        
        // Propagate tool and UI state into the NSView.
        nsView.currentColor = currentColor
        nsView.brushSize = brushSize
        nsView.currentTool = currentTool
        nsView.showResizeHandles = showResizeHandles
        
        // Detect external document changes (undo/redo/clear/flip/etc.) and reload image.
        if nsView.documentDataHash != document.canvasData.hashValue ||
           nsView.canvasSize != document.canvasSize {
            // Don't notify during update - just reload the image
            nsView.reloadFromDocument(data: document.canvasData, size: document.canvasSize, notifyNavigator: false)
        }
        
        // Request a redraw to reflect any state changes.
        nsView.setNeedsDisplay(nsView.bounds)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(document: $document, undoManager: undoManager, onCanvasResize: onCanvasResize, onCanvasUpdate: onCanvasUpdate)
    }
    
    /// Mediates between the NSView and SwiftUI: writes to the document binding,
    /// registers undo, and forwards callbacks to ContentView.
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
        
        /// Saves new image data into the document and updates the Navigator without undo registration.
        func saveToDocument(_ data: Data, image: NSImage) {
            document.wrappedValue.canvasData = data
            onCanvasUpdate(image)
        }
        
        /// Requests the outer SwiftUI view to perform a canvas resize.
        func requestCanvasResize(_ size: CGSize) {
            onCanvasResize(size)
        }
        
        /// Updates the shared foreground color after a color pick operation.
        func colorPicked(_ color: NSColor) {
            DispatchQueue.main.async {
                ToolPaletteState.shared.foregroundColor = Color(nsColor: color)
            }
        }
        
        /// Saves new image data into the document and registers an undo operation.
        func saveWithUndo(newData: Data, image: NSImage, actionName: String) {
            guard let undoManager = undoManager else {
                saveToDocument(newData, image: image)
                return
            }
            
            let oldData = document.wrappedValue.canvasData
            guard oldData != newData else { return }
            
            // Register undo to restore previous canvas data and navigator image.
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

/// AppKit canvas view that performs pixel-level drawing and previews.
/// The view maintains an NSImage as backing store and draws previews for
/// in-progress strokes, shapes, selections, etc. It communicates changes
/// back through the CanvasView.Coordinator.
class CanvasNSView: NSView {
    weak var delegate: CanvasView.Coordinator?
    
    // Canvas state - derived from document
    private var canvasImage: NSImage?
    var canvasSize: CGSize = CGSize(width: 800, height: 600)
    /// Hash of the last saved document data to detect external changes.
    var documentDataHash: Int = 0
    
    // Tool state
    var currentColor: NSColor = .black
    var brushSize: CGFloat = 4.0
    var currentTool: Tool = .pencil {
        didSet {
            // Remember the tool we came from when switching into the color picker
            if currentTool == .colorPicker, oldValue != .colorPicker {
                previousToolBeforePicker = oldValue
            }
        }
    }
    private var previousToolBeforePicker: Tool? = nil
    /// Controls whether resize handles are drawn and interactive.
    var showResizeHandles: Bool = true
    
    // Drawing state (for strokes)
    private var currentPath: [NSPoint] = []
    private var lastPoint: NSPoint?
    
    // Shape tools (rectangle, ellipse, rounded rect, line)
    private var shapeStartPoint: NSPoint?
    private var shapeEndPoint: NSPoint?
    
    // Curve tool (quadratic-like using two control phases)
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
    // True free-form selection path and tracking of its position
    private var selectionPath: NSBezierPath?
    private var lastSelectionOrigin: NSPoint?
    // Track if we have an active/committed selection (prevents new selections until ESC)
    private var hasActiveSelection: Bool = false
    
    // Transform/handles
    private enum SelectionHandle {
        case none, topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, rotate
    }
    private var activeHandle: SelectionHandle = .none
    private var transformStartRect: NSRect?
    private var transformOriginalImage: NSImage?
    private var transformOriginalPath: NSBezierPath?
    private var transformStartAngle: CGFloat = 0
    private var lastMousePoint: NSPoint = .zero
    private var transformStartRotation: CGFloat = 0
    
    // Text tool
    private var textField: NSTextField?
    private var textInsertPoint: NSPoint?
    // Tracks whether we originated from text tool (for commit action naming)
    private var isTextSelection: Bool = false
    // Track if we have an active text box (prevents new text boxes until ESC)
    private var hasActiveTextBox: Bool = false
    
    // Canvas resize handles (outside canvas)
    private var isResizing = false
    private var resizeEdge: ResizeEdge = .none
    private var resizeStartSize: CGSize = .zero
    private let handleSize: CGFloat = 8
    
    // Airbrush
    private var airbrushTimer: Timer?
    private var airbrushLocation: NSPoint = .zero
    private var isAirbrushActive = false
    
    /// Which handle/edge is being dragged during a resize gesture.
    enum ResizeEdge {
        case none, right, bottom, corner
    }
    
    // Selection combination mode
    private enum SelectionCombineMode { case replace, add, subtract }
    
    // State for text box drag and editing
    private var textBoxStart: NSPoint?
    private var textBoxEnd: NSPoint?
    private var isDraggingTextBox: Bool = false
    
    // Track the last text string and rotation angle
    private var lastTextString: String?
    private var selectionRotation: CGFloat = 0  // in radians

    override var acceptsFirstResponder: Bool { true }
    
    /// Provide a context menu with selection operations.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let hasSelection = (selectionRect != nil && selectionImage != nil)
        menu.addItem(withTitle: "Copy", action: #selector(copySelection), keyEquivalent: "")
        menu.items.last?.isEnabled = hasSelection
        menu.addItem(withTitle: "Paste", action: #selector(pasteFromPasteboard), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Delete", action: #selector(deleteSelectionAction), keyEquivalent: "")
        menu.items.last?.isEnabled = hasSelection
        menu.addItem(NSMenuItem.separator())
        let rotateCW = NSMenuItem(title: "Rotate 90° CW", action: #selector(rotateCWAction), keyEquivalent: "")
        rotateCW.isEnabled = hasSelection
        menu.addItem(rotateCW)
        let rotateCCW = NSMenuItem(title: "Rotate 90° CCW", action: #selector(rotateCCWAction), keyEquivalent: "")
        rotateCCW.isEnabled = hasSelection
        menu.addItem(rotateCCW)
        menu.addItem(NSMenuItem.separator())
        let scaleUp = NSMenuItem(title: "Scale 200%", action: #selector(scaleUpAction), keyEquivalent: "")
        scaleUp.isEnabled = hasSelection
        menu.addItem(scaleUp)
        let scaleDown = NSMenuItem(title: "Scale 50%", action: #selector(scaleDownAction), keyEquivalent: "")
        scaleDown.isEnabled = hasSelection
        menu.addItem(scaleDown)
        return menu
    }
    
    /// Handle keyboard shortcuts for selection operations.
    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? ""
        if chars == String(UnicodeScalar(0x1B)!) { // ESC key
            if let tf = textField {
                commitText()
                tf.removeFromSuperview()
                textField = nil
                hasActiveTextBox = false
                setNeedsDisplay(bounds)
                window?.makeFirstResponder(self)
                return
            }
            if selectionImage != nil || selectionRect != nil || hasActiveSelection {
                commitSelection()
                selectionRotation = 0
                hasActiveSelection = false
                setNeedsDisplay(bounds)
                window?.makeFirstResponder(self)
                return
            }
        }
        super.keyDown(with: event)
    }
    
    /// Expand intrinsic size to include resize handle extents so SwiftUI can lay out correctly.
    override var intrinsicContentSize: NSSize {
        NSSize(width: canvasSize.width + (showResizeHandles ? handleSize : 0),
               height: canvasSize.height + (showResizeHandles ? handleSize : 0))
    }
    
    // MARK: - Document Loading
    
    /// Reload canvas from document data - this is the ONLY way to set canvas content
    /// from the outside. It constructs an NSImage of the document size and optionally
    /// notifies the Navigator with the new image.
    func reloadFromDocument(data: Data, size: CGSize, notifyNavigator: Bool = true) {
        documentDataHash = data.hashValue
        canvasSize = size
        
        if data.isEmpty {
            createBlankCanvas()
            return
        }
        
        if let image = NSImage(data: data) {
            // Ensure image is rendered at correct size (clear background to white).
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
    
    /// Creates a white background image for the current canvas size.
    private func createBlankCanvas() {
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()
        image.unlockFocus()
        canvasImage = image
    }
    
    // MARK: - Drawing
    
    /// Main draw routine: paints the canvas background, the backing image,
    /// and all in-progress previews (stroke, shapes, selections, etc.).
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
    
    /// Renders the temporary stroke preview as the user drags with pencil/brush/eraser.
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
    
    /// Renders previews for line/rectangle/ellipse/rounded-rectangle as the user drags.
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
    
    /// Renders preview for the curve tool, progressing through phases as control points are chosen.
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
    
    /// Renders preview for polygon tool as points are added and mouse moves.
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
    
    /// Draws selection rectangle/image, marching ants/path, and interactive handles.
    private func drawSelection() {
        // In-progress freehand path drawing (before capture)
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
            // Draw marching ants (rotated with selection)
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
            // Draw handles in rotated space
            drawSelectionHandles(rect, rotation: 0) // Handles drawn in rotated context
            ctx?.restoreGState()
            return
        }

        // Draw marching ants for non-floating selection (not rotated)
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
        
        // Draw text box preview while dragging
        if currentTool == .text, isDraggingTextBox, let start = textBoxStart, let end = textBoxEnd {
            let rect = rectFromPoints(start, end)
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: rect)
            path.setLineDash([4, 2], count: 2, phase: 0)
            path.lineWidth = 1.5
            path.stroke()
            drawSelectionHandles(rect, rotation: 0)
        }

        // Draw handles around active text field for transform affordance
        if let tf = textField {
            let tfRect = tf.frame
            drawSelectionHandles(tfRect, rotation: 0)
        }
    }
    
    /// Draws right, bottom, and corner resize handles next to the canvas.
    private func drawResizeHandles() {
        NSColor.controlAccentColor.setFill()
        
        NSBezierPath(roundedRect: NSRect(x: canvasSize.width, y: canvasSize.height/2 - 4, width: 6, height: 8),
                     xRadius: 2, yRadius: 2).fill()
        NSBezierPath(roundedRect: NSRect(x: canvasSize.width/2 - 4, y: -6, width: 8, height: 6),
                     xRadius: 2, yRadius: 2).fill()
        NSBezierPath(roundedRect: NSRect(x: canvasSize.width, y: -6, width: 6, height: 6),
                     xRadius: 2, yRadius: 2).fill()
    }
    
    /// Applies style (outline/filled) to a shape path for preview drawing.
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
    
    /// Install tracking area to receive mouseMoved and cursor updates.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeInActiveApp, .mouseMoved, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }
    
    override func cursorUpdate(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        lastMousePoint = clamp(p)
        updateCursor(at: lastMousePoint)
    }
    
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        lastMousePoint = clamp(p)
        updateCursor(at: lastMousePoint)
    }
    
    /// Switch cursor when hovering over resize handles; otherwise show crosshair for drawing.
    private func updateCursor(at point: NSPoint) {
        if showResizeHandles && resizeEdgeAt(point) != .none {
            switch resizeEdgeAt(point) {
            case .right: NSCursor.resizeLeftRight.set()
            case .bottom: NSCursor.resizeUpDown.set()
            case .corner: NSCursor.crosshair.set()
            case .none: break
            }
            return
        }

        // Text box drag handles
        if currentTool == .text, isDraggingTextBox, let start = textBoxStart, let end = textBoxEnd {
            let rect = rectFromPoints(start, end)
            let handle = handleAt(point, in: rect)
            switch handle {
            case .left, .right: NSCursor.resizeLeftRight.set(); return
            case .top, .bottom: NSCursor.resizeUpDown.set(); return
            case .rotate: NSCursor.crosshair.set(); return
            case .topLeft, .topRight, .bottomLeft, .bottomRight: NSCursor.crosshair.set(); return
            default: break
            }
            if rect.contains(point) && handle == .none {
                NSCursor.openHand.set(); return
            }
        }

        // Text field handle cursors
        if let tf = textField {
            let handle = handleAt(point, in: tf.frame)
            switch handle {
            case .left, .right: NSCursor.resizeLeftRight.set(); return
            case .top, .bottom: NSCursor.resizeUpDown.set(); return
            case .rotate: NSCursor.crosshair.set(); return
            case .topLeft, .topRight, .bottomLeft, .bottomRight: NSCursor.crosshair.set(); return
            default: break
            }
            // Inside text field rect = move cursor
            if tf.frame.contains(point) && handle == .none {
                NSCursor.openHand.set(); return
            }
        }
        
        // Selection handle cursors
        if let rect = selectionRect, selectionImage != nil {
            let handle = handleAt(point, in: rect)
            switch handle {
            case .left, .right: NSCursor.resizeLeftRight.set(); return
            case .top, .bottom: NSCursor.resizeUpDown.set(); return
            case .rotate: NSCursor.crosshair.set(); return
            default: break
            }
        }
        NSCursor.crosshair.set()
    }
    
    /// Hit-tests which canvas resize edge/handle is under the cursor.
    private func resizeEdgeAt(_ point: NSPoint) -> ResizeEdge {
        guard showResizeHandles else { return .none }
        
        if NSRect(x: canvasSize.width - 12, y: -6, width: 18, height: 18).contains(point) { return .corner }
        if NSRect(x: canvasSize.width - 4, y: 12, width: 12, height: canvasSize.height - 24).contains(point) { return .right }
        if NSRect(x: 12, y: -6, width: canvasSize.width - 24, height: 12).contains(point) { return .bottom }
        return .none
    }
    
    /// Begin drawing, selecting, transforming, or resizing based on tool and click location.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastMousePoint = clamp(point)

        // If switching to a different tool, commit/remove any text field or floating selection
        if currentTool != .text && currentTool != .rectangleSelect && currentTool != .freeFormSelect {
            if let tf = textField {
                commitText()
                tf.removeFromSuperview()
                textField = nil
                hasActiveTextBox = false
                setNeedsDisplay(bounds)
            }
            if selectionImage != nil || selectionRect != nil {
                commitSelection()
                hasActiveSelection = false
                setNeedsDisplay(bounds)
            }
        }

        // TEXT TOOL HANDLING
        if currentTool == .text {
            // If we have an active text box, only allow transform/move operations
            if hasActiveTextBox {
                // If a text field is present, check if the click is inside its frame or on its handles
                if let tf = textField {
                    let tfRect = tf.frame
                    let handle = handleAt(lastMousePoint, in: tfRect)
                    if handle != .none || tfRect.contains(lastMousePoint) {
                        // Convert text field to floating selection for transform
                        lastTextString = tf.stringValue
                        selectionRotation = 0
                        let image = renderTextFieldToImage(tf)
                        selectionImage = image
                        selectionRect = tf.frame
                        selectionPath = nil
                        originalSelectionRect = nil
                        lastSelectionOrigin = tf.frame.origin
                        isMovingSelection = false
                        tf.removeFromSuperview()
                        textField = nil
                        textInsertPoint = nil
                        // Now begin transform or move
                        if handle != .none {
                            beginTransform(handle: handle, at: lastMousePoint)
                        } else {
                            startMovingSelection(at: lastMousePoint)
                        }
                        setNeedsDisplay(bounds)
                        return
                    }
                    // Click is outside text field - ignore (don't start new text box)
                    return
                }
                // If a floating selection exists (from text), allow transform/move
                if let rect = selectionRect, selectionImage != nil {
                    let handle = handleAt(lastMousePoint, in: rect)
                    if handle != .none {
                        beginTransform(handle: handle, at: lastMousePoint)
                        setNeedsDisplay(bounds)
                        return
                    }
                    if rect.contains(lastMousePoint) {
                        startMovingSelection(at: lastMousePoint)
                        setNeedsDisplay(bounds)
                        return
                    }
                    // Click outside floating selection - ignore
                    return
                }
            }
            // No active text box - start a new one
            textBoxStart = clamp(point)
            textBoxEnd = clamp(point)
            isDraggingTextBox = true
            setNeedsDisplay(bounds)
            return
        }

        // TEXT FIELD HANDLE/RECT LOGIC (for non-text tools that might have a text field)
        if let tf = textField {
            let tfRect = tf.frame
            let handle = handleAt(lastMousePoint, in: tfRect)
            if handle != .none || tfRect.contains(lastMousePoint) {
                // Convert text field to floating selection
                let image = renderTextFieldToImage(tf)
                selectionImage = image
                selectionRect = tfRect
                selectionPath = nil
                originalSelectionRect = nil
                lastSelectionOrigin = tfRect.origin
                isMovingSelection = false
                tf.removeFromSuperview()
                textField = nil
                textInsertPoint = nil
                // Now begin transform or move
                if handle != .none {
                    beginTransform(handle: handle, at: lastMousePoint)
                } else {
                    startMovingSelection(at: lastMousePoint)
                }
                setNeedsDisplay(bounds)
                return
            }
        }

        // Check for canvas resize handle drags first
        if showResizeHandles {
            resizeEdge = resizeEdgeAt(point)
            if resizeEdge != .none {
                isResizing = true
                resizeStartSize = canvasSize
                return
            }
        }
        
        // If there is a floating selection, check transform handles first
        if let rect = selectionRect, selectionImage != nil {
            let handle = handleAt(lastMousePoint, in: rect)
            if handle != .none {
                beginTransform(handle: handle, at: lastMousePoint)
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
            // If we have an active selection, only allow transform/move operations
            if hasActiveSelection {
                if let path = selectionPath, path.contains(p) {
                    startMovingSelection(at: p)
                } else if let rect = selectionRect {
                    let handle = handleAt(p, in: rect)
                    if handle != .none {
                        beginTransform(handle: handle, at: p)
                    } else if rect.contains(p) {
                        startMovingSelection(at: p)
                    }
                    // Click outside selection - ignore (don't start new selection)
                }
            } else {
                // No active selection - start a new freehand path
                freeFormPath = [p]
                isMovingSelection = false
            }
            
        case .rectangleSelect:
            // If we have an active selection, only allow transform/move operations
            if hasActiveSelection {
                if let rect = selectionRect {
                    let handle = handleAt(p, in: rect)
                    if handle != .none {
                        beginTransform(handle: handle, at: p)
                    } else if rect.contains(p) {
                        startMovingSelection(at: p)
                    }
                    // Click outside selection - ignore (don't start new selection)
                }
            } else {
                // No active selection - start a new rectangle selection
                shapeStartPoint = p
                shapeEndPoint = p
            }
        }
        
        setNeedsDisplay(bounds)
    }
    
    /// Update in-progress drawing/selection/shape/transform as the mouse drags.
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastMousePoint = clamp(point)
        
        if isDraggingTextBox, currentTool == .text {
            textBoxEnd = clamp(point)
            setNeedsDisplay(bounds)
            return
        }
        
        if isResizing {
            handleResizeDrag(to: point)
            return
        }
        
        // Transforming floating selection
        if activeHandle != .none {
            updateTransform(to: lastMousePoint)
            setNeedsDisplay(bounds)
            return
        }
        
        let p = clamp(point)
        
        switch currentTool {
        case .pencil, .brush, .eraser:
            // Interpolate intermediate points for smoother strokes
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
            } else if !hasActiveSelection {
                freeFormPath.append(p)
            }
            setNeedsDisplay(bounds)
            
        case .rectangleSelect:
            if isMovingSelection {
                moveSelection(to: p)
            } else if !hasActiveSelection {
                shapeEndPoint = p
                selectionRect = rectFromPoints(shapeStartPoint!, p)
            }
            setNeedsDisplay(bounds)
            
        default:
            setNeedsDisplay(bounds)
        }
    }
    
    /// Finalize the operation for the current tool or transform on mouse up.
    override func mouseUp(with event: NSEvent) {
        if isDraggingTextBox, currentTool == .text {
            isDraggingTextBox = false
            guard let start = textBoxStart, let end = textBoxEnd else { return }
            let rect = rectFromPoints(start, end)
            if rect.width < 10 || rect.height < 10 { // Too small, ignore
                textBoxStart = nil
                textBoxEnd = nil
                setNeedsDisplay(bounds)
                return
            }
            // Create NSTextField sized to rect, font size fits height
            let state = ToolPaletteState.shared
            let fontSize = max(8, rect.height - 8)
            let font = NSFont(name: state.fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            let tf = NSTextField(frame: rect)
            tf.isBordered = true
            tf.backgroundColor = .white
            tf.font = font
            tf.textColor = currentColor
            tf.target = self
            tf.action = #selector(textFieldEntered(_:))
            tf.focusRingType = .none
            tf.lineBreakMode = .byWordWrapping
            tf.usesSingleLineMode = false
            tf.cell?.wraps = true
            tf.cell?.isScrollable = false
            addSubview(tf)
            tf.becomeFirstResponder()
            textField = tf
            textInsertPoint = rect.origin
            textBoxStart = nil
            textBoxEnd = nil
            hasActiveTextBox = true  // Mark that we have an active text box
            setNeedsDisplay(bounds)
            return
        }

        if isResizing {
            isResizing = false
            resizeEdge = .none
            return
        }
        
        if activeHandle != .none {
            endTransform()
            setNeedsDisplay(bounds)
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
            } else if !hasActiveSelection && freeFormPath.count > 2 {
                finalizeFreeFormSelection()
                hasActiveSelection = true  // Mark selection as active
            }
            
        case .rectangleSelect:
            if isMovingSelection {
                isMovingSelection = false
            } else if !hasActiveSelection, let start = shapeStartPoint {
                let rect = rectFromPoints(start, p)
                finalizeRectangleSelection(rect: rect)
                hasActiveSelection = true  // Mark selection as active
                shapeStartPoint = nil
                shapeEndPoint = nil
            }
            
        default: break
        }
        
        setNeedsDisplay(bounds)
    }
    
    // MARK: - Tool Implementations
    
    /// Tool-specific effective stroke size.
    private func getDrawSize() -> CGFloat {
        switch currentTool {
        case .brush: return brushSize * 2.5
        case .eraser: return brushSize * 3
        default: return brushSize
        }
    }
    
    /// Commits the current stroke to the canvas image (with undo support).
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
    
    /// Starts a timer to periodically spray dots around the airbrush location.
    private func startAirbrush() {
        airbrushTimer?.invalidate()
        airbrushTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.sprayAirbrush()
        }
        sprayAirbrush()
    }
    
    /// Applies one "spray" by drawing random dots within a radius around the current location.
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
    
    /// Stops the airbrush timer and saves the current sprayed state to the document.
    private func stopAirbrush() {
        isAirbrushActive = false
        airbrushTimer?.invalidate()
        airbrushTimer = nil
        saveToDocument(actionName: "Airbrush")
    }
    
    // MARK: - Shape Tools
    
    /// Commits a line shape to the canvas image.
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
    
    /// Commits a rectangle/ellipse/rounded-rect shape to the canvas image with the current style.
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
    
    /// First click: establish base line for curve.
    private func handleCurveMouseDown(at point: NSPoint) {
        if curvePhase == 0 {
            shapeStartPoint = point
            shapeEndPoint = point
        }
    }
    
    /// Subsequent clicks: set control points and commit on final phase.
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
    
    /// Draws the final curve using two control points and commits to the canvas.
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
    
    /// Resets curve state machine.
    private func resetCurveState() {
        curvePhase = 0
        curveBaseStart = nil
        curveBaseEnd = nil
        curveControlPoint1 = nil
        shapeStartPoint = nil
        shapeEndPoint = nil
    }
    
    // MARK: - Polygon Tool
    
    /// Closes and commits the polygon using the current shape style.
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
    
    /// Begin moving a captured selection; if this is the first move, clear the original area.
    private func startMovingSelection(at point: NSPoint) {
        guard let rect = selectionRect else { return }
        isMovingSelection = true
        selectionOffset = NSPoint(x: point.x - rect.origin.x, y: point.y - rect.origin.y)
        lastSelectionOrigin = rect.origin
        
        // On first move, clear original area. For free-form, clear only masked area.
        if selectionImage != nil && originalSelectionRect == nil {
            originalSelectionRect = rect
            if let path = selectionPath {
                clearPath(path)
            } else {
                clearRect(rect)
            }
        }
    }
    
    /// Update the selection rect while dragging (and translate path if present).
    private func moveSelection(to point: NSPoint) {
        guard var rect = selectionRect else { return }
        // Rotate the point into selection's local coordinates
        let center = rectCenter(rect)
        let rotatedPoint = rotatePoint(point, around: center, by: -selectionRotation)
        let newOrigin = NSPoint(x: rotatedPoint.x - selectionOffset.x, y: rotatedPoint.y - selectionOffset.y)
        if let oldOrigin = lastSelectionOrigin, let path = selectionPath {
            let dx = newOrigin.x - oldOrigin.x
            let dy = newOrigin.y - oldOrigin.y
            let transform = AffineTransform(translationByX: dx, byY: dy)
            path.transform(using: transform)
            lastSelectionOrigin = newOrigin
        }
        rect.origin = newOrigin
        selectionRect = rect
    }
    
    /// Finalize free-form selection (no combination modes - simple replace).
    private func finalizeFreeFormSelection() {
        guard freeFormPath.count > 2 else {
            freeFormPath = []
            return
        }
        // Build a closed bezier path from points
        let newPath = NSBezierPath()
        newPath.move(to: freeFormPath[0])
        for i in 1..<freeFormPath.count { newPath.line(to: freeFormPath[i]) }
        newPath.close()
        
        // Capture selection from canvas using mask
        selectionPath = newPath.copy() as? NSBezierPath
        let bounds = selectionPath!.bounds
        selectionRect = bounds
        captureSelection(using: selectionPath!)
        lastSelectionOrigin = bounds.origin
        
        freeFormPath = []
    }
    
    /// Finalize rectangle selection (no combination modes - simple replace).
    private func finalizeRectangleSelection(rect: NSRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        
        selectionRect = rect
        selectionPath = nil
        captureSelection()
        lastSelectionOrigin = rect.origin
    }
    
    /// Captures selection using a free-form mask (alpha outside the path).
    private func captureSelection(using path: NSBezierPath) {
        guard let image = canvasImage else { return }
        let bounds = path.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        
        // Create an offscreen bitmap with alpha
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(bounds.width)),
            pixelsHigh: Int(ceil(bounds.height)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        rep.size = bounds.size
        
        NSGraphicsContext.saveGraphicsState()
        if let _ = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            
            // Clear to transparent
            NSColor.clear.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: bounds.size)).fill()
            
            // Clip to translated path and draw image from canvas region
            let translated = path.copy() as! NSBezierPath
            let t = AffineTransform(translationByX: -bounds.origin.x, byY: -bounds.origin.y)
            translated.transform(using: t)
            translated.addClip()
            
            image.draw(in: NSRect(origin: .zero, size: bounds.size),
                       from: bounds,
                       operation: .sourceOver,
                       fraction: 1.0)
        }
        NSGraphicsContext.restoreGraphicsState()
        
        let captured = NSImage(size: bounds.size)
        captured.addRepresentation(rep)
        selectionImage = captured
        selectionRect = bounds
        lastSelectionOrigin = bounds.origin
    }
    
    /// Captures the current selection rect from the canvas image into selectionImage (rectangular).
    private func captureSelection() {
        guard let rect = selectionRect, rect.width > 0, rect.height > 0, let image = canvasImage else { return }
        
        let captured = NSImage(size: rect.size)
        captured.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: rect.size), from: rect, operation: .copy, fraction: 1.0)
        captured.unlockFocus()
        
        selectionImage = captured
        selectionPath = nil
        lastSelectionOrigin = rect.origin
    }
    
    /// Commits the selection image back into the canvas at its current rect.
    private func commitSelection() {
        guard let rect = selectionRect, let selImage = selectionImage, let image = canvasImage else {
            selectionRect = nil
            selectionImage = nil
            originalSelectionRect = nil
            selectionPath = nil
            lastSelectionOrigin = nil
            selectionRotation = 0
            return
        }
        
        let newImage = NSImage(size: canvasSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))
        
        // Apply rotation when committing
        let ctx = NSGraphicsContext.current?.cgContext
        let center = rectCenter(rect)
        ctx?.translateBy(x: center.x, y: center.y)
        ctx?.rotate(by: selectionRotation)
        ctx?.translateBy(x: -center.x, y: -center.y)
        
        selImage.draw(in: rect, from: NSRect(origin: .zero, size: rect.size), operation: .sourceOver, fraction: 1.0)
        newImage.unlockFocus()
        
        canvasImage = newImage
        selectionRect = nil
        selectionImage = nil
        originalSelectionRect = nil
        selectionPath = nil
        lastSelectionOrigin = nil
        selectionRotation = 0
        saveToDocument(actionName: "Move Selection")
    }
    
    /// Clears a rectangular area to white (used when cutting/moving selection).
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
    
    /// Clears a free-form path area to white (used when cutting/moving selection).
    private func clearPath(_ path: NSBezierPath) {
        guard let image = canvasImage else { return }
        let newImage = NSImage(size: canvasSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))
        NSGraphicsContext.current?.saveGraphicsState()
        path.addClip()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        newImage.unlockFocus()
        canvasImage = newImage
    }
    
    // MARK: - Clipboard & Selection Ops
    
    /// Copy selection to NSPasteboard as PNG.
    @objc private func copySelection() {
        guard let selImage = selectionImage,
              let tiff = selImage.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
    }
    
    /// Paste PNG or image from NSPasteboard as a new floating selection at cursor.
    @objc private func pasteFromPasteboard() {
        let pb = NSPasteboard.general
        var pastedImage: NSImage?
        if let data = pb.data(forType: .png), let img = NSImage(data: data) {
            pastedImage = img
        } else if let img = NSImage(pasteboard: pb) {
            pastedImage = img
        }
        guard let img = pastedImage else { return }
        
        // Place centered at last mouse point, clamped to canvas
        let size = img.size
        var origin = NSPoint(x: lastMousePoint.x - size.width / 2,
                             y: lastMousePoint.y - size.height / 2)
        origin.x = max(0, min(origin.x, canvasSize.width - size.width))
        origin.y = max(0, min(origin.y, canvasSize.height - size.height))
        
        selectionImage = img
        selectionRect = NSRect(origin: origin, size: size)
        selectionPath = nil
        originalSelectionRect = nil
        lastSelectionOrigin = origin
        isMovingSelection = false
        hasActiveSelection = true
        setNeedsDisplay(bounds)
    }
    
    /// Delete selection: clear on canvas and drop floating selection.
    @objc private func deleteSelectionAction() {
        guard let rect = selectionRect else { return }
        if let path = selectionPath {
            clearPath(path)
        } else {
            clearRect(rect)
        }
        // Persist deletion
        saveToDocument(actionName: "Delete Selection")
        // Clear floating selection
        selectionRect = nil
        selectionImage = nil
        selectionPath = nil
        originalSelectionRect = nil
        lastSelectionOrigin = nil
        hasActiveSelection = false
        setNeedsDisplay(bounds)
    }
    
    /// Rotate selection 90 degrees CW/CCW.
    @objc private func rotateCWAction() { rotateSelection(clockwise: true) }
    @objc private func rotateCCWAction() { rotateSelection(clockwise: false) }
    
    private func rotateSelection(clockwise: Bool) {
        guard let img = selectionImage, var rect = selectionRect else { return }
        // Rotate image
        let newSize = NSSize(width: rect.height, height: rect.width)
        let rotated = NSImage(size: newSize)
        rotated.lockFocus()
        let transform = NSAffineTransform()
        if clockwise {
            transform.translateX(by: newSize.width, yBy: 0)
            transform.rotate(byDegrees: 90)
        } else {
            transform.translateX(by: 0, yBy: newSize.height)
            transform.rotate(byDegrees: -90)
        }
        transform.concat()
        img.draw(in: NSRect(origin: .zero, size: rect.size))
        rotated.unlockFocus()
        selectionImage = rotated
        
        // Rotate path around its bounds center
        if let path = selectionPath {
            let center = NSPoint(x: rect.midX, y: rect.midY)
            var t = AffineTransform(translationByX: -center.x, byY: -center.y)
            path.transform(using: t)
            t = AffineTransform(rotationByDegrees: clockwise ? 90 : -90)
            path.transform(using: t)
            t = AffineTransform(translationByX: center.x, byY: center.y)
            path.transform(using: t)
            // Update rect to new bounds
            rect = path.bounds
            selectionRect = rect
            lastSelectionOrigin = rect.origin
        } else {
            // Update rect swapping width/height around same center
            let center = NSPoint(x: rect.midX, y: rect.midY)
            rect.size = newSize
            rect.origin = NSPoint(x: center.x - newSize.width/2, y: center.y - newSize.height/2)
            selectionRect = rect
            lastSelectionOrigin = rect.origin
        }
        setNeedsDisplay(bounds)
    }
    
    /// Scale selection up/down.
    @objc private func scaleUpAction() { scaleSelection(by: 2.0) }
    @objc private func scaleDownAction() { scaleSelection(by: 0.5) }
    
    private func scaleSelection(by factor: CGFloat) {
        guard let img = selectionImage, var rect = selectionRect else { return }
        let newSize = NSSize(width: max(1, rect.size.width * factor), height: max(1, rect.size.height * factor))
        // Scale image
        let scaled = NSImage(size: newSize)
        scaled.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: rect.size), operation: .sourceOver, fraction: 1.0)
        scaled.unlockFocus()
        selectionImage = scaled
        
        // Scale path around center
        if let path = selectionPath {
            let center = NSPoint(x: rect.midX, y: rect.midY)
            var t = AffineTransform(translationByX: -center.x, byY: -center.y)
            path.transform(using: t)
            t = AffineTransform(scaleByX: factor, byY: factor)
            path.transform(using: t)
            t = AffineTransform(translationByX: center.x, byY: center.y)
            path.transform(using: t)
            rect = path.bounds
            selectionRect = rect
            lastSelectionOrigin = rect.origin
        } else {
            // Update rect around same center
            let center = NSPoint(x: rect.midX, y: rect.midY)
            rect.size = newSize
            rect.origin = NSPoint(x: center.x - newSize.width/2, y: center.y - newSize.height/2)
            selectionRect = rect
            lastSelectionOrigin = rect.origin
        }
        setNeedsDisplay(bounds)
    }
    
    // MARK: - Selection Handles (resize/rotate)
    
    /// Draws square handles at corners/sides and a rotate handle above the top center.
    private func drawSelectionHandles(_ rect: NSRect, rotation: CGFloat) {
        NSColor.controlAccentColor.setFill()
        for frame in handleFrames(for: rect, rotation: rotation) {
            NSBezierPath(ovalIn: frame).fill()
        }
        // Rotate handle: small circle above top-center with a line
        let rotateFrame = rotateHandleFrame(for: rect, rotation: rotation)
        NSColor.secondaryLabelColor.setStroke()
        let top = rotatePoint(NSPoint(x: rect.midX, y: rect.maxY), around: rectCenter(rect), by: rotation)
        let rotateMid = NSPoint(x: rotateFrame.midX, y: rotateFrame.midY)
        let line = NSBezierPath()
        line.move(to: top)
        line.line(to: rotateMid)
        line.lineWidth = 1
        line.stroke()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: rotateFrame).fill()
    }
    
    private func handleFrames(for rect: NSRect, rotation: CGFloat) -> [NSRect] {
        let s: CGFloat = 8
        let half = s / 2
        let points: [NSPoint] = [
            NSPoint(x: rect.minX, y: rect.maxY), // topLeft
            NSPoint(x: rect.midX, y: rect.maxY), // top
            NSPoint(x: rect.maxX, y: rect.maxY), // topRight
            NSPoint(x: rect.maxX, y: rect.midY), // right
            NSPoint(x: rect.maxX, y: rect.minY), // bottomRight
            NSPoint(x: rect.midX, y: rect.minY), // bottom
            NSPoint(x: rect.minX, y: rect.minY), // bottomLeft
            NSPoint(x: rect.minX, y: rect.midY)  // left
        ]
        let center = rectCenter(rect)
        return points.map {
            let rotated = rotatePoint($0, around: center, by: rotation)
            return NSRect(x: rotated.x - half, y: rotated.y - half, width: s, height: s)
        }
    }
    
    private func rotateHandleFrame(for rect: NSRect, rotation: CGFloat) -> NSRect {
        let s: CGFloat = 10
        let gap: CGFloat = 18
        let center = rectCenter(rect)
        let top = rotatePoint(NSPoint(x: rect.midX, y: rect.maxY + gap), around: center, by: rotation)
        return NSRect(x: top.x - s/2, y: top.y - s/2, width: s, height: s)
    }
    
    private func rotatePoint(_ point: NSPoint, around center: NSPoint, by angle: CGFloat) -> NSPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cosA = cos(angle)
        let sinA = sin(angle)
        return NSPoint(
            x: center.x + dx * cosA - dy * sinA,
            y: center.y + dx * sinA + dy * cosA
        )
    }
    
    /// Which selection handle is at a given point.
    private func handleAt(_ point: NSPoint, in rect: NSRect) -> SelectionHandle {
        // Try all handles with rotation
        let rotation = selectionRotation
        let frames = handleFrames(for: rect, rotation: rotation)
        let names: [SelectionHandle] = [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]
        for (i, f) in frames.enumerated() where f.contains(point) {
            return names[i]
        }
        if rotateHandleFrame(for: rect, rotation: rotation).contains(point) { return .rotate }
        return .none
    }
    
    /// Begin a transform gesture on the floating selection.
    private func beginTransform(handle: SelectionHandle, at point: NSPoint) {
        guard let rect = selectionRect else { return }
        activeHandle = handle
        transformStartRect = rect
        transformOriginalImage = selectionImage
        transformOriginalPath = selectionPath?.copy() as? NSBezierPath
        if handle == .rotate {
            let center = rectCenter(rect)
            transformStartRotation = selectionRotation
            transformStartAngle = atan2(point.y - center.y, point.x - center.x) - selectionRotation
        }
    }
    
    /// Update transform during drag.
    private func updateTransform(to point: NSPoint) {
        guard let startRect = transformStartRect, let originalImage = transformOriginalImage else { return }
        
        switch activeHandle {
        case .rotate:
            let center = rectCenter(startRect)
            let angleNow = atan2(point.y - center.y, point.x - center.x)
            selectionRotation = angleNow - transformStartAngle
            setNeedsDisplay(bounds)
        case .topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left:
            var newRect = startRect
            // Adjust rect edges based on handle
            switch activeHandle {
            case .topLeft:
                newRect.origin.x = min(point.x, startRect.maxX - 1)
                newRect.size.width = max(1, startRect.maxX - newRect.origin.x)
                newRect.size.height = max(1, point.y - startRect.minY)
            case .top:
                newRect.size.height = max(1, point.y - startRect.minY)
            case .topRight:
                newRect.size.width = max(1, point.x - startRect.minX)
                newRect.size.height = max(1, point.y - startRect.minY)
            case .right:
                newRect.size.width = max(1, point.x - startRect.minX)
            case .bottomRight:
                newRect.size.width = max(1, point.x - startRect.minX)
                newRect.origin.y = min(point.y, startRect.maxY - 1)
                newRect.size.height = max(1, startRect.maxY - newRect.origin.y)
            case .bottom:
                newRect.origin.y = min(point.y, startRect.maxY - 1)
                newRect.size.height = max(1, startRect.maxY - newRect.origin.y)
            case .bottomLeft:
                newRect.origin.x = min(point.x, startRect.maxX - 1)
                newRect.size.width = max(1, startRect.maxX - newRect.origin.x)
                newRect.origin.y = min(point.y, startRect.maxY - 1)
                newRect.size.height = max(1, startRect.maxY - newRect.origin.y)
            case .left:
                newRect.origin.x = min(point.x, startRect.maxX - 1)
                newRect.size.width = max(1, startRect.maxX - newRect.origin.x)
            default: break
            }
            // Clamp within canvas
            newRect.origin.x = max(0, min(newRect.origin.x, canvasSize.width - newRect.size.width))
            newRect.origin.y = max(0, min(newRect.origin.y, canvasSize.height - newRect.size.height))
            // Scale image from original to newRect size
            let scaled = NSImage(size: newRect.size)
            scaled.lockFocus()
            originalImage.draw(in: NSRect(origin: .zero, size: newRect.size), from: NSRect(origin: .zero, size: startRect.size), operation: .sourceOver, fraction: 1.0)
            scaled.unlockFocus()
            selectionImage = scaled
            // Scale path if present around center
            if let basePath = transformOriginalPath?.copy() as? NSBezierPath {
                let sx = newRect.size.width / startRect.size.width
                let sy = newRect.size.height / startRect.size.height
                let center = NSPoint(x: startRect.midX, y: startRect.midY)
                let path = basePath
                var aff = AffineTransform(translationByX: -center.x, byY: -center.y)
                path.transform(using: aff)
                aff = AffineTransform(scaleByX: sx, byY: sy)
                path.transform(using: aff)
                aff = AffineTransform(translationByX: center.x, byY: center.y)
                path.transform(using: aff)
                // Also translate if origin moved
                let delta = NSPoint(x: newRect.midX - startRect.midX, y: newRect.midY - startRect.midY)
                aff = AffineTransform(translationByX: delta.x, byY: delta.y)
                path.transform(using: aff)
                selectionPath = path
            }
            selectionRect = newRect
            lastSelectionOrigin = newRect.origin
            
        case .none:
            break
        }
    }
    
    /// End transform gesture.
    private func endTransform() {
        activeHandle = .none
        transformStartRect = nil
        transformOriginalImage = nil
        transformOriginalPath = nil
        transformStartAngle = 0
        transformStartRotation = 0
    }
    
    // MARK: - Color Picker & Fill
    
    /// Reads the pixel color at the given point and updates the foreground color.
    private func pickColor(at point: NSPoint) {
        guard let image = canvasImage,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return }
        
        // Map view point (in points) to bitmap pixel coordinates
        let scaleX = CGFloat(bitmap.pixelsWide) / image.size.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / image.size.height
        
        let px = Int((point.x * scaleX).rounded(.down))
        let py = Int(((canvasSize.height - point.y) * scaleY).rounded(.down))
        
        guard px >= 0, px < bitmap.pixelsWide, py >= 0, py < bitmap.pixelsHigh,
              let color = bitmap.colorAt(x: px, y: py) else { return }
        
        delegate?.colorPicked(color)
        
        // Switch back to the tool we had before entering the picker
        if let previous = previousToolBeforePicker {
            previousToolBeforePicker = nil
            DispatchQueue.main.async {
                ToolPaletteState.shared.currentTool = previous
            }
        }
    }
    
    /// Flood fill using direct pixel buffer manipulation for reliability and performance.
    /// Uses scanline algorithm with tolerance-based edge detection.
    private func floodFill(at point: NSPoint) {
        guard let image = canvasImage else { return }
        
        // Create a fresh bitmap at exact canvas size (1:1 pixel mapping)
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)
        
        guard width > 0, height > 0 else { return }
        
        // Create a new bitmap representation with known format: 32-bit RGBA
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
            // Fill with white first (in case image has transparency)
            NSColor.white.setFill()
            NSRect(origin: .zero, size: canvasSize).fill()
            // Draw the image
            image.draw(in: NSRect(origin: .zero, size: canvasSize),
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .sourceOver,
                       fraction: 1.0)
        }
        NSGraphicsContext.restoreGraphicsState()
        
        // Get direct access to pixel buffer
        guard let pixelData = bitmap.bitmapData else { return }
        
        // Convert click point to pixel coordinates
        // Note: NSView coordinates have origin at bottom-left, bitmap at top-left
        let clickX = Int(point.x)
        let clickY = height - 1 - Int(point.y)  // Flip Y coordinate
        
        guard clickX >= 0, clickX < width, clickY >= 0, clickY < height else { return }
        
        // Get target color at click point (RGBA)
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
        let tolerance: Int = 32  // Allow some tolerance for anti-aliased edges
        if colorMatchesRGB(targetR, targetG, targetB, fillR, fillG, fillB, tolerance: 1) {
            return
        }
        
        // Scanline flood fill algorithm - more efficient than simple stack
        var visited = [Bool](repeating: false, count: width * height)
        var stack: [(Int, Int)] = [(clickX, clickY)]
        
        // Helper to check if pixel matches target color within tolerance
        func matchesTarget(_ x: Int, _ y: Int) -> Bool {
            let offset = (y * width + x) * 4
            let r = pixelData[offset]
            let g = pixelData[offset + 1]
            let b = pixelData[offset + 2]
            return colorMatchesRGB(r, g, b, targetR, targetG, targetB, tolerance: tolerance)
        }
        
        // Helper to set pixel color
        func setPixel(_ x: Int, _ y: Int) {
            let offset = (y * width + x) * 4
            pixelData[offset] = fillR
            pixelData[offset + 1] = fillG
            pixelData[offset + 2] = fillB
            pixelData[offset + 3] = 255  // Full opacity
        }
        
        // Scanline fill
        while !stack.isEmpty {
            let (seedX, seedY) = stack.removeLast()
            
            // Skip if already visited or out of bounds
            if seedY < 0 || seedY >= height { continue }
            let idx = seedY * width + seedX
            if visited[idx] { continue }
            
            // Find left edge of this scanline segment
            var leftX = seedX
            while leftX > 0 && matchesTarget(leftX - 1, seedY) && !visited[seedY * width + leftX - 1] {
                leftX -= 1
            }
            
            // Find right edge of this scanline segment
            var rightX = seedX
            while rightX < width - 1 && matchesTarget(rightX + 1, seedY) && !visited[seedY * width + rightX + 1] {
                rightX += 1
            }
            
            // Fill this scanline segment and mark as visited
            var aboveAdded = false
            var belowAdded = false
            
            for x in leftX...rightX {
                let currentIdx = seedY * width + x
                if visited[currentIdx] { continue }
                if !matchesTarget(x, seedY) { continue }
                
                visited[currentIdx] = true
                setPixel(x, seedY)
                
                // Check pixel above
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
                
                // Check pixel below
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
        
        // Create new image from modified bitmap
        bitmap.size = canvasSize
        let newImage = NSImage(size: canvasSize)
        newImage.addRepresentation(bitmap)
        canvasImage = newImage
        saveToDocument(actionName: "Fill")
        setNeedsDisplay(bounds)
    }
    
    /// Compare two RGB colors within a tolerance (0-255 scale).
    private func colorMatchesRGB(_ r1: UInt8, _ g1: UInt8, _ b1: UInt8,
                                  _ r2: UInt8, _ g2: UInt8, _ b2: UInt8,
                                  tolerance: Int) -> Bool {
        let dr = abs(Int(r1) - Int(r2))
        let dg = abs(Int(g1) - Int(g2))
        let db = abs(Int(b1) - Int(b2))
        return dr <= tolerance && dg <= tolerance && db <= tolerance
    }
    
    // MARK: - Magnifier
    
    /// Zooms in or out by doubling/halving the zoom level via shared state.
    private func handleMagnifier(at point: NSPoint, zoomIn: Bool) {
        let state = ToolPaletteState.shared
        if zoomIn {
            state.zoomLevel = min(8, state.zoomLevel * 2)
        } else {
            state.zoomLevel = max(1, state.zoomLevel / 2)
        }
    }
    
    // MARK: - Text Tool
    
    /// Places an NSTextField at the click point for inline text entry.
    private func handleTextTool(at point: NSPoint) {
        if let tf = textField {
            commitText()
            tf.removeFromSuperview()
            textField = nil
        }
        
        textInsertPoint = point
        
        // Build the font with style attributes
        let state = ToolPaletteState.shared
        let font = NSFont(name: state.fontName, size: state.fontSize) ?? NSFont.systemFont(ofSize: state.fontSize)
        
        let tf = NSTextField(frame: NSRect(x: point.x, y: point.y - state.fontSize - 4, width: 300, height: state.fontSize + 8))
        tf.isBordered = true
        tf.backgroundColor = .white
        tf.font = font
        tf.textColor = currentColor
        tf.target = self
        tf.action = #selector(textFieldEntered(_:))
        tf.focusRingType = .none
        tf.lineBreakMode = .byWordWrapping
        tf.usesSingleLineMode = false
        tf.cell?.wraps = true
        tf.cell?.isScrollable = false
        addSubview(tf)
        tf.becomeFirstResponder()
        textField = tf
        hasActiveTextBox = true
    }

    /// Called when the user presses Return in the text field; commits text to image.
    @objc private func textFieldEntered(_ sender: NSTextField) {
        commitText()
        sender.removeFromSuperview()
        textField = nil
        hasActiveTextBox = false
    }

    /// Renders the text field's contents into the canvas image at the insertion point.
    private func commitText() {
        guard let tf = textField, let image = canvasImage else { return }
        let rect = tf.frame
        let text = tf.stringValue
        guard !text.isEmpty else { return }

        let newImage = NSImage(size: canvasSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))

        // Use the text field's font and color
        var attrs: [NSAttributedString.Key: Any] = [
            .font: tf.font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: tf.textColor ?? NSColor.black
        ]
        let state = ToolPaletteState.shared
        if state.isUnderlined {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        let attrString = NSAttributedString(string: text, attributes: attrs)
        attrString.draw(in: rect)
        newImage.unlockFocus()
        canvasImage = newImage
        textInsertPoint = nil
        saveToDocument(actionName: "Text")
    }

    /// Renders the contents of an NSTextField to an NSImage.
    private func renderTextFieldToImage(_ tf: NSTextField) -> NSImage {
        tf.sizeToFit()
        var frame = tf.frame
        frame.size.width = max(frame.size.width, tf.intrinsicContentSize.width)
        frame.size.height = tf.intrinsicContentSize.height
        tf.frame = frame

        let size = tf.frame.size
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrString = NSAttributedString(string: tf.stringValue, attributes: [
            .font: tf.font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: tf.textColor ?? NSColor.black
        ])
        attrString.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        return image
    }
    
    // MARK: - Canvas Resize Handling
    
    /// Responds to dragging on canvas resize handles by requesting a new canvas size.
    private func handleResizeDrag(to point: NSPoint) {
        var newSize = canvasSize
        
        switch resizeEdge {
        case .right:
            newSize.width = max(50, point.x)
        case .bottom:
            newSize.height = max(50, resizeStartSize.height + (resizeStartSize.height - point.y))
        case .corner:
            newSize.width = max(50, point.x)
            newSize.height = max(50, resizeStartSize.height + (resizeStartSize.height - point.y))
        case .none:
            return
        }
        
        delegate?.requestCanvasResize(newSize)
    }
    
    // MARK: - Helpers
    
    /// Clamp a point to the canvas bounds.
    private func clamp(_ point: NSPoint) -> NSPoint {
        NSPoint(x: max(0, min(point.x, canvasSize.width)), y: max(0, min(point.y, canvasSize.height)))
    }

    /// Returns the center point of a rect.
    private func rectCenter(_ rect: NSRect) -> NSPoint {
        NSPoint(x: rect.midX, y: rect.midY)
    }
    
    /// Construct a rect from two corner points.
    private func rectFromPoints(_ p1: NSPoint, _ p2: NSPoint) -> NSRect {
        NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
               width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }
    
    /// Constrain to square/circle or 45-degree line when holding Shift.
    private func constrainedPoint(from start: NSPoint, to end: NSPoint) -> NSPoint {
        let dx = abs(end.x - start.x)
        let dy = abs(end.y - start.y)
        let d = max(dx, dy)
        return NSPoint(x: start.x + d * (end.x > start.x ? 1 : -1),
                       y: start.y + d * (end.y > start.y ? 1 : -1))
    }
    
    /// Clears shape preview state.
    private func resetShapeState() {
        shapeStartPoint = nil
        shapeEndPoint = nil
    }
    
    /// Serializes the current canvas image as PNG and saves to the document.
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