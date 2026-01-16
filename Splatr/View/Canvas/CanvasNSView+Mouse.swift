//
//  CanvasNSView+Mouse.swift
//  Splatr
//
//  Created by Kushagra Srivastava on 1/16/26.
//

import AppKit

// MARK: - Mouse Event Handling

extension CanvasNSView {
    
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
    
    /// Switch cursor when hovering over resize handles; otherwise show crosshair.
    func updateCursor(at point: NSPoint) {
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
    func resizeEdgeAt(_ point: NSPoint) -> ResizeEdge {
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
            if hasActiveTextBox {
                if let tf = textField {
                    let tfRect = tf.frame
                    let handle = handleAt(lastMousePoint, in: tfRect)
                    if handle != .none || tfRect.contains(lastMousePoint) {
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
                        if handle != .none {
                            beginTransform(handle: handle, at: lastMousePoint)
                        } else {
                            startMovingSelection(at: lastMousePoint)
                        }
                        setNeedsDisplay(bounds)
                        return
                    }
                    return
                }
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
                    return
                }
            }
            textBoxStart = clamp(point)
            textBoxEnd = clamp(point)
            isDraggingTextBox = true
            setNeedsDisplay(bounds)
            return
        }

        // Text field handle/rect logic for non-text tools
        if let tf = textField {
            let tfRect = tf.frame
            let handle = handleAt(lastMousePoint, in: tfRect)
            if handle != .none || tfRect.contains(lastMousePoint) {
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
                if handle != .none {
                    beginTransform(handle: handle, at: lastMousePoint)
                } else {
                    startMovingSelection(at: lastMousePoint)
                }
                setNeedsDisplay(bounds)
                return
            }
        }

        // Canvas resize handles
        if showResizeHandles {
            resizeEdge = resizeEdgeAt(point)
            if resizeEdge != .none {
                isResizing = true
                resizeStartSize = canvasSize
                return
            }
        }
        
        // Selection transform handles
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
                }
            } else {
                freeFormPath = [p]
                isMovingSelection = false
            }
            
        case .rectangleSelect:
            if hasActiveSelection {
                if let rect = selectionRect {
                    let handle = handleAt(p, in: rect)
                    if handle != .none {
                        beginTransform(handle: handle, at: p)
                    } else if rect.contains(p) {
                        startMovingSelection(at: p)
                    }
                }
            } else {
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
        
        if activeHandle != .none {
            updateTransform(to: lastMousePoint)
            setNeedsDisplay(bounds)
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
            if rect.width < 10 || rect.height < 10 {
                textBoxStart = nil
                textBoxEnd = nil
                setNeedsDisplay(bounds)
                return
            }
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
            hasActiveTextBox = true
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
                hasActiveSelection = true
            }
            
        case .rectangleSelect:
            if isMovingSelection {
                isMovingSelection = false
            } else if !hasActiveSelection, let start = shapeStartPoint {
                let rect = rectFromPoints(start, p)
                finalizeRectangleSelection(rect: rect)
                hasActiveSelection = true
                shapeStartPoint = nil
                shapeEndPoint = nil
            }
            
        default: break
        }
        
        setNeedsDisplay(bounds)
    }
    
    /// Responds to dragging on canvas resize handles.
    func handleResizeDrag(to point: NSPoint) {
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
}
