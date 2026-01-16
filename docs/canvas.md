# Canvas Internals

This document provides an exhaustive reference for the `CanvasNSView` class and its extensions. It is intended for developers working directly on canvas functionality.

---

## File Overview

| File | Lines | Purpose |
|------|-------|---------|
| `CanvasView.swift` | ~120 | SwiftUI wrapper and Coordinator |
| `CanvasNSView.swift` | ~280 | Core class, properties, drawing |
| `CanvasNSView+Mouse.swift` | ~280 | Input handling |
| `CanvasNSView+Drawing.swift` | ~100 | Freehand tools |
| `CanvasNSView+Shapes.swift` | ~150 | Shape tools |
| `CanvasNSView+Selection.swift` | ~350 | Selection system |
| `CanvasNSView+Text.swift` | ~90 | Text tool |
| `CanvasNSView+Fill.swift` | ~150 | Fill and picker |
| `CanvasNSView+Helpers.swift` | ~60 | Utilities |

---

## CanvasNSView Properties Reference

### Canvas State

```swift
var canvasImage: NSImage?
```
The backing store for all canvas content. All drawing operations modify this image. It is the single source of truth for what appears on the canvas.

```swift
var canvasSize: CGSize
```
The dimensions of the canvas in points. This may differ from `canvasImage.size` temporarily during resize operations.

```swift
var documentDataHash: Int
```
Hash of the last saved PNG data. Used to detect external changes (undo/redo) by comparing against the current document data hash.

### Tool State

```swift
var currentColor: NSColor
```
The foreground color for drawing operations. Set from `ToolPaletteState.foregroundColor` during `updateNSView()`.

```swift
var brushSize: CGFloat
```
Base size for brush-based tools. Interpreted differently per tool (see `getDrawSize()`).

```swift
var currentTool: Tool
```
The currently selected tool. Determines behavior in mouse event handlers.

```swift
var previousToolBeforePicker: Tool?
```
When switching to the color picker tool, this stores the previous tool so we can switch back after picking a color.

```swift
var showResizeHandles: Bool
```
Whether to display and respond to canvas resize handles on the right and bottom edges.

### Drawing State

```swift
var currentPath: [NSPoint]
```
Array of points for the in-progress stroke (pencil, brush, eraser). Cleared after commit.

```swift
var lastPoint: NSPoint?
```
The most recent point in the current stroke. Used for interpolation during fast mouse movement.

### Shape State

```swift
var shapeStartPoint: NSPoint?
var shapeEndPoint: NSPoint?
```
Anchor and current points for shape tools (line, rectangle, ellipse, rounded rectangle).

```swift
var curveBaseStart: NSPoint?
var curveBaseEnd: NSPoint?
var curveControlPoint1: NSPoint?
var curvePhase: Int
```
State machine for the curve tool. Phase 0: drawing base line. Phase 1: first control point. Phase 2: second control point (commits).

```swift
var polygonPoints: [NSPoint]
```
Accumulated vertices for the polygon tool. Double-click closes and commits.

### Selection State

```swift
var selectionRect: NSRect?
```
Bounding rectangle of the current selection. For free-form selections, this is the bounds of `selectionPath`.

```swift
var selectionImage: NSImage?
```
The captured pixels within the selection. Created when the user first moves the selection.

```swift
var originalSelectionRect: NSRect?
```
The rect where the selection was captured from. Used to prevent re-clearing on subsequent moves.

```swift
var selectionPath: NSBezierPath?
```
For free-form selections, the actual path outline. Nil for rectangular selections.

```swift
var selectionOffset: NSPoint
```
Offset from the mouse position to the selection origin. Used for smooth dragging.

```swift
var lastSelectionOrigin: NSPoint?
```
Previous origin point. Used to calculate delta for path translation.

```swift
var hasActiveSelection: Bool
```
Flag indicating a selection exists and is in "locked" mode. When true, clicking outside the selection does not start a new selection (user must press ESC first).

```swift
var selectionRotation: CGFloat
```
Rotation angle of the selection in radians. Applied during drawing via context transform.

```swift
var isMovingSelection: Bool
```
Flag indicating the selection is currently being dragged.

```swift
var freeFormPath: [NSPoint]
```
Points collected during free-form selection drawing (before closure).

### Transform State

```swift
enum SelectionHandle {
    case none, topLeft, top, topRight, right, 
         bottomRight, bottom, bottomLeft, left, rotate
}

var activeHandle: SelectionHandle
```
Which handle is currently being dragged, if any.

