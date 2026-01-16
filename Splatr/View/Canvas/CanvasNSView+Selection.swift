//
//  CanvasNSView+Selection.swift
//  Splatr
//
//  Created by Kushagra Srivastava on 1/16/26.
//

import AppKit

// MARK: - Selection Tools (Rectangle Select, Free-form Select, Transforms)

extension CanvasNSView {
    
    // MARK: - Selection Movement
    
    /// Begin moving a captured selection; if this is the first move, clear the original area.
    func startMovingSelection(at point: NSPoint) {
        guard let rect = selectionRect else { return }
        isMovingSelection = true
        selectionOffset = NSPoint(x: point.x - rect.origin.x, y: point.y - rect.origin.y)
        lastSelectionOrigin = rect.origin
        
        if selectionImage != nil && originalSelectionRect == nil {
            originalSelectionRect = rect
            if let path = selectionPath {
                clearPath(path)
            } else {
                clearRect(rect)
            }
        }
    }
    
    /// Update the selection rect while dragging.
    func moveSelection(to point: NSPoint) {
        guard var rect = selectionRect else { return }
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
    
    // MARK: - Selection Finalization
    
    /// Finalize free-form selection.
    func finalizeFreeFormSelection() {
        guard freeFormPath.count > 2 else {
            freeFormPath = []
            return
        }
        let newPath = NSBezierPath()
        newPath.move(to: freeFormPath[0])
        for i in 1..<freeFormPath.count { newPath.line(to: freeFormPath[i]) }
        newPath.close()
        
        selectionPath = newPath.copy() as? NSBezierPath
        let bounds = selectionPath!.bounds
        selectionRect = bounds
        captureSelectionWithPath(selectionPath!)
        lastSelectionOrigin = bounds.origin
        
        freeFormPath = []
    }
    
    /// Finalize rectangle selection.
    func finalizeRectangleSelection(rect: NSRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        
        selectionRect = rect
        selectionPath = nil
        captureSelection()
        lastSelectionOrigin = rect.origin
    }
    
    // MARK: - Selection Capture
    
    /// Captures selection using a free-form mask.
    func captureSelectionWithPath(_ path: NSBezierPath) {
        guard let image = canvasImage else { return }
        let bounds = path.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        
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
            
            NSColor.clear.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: bounds.size)).fill()
            
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
    
