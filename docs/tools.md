# Tool Reference

This document describes each of the 16 tools in Splatr, including their behavior, implementation details, and keyboard shortcuts.

---

## Tool Overview

| Tool | Shortcut | Category | Description |
|------|----------|----------|-------------|
| Free-Form Select | `S` | Selection | Lasso selection |
| Rectangle Select | `Shift+S` | Selection | Rectangular selection |
| Eraser | `E` | Drawing | Erases to white |
| Fill | `G` | Drawing | Flood fill |
| Color Picker | `I` | Utility | Eyedropper |
| Magnifier | `Z` | Utility | Zoom control |
| Pencil | `P` | Drawing | 1px freehand |
| Brush | `B` | Drawing | Variable-width freehand |
| Airbrush | `A` | Drawing | Spray effect |
| Text | `T` | Drawing | Text insertion |
| Line | `L` | Shape | Straight lines |
| Curve | `C` | Shape | Bezier curves |
| Rectangle | `R` | Shape | Rectangles |
| Polygon | `Y` | Shape | Multi-sided shapes |
| Ellipse | `O` | Shape | Circles and ovals |
| Rounded Rectangle | `Shift+R` | Shape | Rounded corners |

---

## Selection Tools

### Free-Form Select (Lasso)

**Shortcut:** `S`

**Behavior:**
1. Click and drag to draw a freehand selection outline
2. Release to close the path and capture the selection
3. The selected area becomes a "floating selection"
4. Click inside to move; use handles to resize/rotate
5. Press ESC to commit the selection back to the canvas

**Implementation:** `CanvasNSView+Selection.swift`

The free-form path is collected in `freeFormPath` during drag. On mouse up, `finalizeFreeFormSelection()` creates an `NSBezierPath`, captures the masked pixels using alpha compositing, and stores them in `selectionImage`.

**State Variables:**
- `freeFormPath: [NSPoint]` - Points during drawing
- `selectionPath: NSBezierPath?` - The closed path
- `selectionImage: NSImage?` - Captured pixels
- `selectionRect: NSRect?` - Bounding box

### Rectangle Select

**Shortcut:** `Shift+S`

**Behavior:**
1. Click and drag to define a rectangular selection
2. Release to capture the selection
3. Same move/resize/rotate behavior as free-form
4. Press ESC to commit

**Implementation:** `CanvasNSView+Selection.swift`

Uses `shapeStartPoint` and `shapeEndPoint` during drag. On mouse up, `finalizeRectangleSelection()` captures the rectangular area.

**Modifier Keys:**
- None currently (could add Shift for square constraint)

### Common Selection Features

Both selection tools support:

**Moving:** Click inside the selection and drag.

**Resizing:** Drag the 8 handles around the selection.

**Rotating:** Drag the circular handle above the selection.

**Context Menu:**
- Copy
- Paste
- Delete
- Rotate 90° CW/CCW
- Scale 200%/50%

**Keyboard:**
- `ESC` - Commit selection

**Modal Behavior:** Once a selection exists, clicking outside it does nothing. The user must press ESC to commit before starting a new selection. This prevents accidental loss of selections.

---

## Drawing Tools

### Eraser

**Shortcut:** `E`

**Behavior:**
1. Click and drag to erase
2. Erases to white (the canvas background color)
3. Size is 3x the brush size setting

**Implementation:** `CanvasNSView+Drawing.swift`

Uses the same stroke rendering as pencil/brush but with `NSColor.white` as the drawing color.

**Options:**
- Size: 2, 4, 6, 8 (selectable in tool palette)

### Fill (Paint Bucket)

**Shortcut:** `G`

**Behavior:**
1. Click on a colored region
2. All connected pixels of similar color are filled with the foreground color
3. "Similar" is defined by a tolerance value (currently 32/255 per channel)

**Implementation:** `CanvasNSView+Fill.swift`

The flood fill uses a scanline algorithm:
1. Create a fresh 32-bit RGBA bitmap
2. Draw the canvas into the bitmap
3. Sample the target color at the click point
4. For each pixel, scan left and right to find the extent of the matching region
5. Fill the entire horizontal span
6. Add seeds for rows above and below at transition points
7. Repeat until stack is empty