```swift
var transformStartRect: NSRect?
var transformOriginalImage: NSImage?
var transformOriginalPath: NSBezierPath?
```
Captured at the start of a transform operation. Used to compute deltas and allow smooth scaling.

```swift
var transformStartAngle: CGFloat
var transformStartRotation: CGFloat
```
For rotation transforms: the initial angle and the selection's rotation when the gesture began.

```swift
var lastMousePoint: NSPoint
```
Most recent mouse position in canvas coordinates. Used for cursor updates and context menu placement.

### Text State

```swift
var textField: NSTextField?
```
The active text field when using the text tool. Nil when no text is being edited.

```swift
var textInsertPoint: NSPoint?
```
Where the text will be rendered when committed.

```swift
var hasActiveTextBox: Bool
```
Similar to `hasActiveSelection` but for the text tool. When true, clicking outside doesn't create a new text box.

```swift
var textBoxStart: NSPoint?
var textBoxEnd: NSPoint?
var isDraggingTextBox: Bool
```
State for drag-to-create text box gesture.

```swift
var lastTextString: String?
```
Captured text content when converting a text field to a floating selection (for transform).

### Resize State

```swift
enum ResizeEdge {
    case none, right, bottom, corner
}

var isResizing: Bool
var resizeEdge: ResizeEdge
var resizeStartSize: CGSize
let handleSize: CGFloat = 8
```
State for canvas resize drag operations.

### Airbrush State

```swift
var airbrushTimer: Timer?
var airbrushLocation: NSPoint
var isAirbrushActive: Bool
```
The airbrush uses a timer to continuously spray dots while the mouse is held down.

---

## Method Reference by File

### CanvasNSView.swift

#### Document Loading

```swift
func reloadFromDocument(data: Data, size: CGSize, notifyNavigator: Bool = true)
```
Reloads the canvas from document data. This is the **only** way to set canvas content from outside. Called on initial load and when undo/redo changes the document.

Parameters:
- `data`: PNG-encoded image data (may be empty for new documents)
- `size`: Target canvas size
- `notifyNavigator`: Whether to update the navigator thumbnail

```swift
func createBlankCanvas()
```
Creates a white-filled image at `canvasSize`. Called when document data is empty.

#### Drawing

```swift
override func draw(_ dirtyRect: NSRect)
```
Main draw method. Draws in order:
1. White background fill
2. `canvasImage` (the persistent bitmap)
3. Preview layers (stroke, shape, selection)
4. Resize handles (if enabled)

```swift
func drawCurrentStroke()
```
Renders the in-progress stroke from `currentPath`. Shows what the user will see before committing.

```swift
func drawShapePreview()
```
Renders in-progress shapes (line, rectangle, ellipse, rounded rectangle) using `shapeStartPoint` and `shapeEndPoint`.

```swift
func drawCurvePreview()
```
Renders the curve at its current phase. Phase 0 shows a straight line; phases 1-2 show the bezier curve with current control points.

```swift
func drawPolygonPreview()
```
Renders the polygon outline including the line to the current mouse position.

```swift
func drawSelection()
```
Renders:
- In-progress free-form selection path
- Selection image (if captured) with rotation
- Marching ants (animated dashed border)
- Selection handles
- Text box preview (if dragging)
- Text field handles (if active)

```swift
func drawResizeHandles()
```
Renders the three canvas resize handles (right edge, bottom edge, corner).

```swift
func drawStyledShape(_ path: NSBezierPath, lineWidth: CGFloat)
```
Applies the current `shapeStyle` (outline, filled with outline, filled) to a shape path.

---

### CanvasNSView+Mouse.swift

#### Tracking

```swift
override func updateTrackingAreas()
```
Installs a tracking area covering the entire view to receive `mouseMoved` events.

```swift
override func cursorUpdate(with event: NSEvent)
override func mouseMoved(with event: NSEvent)
```
Update the cursor based on position (resize handles, selection handles, etc.).

```swift
func updateCursor(at point: NSPoint)
```
Determines and sets the appropriate cursor for the given position.

```swift
func resizeEdgeAt(_ point: NSPoint) -> ResizeEdge
```
Hit-tests the canvas resize handles.

#### Mouse Events

```swift
override func mouseDown(with event: NSEvent)
```
Routes to tool-specific handling. Also handles:
- Committing active text/selection when switching tools
- Text tool modal behavior
- Resize handle initiation
- Selection transform handle initiation

```swift
override func mouseDragged(with event: NSEvent)
```
Updates in-progress operations:
- Stroke path accumulation (with interpolation)
- Shape endpoint updates
- Selection movement
- Transform updates
- Resize drag