    /// Captures rectangular selection from the canvas.
    func captureSelection() {
        guard let rect = selectionRect, rect.width > 0, rect.height > 0, let image = canvasImage else { return }
        
        let captured = NSImage(size: rect.size)
        captured.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: rect.size), from: rect, operation: .copy, fraction: 1.0)
        captured.unlockFocus()
        
        selectionImage = captured
        selectionPath = nil
        lastSelectionOrigin = rect.origin
    }
    
    /// Commits the selection image back into the canvas.
    func commitSelection() {
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
    
    // MARK: - Clear Operations
    
    /// Clears a rectangular area to white.
    func clearRect(_ rect: NSRect) {
        guard let image = canvasImage else { return }
        
        let newImage = NSImage(size: canvasSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))
        NSColor.white.setFill()
        rect.fill()
        newImage.unlockFocus()
        
        canvasImage = newImage
    }
    
    /// Clears a free-form path area to white.
    func clearPath(_ path: NSBezierPath) {
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
    
    // MARK: - Clipboard Operations
    
    /// Copy selection to NSPasteboard as PNG.
    @objc func copySelection() {
        guard let selImage = selectionImage,
              let tiff = selImage.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
    }
    
    /// Paste from NSPasteboard as a new floating selection.
    @objc func pasteFromPasteboard() {
        let pb = NSPasteboard.general
        var pastedImage: NSImage?
        if let data = pb.data(forType: .png), let img = NSImage(data: data) {
            pastedImage = img
        } else if let img = NSImage(pasteboard: pb) {
            pastedImage = img
        }
        guard let img = pastedImage else { return }
        
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
    
    /// Delete selection.
    @objc func deleteSelectionAction() {
        guard let rect = selectionRect else { return }
        if let path = selectionPath {
            clearPath(path)
        } else {
            clearRect(rect)
        }
        saveToDocument(actionName: "Delete Selection")
        selectionRect = nil
        selectionImage = nil
        selectionPath = nil
        originalSelectionRect = nil
        lastSelectionOrigin = nil
        hasActiveSelection = false
        setNeedsDisplay(bounds)
    }
    
    // MARK: - Rotation & Scaling
    
    @objc func rotateCWAction() { rotateSelection(clockwise: true) }
    @objc func rotateCCWAction() { rotateSelection(clockwise: false) }
    
    func rotateSelection(clockwise: Bool) {
        guard let img = selectionImage, var rect = selectionRect else { return }
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
        
        if let path = selectionPath {
            let center = NSPoint(x: rect.midX, y: rect.midY)
            var t = AffineTransform(translationByX: -center.x, byY: -center.y)
            path.transform(using: t)
            t = AffineTransform(rotationByDegrees: clockwise ? 90 : -90)
            path.transform(using: t)
            t = AffineTransform(translationByX: center.x, byY: center.y)
            path.transform(using: t)
            rect = path.bounds
            selectionRect = rect
            lastSelectionOrigin = rect.origin
        } else {
            let center = NSPoint(x: rect.midX, y: rect.midY)
            rect.size = newSize
            rect.origin = NSPoint(x: center.x - newSize.width/2, y: center.y - newSize.height/2)
            selectionRect = rect
            lastSelectionOrigin = rect.origin
        }
        setNeedsDisplay(bounds)
    }
    
    @objc func scaleUpAction() { scaleSelection(by: 2.0) }
    @objc func scaleDownAction() { scaleSelection(by: 0.5) }
    
    func scaleSelection(by factor: CGFloat) {
        guard let img = selectionImage, var rect = selectionRect else { return }
        let newSize = NSSize(width: max(1, rect.size.width * factor), height: max(1, rect.size.height * factor))
        let scaled = NSImage(size: newSize)
        scaled.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: rect.size), operation: .sourceOver, fraction: 1.0)
        scaled.unlockFocus()
        selectionImage = scaled
        
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
            let center = NSPoint(x: rect.midX, y: rect.midY)
            rect.size = newSize
            rect.origin = NSPoint(x: center.x - newSize.width/2, y: center.y - newSize.height/2)
            selectionRect = rect
            lastSelectionOrigin = rect.origin
        }
        setNeedsDisplay(bounds)
    }
    
    // MARK: - Selection Handles
    
    /// Draws handles at corners/sides and a rotate handle.
    func drawSelectionHandles(_ rect: NSRect, rotation: CGFloat) {
        NSColor.controlAccentColor.setFill()
        for frame in handleFrames(for: rect, rotation: rotation) {
            NSBezierPath(ovalIn: frame).fill()
        }
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
    
    func handleFrames(for rect: NSRect, rotation: CGFloat) -> [NSRect] {
        let s: CGFloat = 8
        let half = s / 2
        let points: [NSPoint] = [
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.midX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.midY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.midX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.midY)
        ]
        let center = rectCenter(rect)
        return points.map {
            let rotated = rotatePoint($0, around: center, by: rotation)
            return NSRect(x: rotated.x - half, y: rotated.y - half, width: s, height: s)
        }
    }
    
    func rotateHandleFrame(for rect: NSRect, rotation: CGFloat) -> NSRect {
        let s: CGFloat = 10
        let gap: CGFloat = 18
        let center = rectCenter(rect)
        let top = rotatePoint(NSPoint(x: rect.midX, y: rect.maxY + gap), around: center, by: rotation)
        return NSRect(x: top.x - s/2, y: top.y - s/2, width: s, height: s)
    }
    
    /// Which selection handle is at a given point.
    func handleAt(_ point: NSPoint, in rect: NSRect) -> SelectionHandle {
        let rotation = selectionRotation
        let frames = handleFrames(for: rect, rotation: rotation)
        let names: [SelectionHandle] = [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]
        for (i, f) in frames.enumerated() where f.contains(point) {
            return names[i]
        }
        if rotateHandleFrame(for: rect, rotation: rotation).contains(point) { return .rotate }
        return .none
    }
    
    // MARK: - Transform Operations
    
    /// Begin a transform gesture.
    func beginTransform(handle: SelectionHandle, at point: NSPoint) {
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
    func updateTransform(to point: NSPoint) {
        guard let startRect = transformStartRect, let originalImage = transformOriginalImage else { return }
        
        switch activeHandle {
        case .rotate:
            let center = rectCenter(startRect)
            let angleNow = atan2(point.y - center.y, point.x - center.x)
            selectionRotation = angleNow - transformStartAngle
            setNeedsDisplay(bounds)
        case .topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left:
            var newRect = startRect
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
            newRect.origin.x = max(0, min(newRect.origin.x, canvasSize.width - newRect.size.width))
            newRect.origin.y = max(0, min(newRect.origin.y, canvasSize.height - newRect.size.height))
            let scaled = NSImage(size: newRect.size)
            scaled.lockFocus()
            originalImage.draw(in: NSRect(origin: .zero, size: newRect.size), from: NSRect(origin: .zero, size: startRect.size), operation: .sourceOver, fraction: 1.0)
            scaled.unlockFocus()
            selectionImage = scaled
            if let basePath = transformOriginalPath?.copy() as? NSBezierPath {
                let sx = newRect.size.width / startRect.size.width
                let sy = newRect.size.height / startRect.size.height
                let center = NSPoint(x: startRect.midX, y: startRect.midY)
                var aff = AffineTransform(translationByX: -center.x, byY: -center.y)
                basePath.transform(using: aff)
                aff = AffineTransform(scaleByX: sx, byY: sy)
                basePath.transform(using: aff)
                aff = AffineTransform(translationByX: center.x, byY: center.y)
                basePath.transform(using: aff)
                let delta = NSPoint(x: newRect.midX - startRect.midX, y: newRect.midY - startRect.midY)
                aff = AffineTransform(translationByX: delta.x, byY: delta.y)
                basePath.transform(using: aff)
                selectionPath = basePath
            }
            selectionRect = newRect
            lastSelectionOrigin = newRect.origin
        case .none:
            break
        }
    }
    
    /// End transform gesture.
    func endTransform() {
        activeHandle = .none
        transformStartRect = nil
        transformOriginalImage = nil
        transformOriginalPath = nil
        transformStartAngle = 0
        transformStartRotation = 0
    }
    
    // MARK: - Context Menu & Keyboard
    
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
}