**Technical Details:**
- Coordinate system: Y is flipped (view origin bottom-left, bitmap top-left)
- Tolerance: 32 per channel (allows for anti-aliased edges)
- Self-fill check: Tolerance of 1 to avoid no-op fills

### Pencil

**Shortcut:** `P`

**Behavior:**
1. Click and drag to draw
2. Always 1px line width (uses base `brushSize`)
3. Sharp, pixel-precise lines

**Implementation:** `CanvasNSView+Drawing.swift`

Points are collected in `currentPath` with interpolation for smooth curves. On mouse up, `commitStroke()` renders the path.

### Brush

**Shortcut:** `B`

**Behavior:**
1. Click and drag to draw
2. Variable width based on brush size setting
3. Effective size is `brushSize * 2.5`
4. Round line caps and joins for smooth appearance

**Implementation:** `CanvasNSView+Drawing.swift`

Same as pencil but with larger stroke width. The brush shape setting (circle, square, slash) is defined but not yet fully implemented in rendering.

**Options:**
- Size: 2-20 (slider in tool palette)
- Shape: Circle, Square, Slash Right, Slash Left

### Airbrush

**Shortcut:** `A`

**Behavior:**
1. Click and hold to spray
2. Continuous spray while mouse is down
3. Moving the mouse moves the spray center
4. Density increases with brush size

**Implementation:** `CanvasNSView+Drawing.swift`

A `Timer` fires every 0.04 seconds while the mouse is down. Each tick, `sprayAirbrush()` draws random dots within a radius of `brushSize * 2` around the current mouse position.

**Options:**
- Size: 2, 4, 6, 8 (selectable in tool palette)

### Text

**Shortcut:** `T`

**Behavior:**
1. Click and drag to define text box size
2. An editable text field appears
3. Type to enter text
4. Press Return to commit, or ESC to commit and close
5. Can move/resize the text box before committing

**Implementation:** `CanvasNSView+Text.swift`

Creates an actual `NSTextField` as a subview. This provides native text editing, cursor behavior, and selection. On commit, the text is rendered into the canvas using `NSAttributedString.draw()`.

**Options (in Text Options palette):**
- Font: Curated list of system fonts
- Size: 8-96 (with stepper for custom values)
- Style: Bold, Italic, Underline

---

## Shape Tools

### Line

**Shortcut:** `L`

**Behavior:**
1. Click to set start point
2. Drag to set end point
3. Release to commit the line

**Implementation:** `CanvasNSView+Shapes.swift`

Uses `shapeStartPoint` and `shapeEndPoint`. Preview is drawn in `drawShapePreview()`.

**Modifier Keys:**
- `Shift` - Constrain to 45° angles (via `constrainedPoint()`)

**Options:**
- Width: 1, 2, 3, 4, 5 px

### Curve

**Shortcut:** `C`

**Behavior:**
1. Click and drag to define the base line
2. Click to set first control point
3. Click to set second control point (commits the curve)

**Implementation:** `CanvasNSView+Shapes.swift`

A three-phase state machine:
- Phase 0: Drawing base line (like Line tool)
- Phase 1: Waiting for first control point
- Phase 2: Waiting for second control point

The curve is a cubic Bezier using `NSBezierPath.curve(to:controlPoint1:controlPoint2:)`.

**Options:**
- Width: 1, 2, 3, 4, 5 px

### Rectangle

**Shortcut:** `R`

**Behavior:**
1. Click to set one corner
2. Drag to set opposite corner
3. Release to commit

**Implementation:** `CanvasNSView+Shapes.swift`

Uses `rectFromPoints()` to create the rect regardless of drag direction.

**Modifier Keys:**
- `Shift` - Constrain to square

**Options:**
- Style: Outline, Filled with outline, Filled (no outline)

### Polygon

**Shortcut:** `Y`

**Behavior:**
1. Click to place first vertex
2. Click to place additional vertices
3. Double-click to close and commit

**Implementation:** `CanvasNSView+Shapes.swift`

Points accumulate in `polygonPoints`. The preview shows the polygon with a line to the current mouse position. Double-click triggers `commitPolygon()`.

**Options:**
- Style: Outline, Filled with outline, Filled (no outline)

### Ellipse

**Shortcut:** `O`