```swift
override func mouseUp(with event: NSEvent)
```
Commits operations:
- Stroke commit
- Shape commit
- Selection finalization
- Text box creation

```swift
func handleResizeDrag(to point: NSPoint)
```
Calculates new canvas size based on drag position and requests resize via coordinator.

---

### CanvasNSView+Drawing.swift

```swift
func getDrawSize() -> CGFloat
```
Returns the effective stroke size for the current tool:
- Brush: `brushSize * 2.5`
- Eraser: `brushSize * 3`
- Others: `brushSize`

```swift
func commitStroke()
```
Renders `currentPath` into `canvasImage` and saves with undo.

```swift
func startAirbrush()
```
Starts a repeating timer (0.04s interval) that calls `sprayAirbrush()`.

```swift
func sprayAirbrush()
```
Draws random dots within a radius around `airbrushLocation`. Density is proportional to `brushSize`.

```swift
func stopAirbrush()
```
Invalidates the timer and saves the result.

---

### CanvasNSView+Shapes.swift

```swift
func commitLine()
```
Draws a line from `shapeStartPoint` to `shapeEndPoint` into the canvas.

```swift
func commitShape()
```
Draws rectangle/ellipse/rounded rectangle based on `currentTool`. Applies `shapeStyle`.

```swift
func handleCurveMouseDown(at point: NSPoint)
```
Phase 0: Sets start and end points for the base line.

```swift
func handleCurveMouseUp(at point: NSPoint)
```
Advances the curve state machine:
- Phase 0 → 1: Captures base line, waits for first control point
- Phase 1 → 2: Captures first control point
- Phase 2: Commits with second control point

```swift
func commitCurve(controlPoint2: NSPoint)
```
Draws the final bezier curve and resets state.

```swift
func resetCurveState()
```
Resets all curve-related properties to initial values.

```swift
func commitPolygon()
```
Closes and fills/strokes the polygon path.

```swift
func resetShapeState()
```
Clears `shapeStartPoint` and `shapeEndPoint`.

---

### CanvasNSView+Selection.swift

#### Movement

```swift
func startMovingSelection(at point: NSPoint)
```
Initiates selection movement. On first move, clears the original area.

```swift
func moveSelection(to point: NSPoint)
```
Updates `selectionRect` and transforms `selectionPath` if present.

#### Finalization

```swift
func finalizeFreeFormSelection()
```
Creates a closed path from `freeFormPath`, captures the masked area.

```swift
func finalizeRectangleSelection(rect: NSRect)
```
Captures the rectangular area.

#### Capture

```swift
func captureSelectionWithPath(_ path: NSBezierPath)
```
Creates an image containing only the pixels inside the path (with alpha outside).

```swift
func captureSelection()
```
Creates an image containing the pixels inside `selectionRect`.

```swift
func commitSelection()
```
Composites `selectionImage` back into `canvasImage` at current position/rotation.

#### Clearing

```swift
func clearRect(_ rect: NSRect)
func clearPath(_ path: NSBezierPath)
```
Fill areas with white (used when moving selection away from original position).

#### Clipboard

```swift
@objc func copySelection()
```
Copies `selectionImage` to the system pasteboard as PNG.

```swift
@objc func pasteFromPasteboard()
```
Creates a floating selection from pasteboard content, centered at last mouse position.

```swift
@objc func deleteSelectionAction()
```
Clears the selection area and removes the floating selection.

#### Transforms

```swift
@objc func rotateCWAction()
@objc func rotateCCWAction()
func rotateSelection(clockwise: Bool)
```
Rotates the selection image and path by 90 degrees.

```swift
@objc func scaleUpAction()
@objc func scaleDownAction()
func scaleSelection(by factor: CGFloat)
```
Scales the selection by the given factor.

#### Handles

```swift
func drawSelectionHandles(_ rect: NSRect, rotation: CGFloat)
```
Draws the 8 resize handles plus the rotation handle.

```swift
func handleFrames(for rect: NSRect, rotation: CGFloat) -> [NSRect]
```
Returns the hit-test rects for the 8 resize handles.

```swift
func rotateHandleFrame(for rect: NSRect, rotation: CGFloat) -> NSRect
```
Returns the hit-test rect for the rotation handle.

```swift
func handleAt(_ point: NSPoint, in rect: NSRect) -> SelectionHandle
```
Hit-tests which handle (if any) is at the given point.

#### Transform Gestures

```swift
func beginTransform(handle: SelectionHandle, at point: NSPoint)
```
Captures initial state for a transform operation.

```swift
func updateTransform(to point: NSPoint)
```
Updates the selection based on which handle is being dragged.

```swift
func endTransform()
```
Clears transform state.

#### Input Overrides

```swift
override func menu(for event: NSEvent) -> NSMenu?
```
Returns a context menu with selection operations.

```swift
override func keyDown(with event: NSEvent)
```
Handles ESC key to commit selection/text.

---

### CanvasNSView+Text.swift

```swift
func handleTextTool(at point: NSPoint)
```
Creates an `NSTextField` at the click position.

```swift
@objc func textFieldEntered(_ sender: NSTextField)
```
Called when user presses Return. Commits and removes the text field.

```swift
func commitText()
```
Renders the text field content into `canvasImage`.

```swift
func renderTextFieldToImage(_ tf: NSTextField) -> NSImage
```
Creates an image from a text field (used when converting to floating selection).

---

### CanvasNSView+Fill.swift

```swift
func pickColor(at point: NSPoint)
```
Samples the pixel color at the given point and updates the foreground color.

```swift
func floodFill(at point: NSPoint)
```
Performs scanline flood fill starting at the clicked point.

Implementation details:
1. Creates a fresh 32-bit RGBA bitmap at canvas dimensions
2. Draws the canvas into this controlled bitmap
3. Samples the target color at the (Y-flipped) click point
4. Uses scanline algorithm to fill connected pixels within tolerance
5. Creates new NSImage from modified bitmap

```swift
func colorMatchesRGB(_ r1: UInt8, _ g1: UInt8, _ b1: UInt8,
                     _ r2: UInt8, _ g2: UInt8, _ b2: UInt8,
                     tolerance: Int) -> Bool
```
Compares two colors with per-channel tolerance.

```swift
func handleMagnifier(at point: NSPoint, zoomIn: Bool)
```
Adjusts `ToolPaletteState.shared.zoomLevel`.

---

### CanvasNSView+Helpers.swift

```swift
override var acceptsFirstResponder: Bool { true }
```
Allows the view to receive keyboard events.

```swift
override var intrinsicContentSize: NSSize
```
Returns canvas size plus handle area (for Auto Layout).

```swift
func clamp(_ point: NSPoint) -> NSPoint
```
Constrains a point to canvas bounds.

```swift
func rectCenter(_ rect: NSRect) -> NSPoint
```
Returns the center point of a rect.

```swift
func rectFromPoints(_ p1: NSPoint, _ p2: NSPoint) -> NSRect
```
Creates a rect from two corner points (handles any ordering).

```swift
func constrainedPoint(from start: NSPoint, to end: NSPoint) -> NSPoint
```
Constrains the endpoint to create a square/circle (Shift key behavior).

```swift
func rotatePoint(_ point: NSPoint, around center: NSPoint, by angle: CGFloat) -> NSPoint
```
Rotates a point around a center by the given angle (radians).

```swift
func saveToDocument(actionName: String?)
```
Converts `canvasImage` to PNG and saves via the coordinator. Registers undo if `actionName` is provided.

---

## Common Patterns

### Adding a Drawing Operation

```swift
func commitMyOperation() {
    guard let image = canvasImage else { return }
    
    let newImage = NSImage(size: canvasSize)
    newImage.lockFocus()
    
    // Draw existing content
    image.draw(in: NSRect(origin: .zero, size: canvasSize))
    
    // Draw new content
    currentColor.setStroke()
    // ... drawing code ...
    
    newImage.unlockFocus()
    canvasImage = newImage
    
    // Save with undo support
    saveToDocument(actionName: "My Operation")
}
```

### Adding a New Tool State

1. Add property to `CanvasNSView`:
```swift
var myToolState: SomeType = defaultValue
```

2. Reset in appropriate places (e.g., `resetShapeState()` equivalent)

3. Handle in `mouseDown`/`mouseDragged`/`mouseUp`

4. Draw preview in `draw()` or dedicated preview method

### Handling Coordinate Transformation

For operations requiring pixel access:
```swift
// NSView point → bitmap pixel
let bitmapX = Int(viewPoint.x)
let bitmapY = bitmapHeight - 1 - Int(viewPoint.y)

// With scaling (for non-1:1 bitmaps)
let scaleX = CGFloat(bitmap.pixelsWide) / canvasSize.width
let scaleY = CGFloat(bitmap.pixelsHigh) / canvasSize.height
let bitmapX = Int((viewPoint.x * scaleX).rounded(.down))
let bitmapY = Int(((canvasSize.height - viewPoint.y) * scaleY).rounded(.down))
```