**Behavior:**
1. Click to set one corner of bounding box
2. Drag to set opposite corner
3. Release to commit

**Implementation:** `CanvasNSView+Shapes.swift`

Uses `NSBezierPath(ovalIn:)` with the rect from the drag.

**Modifier Keys:**
- `Shift` - Constrain to circle

**Options:**
- Style: Outline, Filled with outline, Filled (no outline)

### Rounded Rectangle

**Shortcut:** `Shift+R`

**Behavior:**
1. Click to set one corner
2. Drag to set opposite corner
3. Release to commit

**Implementation:** `CanvasNSView+Shapes.swift`

Uses `NSBezierPath(roundedRect:xRadius:yRadius:)`. Corner radius is automatically calculated as 25% of the smaller dimension.

**Options:**
- Style: Outline, Filled with outline, Filled (no outline)

---

## Utility Tools

### Color Picker (Eyedropper)

**Shortcut:** `I`

**Behavior:**
1. Click on any pixel
2. That pixel's color becomes the foreground color
3. Automatically switches back to the previous tool

**Implementation:** `CanvasNSView+Fill.swift`

Samples the pixel using `NSBitmapImageRep.colorAt(x:y:)` after converting coordinates. Updates `ToolPaletteState.shared.foregroundColor`.

The `previousToolBeforePicker` property stores what tool was active before switching to the picker, enabling automatic return.

### Magnifier

**Shortcut:** `Z`

**Behavior:**
1. Click to zoom in (double the zoom level)
2. Option+Click to zoom out (halve the zoom level)
3. Zoom range: 1x to 8x

**Implementation:** `CanvasNSView+Fill.swift`

Simply modifies `ToolPaletteState.shared.zoomLevel`. The actual zoom is applied in `ContentView` via a scale transform on the canvas container.

**Options (in tool palette):**
- Preset levels: 1x, 2x, 4x, 6x, 8x

---

## Shape Styles

All shape tools (Rectangle, Ellipse, Rounded Rectangle, Polygon) support three fill styles:

### Outline

Strokes the shape with the foreground color. Interior is transparent (shows canvas beneath).

```swift
case .outline:
    currentColor.setStroke()
    path.stroke()
```

### Filled with Outline

Fills with the background color, strokes with the foreground color.

```swift
case .filledWithOutline:
    NSColor(ToolPaletteState.shared.backgroundColor).setFill()
    path.fill()
    currentColor.setStroke()
    path.stroke()
```

### Filled (No Outline)

Fills with the foreground color. No stroke.

```swift
case .filledNoOutline:
    currentColor.setFill()
    path.fill()
```

---

## Adding a New Tool

To add a new tool to Splatr:

1. **Define the tool** in `Model/Tool.swift`:
```swift
case myNewTool = "My New Tool"

var icon: String {
    case .myNewTool: return "sf.symbol.name"
}

var shortcut: String {
    case .myNewTool: return "X"
}
```

2. **Add state** (if needed) to `CanvasNSView.swift`:
```swift
var myToolState: SomeType = defaultValue
```

3. **Update the tool palette** in `ToolPaletteView.swift`:
```swift
let toolRows: [[Tool]] = [
    // ... add to appropriate row
]
```

4. **Add tool options** (if needed) in `toolOptionsView`:
```swift
case .myNewTool:
    VStack {
        // Tool-specific controls
    }
```

5. **Handle mouse events** in `CanvasNSView+Mouse.swift`:
```swift
// In mouseDown:
case .myNewTool:
    startMyTool(at: p)

// In mouseDragged:
case .myNewTool:
    updateMyTool(to: p)

// In mouseUp:
case .myNewTool:
    commitMyTool()
```

6. **Implement tool logic** in appropriate extension file (or create new one):
```swift
extension CanvasNSView {
    func startMyTool(at point: NSPoint) { }
    func updateMyTool(to point: NSPoint) { }
    func commitMyTool() { }
}
```

7. **Add preview drawing** (if needed) in `CanvasNSView.swift`:
```swift
func drawMyToolPreview() {
    // Draw in-progress state
}

// Call from draw():
drawMyToolPreview()
```

8. **Add keyboard shortcut** in `ContentView.swift`:
```swift
case "x":
    state.currentTool = .myNewTool
```