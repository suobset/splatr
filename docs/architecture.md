# Splatr Architecture

This document provides a deep technical dive into Splatr's architecture, intended for developers who need to understand the system at a detailed level.

## Table of Contents

1. [System Overview](#system-overview)
2. [The Document Model](#the-document-model)
3. [The Canvas System](#the-canvas-system)
4. [State Management](#state-management)
5. [The Palette System](#the-palette-system)
6. [Coordinate Systems](#coordinate-systems)
7. [Image Pipeline](#image-pipeline)
8. [Undo/Redo System](#undoredo-system)
9. [Event Flow](#event-flow)

---

## System Overview

Splatr is structured as a document-based macOS application using SwiftUI's `DocumentGroup` for window management and lifecycle, with an AppKit `NSView` subclass for the actual canvas rendering.

### Why This Hybrid Approach?

SwiftUI excels at:
- Declarative UI composition
- State observation and binding
- Document lifecycle management
- Cross-window state sharing

AppKit excels at:
- Low-level event handling
- Direct pixel manipulation
- Custom cursor management
- Embedding native controls (NSTextField for text tool)

By combining both, Splatr achieves a modern, maintainable codebase while retaining the precise control needed for a bitmap editor.

---

## The Document Model

### splatrDocument

```swift
struct splatrDocument: FileDocument {
    var canvasData: Data
    var canvasSize: CGSize
    
    static var readableContentTypes: [UTType] { [.splatr, .png, .jpeg, ...] }
    static var writableContentTypes: [UTType] { [.splatr] }
}
```

### Data Representation

The canvas is stored as PNG-encoded `Data`. This choice provides:
- Lossless compression
- Alpha channel support
- Wide compatibility
- Reasonable file sizes

When the document is saved:
1. `CanvasNSView.canvasImage` is converted to TIFF representation
2. TIFF is converted to PNG via `NSBitmapImageRep`
3. PNG data is written to the file wrapper

When the document is loaded:
1. Data is read from the file
2. `NSImage(data:)` reconstructs the image
3. Image is drawn into the canvas at `canvasSize` dimensions

### File Format Detection

The document supports opening multiple formats:

```swift
init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
        throw CocoaError(.fileReadCorruptFile)
    }
    
    if let image = NSImage(data: data) {
        canvasData = data
        canvasSize = image.size
    } else {
        // Handle format-specific loading
    }
}
```

### The .splatr Format

Currently, `.splatr` files are PNG images with a custom Uniform Type Identifier (UTI). The UTI is declared in `Info.plist`:

```xml
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.skushagra.splatr</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.image</string>
        </array>
    </dict>
</array>
```

Future versions may embed additional metadata (layers, history) using PNG ancillary chunks or a container format.

---

## The Canvas System

The canvas is the heart of Splatr. It consists of three main components:

### CanvasView (NSViewRepresentable)

This SwiftUI view wraps the AppKit canvas:

```swift
struct CanvasView: NSViewRepresentable {
    @Binding var document: splatrDocument
    var currentColor: NSColor
    var brushSize: CGFloat
    var currentTool: Tool
    var showResizeHandles: Bool
    var onCanvasResize: (CGSize) -> Void
    var onCanvasUpdate: (NSImage) -> Void
    
    @Environment(\.undoManager) var undoManager
}
```

Key responsibilities:
- Create the `CanvasNSView` instance
- Propagate state changes from SwiftUI to AppKit
- Detect external document changes (undo/redo) and reload

### Coordinator

The Coordinator bridges AppKit callbacks to SwiftUI:

```swift
class Coordinator {
    var document: Binding<splatrDocument>
    var undoManager: UndoManager?
    var onCanvasResize: (CGSize) -> Void
    var onCanvasUpdate: (NSImage) -> Void
    
    func saveWithUndo(newData: Data, image: NSImage, actionName: String)
    func saveToDocument(_ data: Data, image: NSImage)
    func colorPicked(_ color: NSColor)
    func requestCanvasResize(_ size: CGSize)
}
```

The Coordinator is held weakly by `CanvasNSView` via the `delegate` property.

### CanvasNSView

The actual `NSView` subclass that handles all drawing and interaction. It is split across multiple files:

| File | Responsibility |
|------|----------------|
| `CanvasNSView.swift` | Class definition, properties, `draw()`, preview rendering |
| `CanvasNSView+Mouse.swift` | Mouse events, cursor updates |
| `CanvasNSView+Drawing.swift` | Pencil, brush, eraser, airbrush |
| `CanvasNSView+Shapes.swift` | Line, rectangle, ellipse, curve, polygon |
| `CanvasNSView+Selection.swift` | Selection tools, transforms, clipboard |
| `CanvasNSView+Text.swift` | Text tool |
| `CanvasNSView+Fill.swift` | Flood fill, color picker |
| `CanvasNSView+Helpers.swift` | Utility functions |

### The Drawing Cycle

```
User Input (mouse/keyboard)
         │
         ▼
┌─────────────────────┐
│ Modify transient    │ ← currentPath, shapeEndPoint, selectionRect
│ state               │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ setNeedsDisplay()   │ ← Request redraw
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ draw(_ dirtyRect)   │ ← System calls this
├─────────────────────┤
│ 1. Draw white bg    │
│ 2. Draw canvasImage │
│ 3. Draw previews    │ ← Stroke preview, shape preview, selection
│ 4. Draw handles     │
└──────────┬──────────┘
           │
           ▼
      [Display]
```

### Committing Changes

When a drawing operation completes (mouse up), the transient state is "committed" to the canvas:

```swift
func commitStroke() {
    guard currentPath.count > 0, let image = canvasImage else { return }
    
    // Create new image
    let newImage = NSImage(size: canvasSize)
    newImage.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: canvasSize))
    
    // Draw the stroke
    // ...
    
    newImage.unlockFocus()
    canvasImage = newImage
    
    // Save to document with undo
    saveToDocument(actionName: "Draw")
}
```

---

## State Management

### ToolPaletteState

A singleton `ObservableObject` that holds all tool-related state:

```swift
class ToolPaletteState: ObservableObject {
    static let shared = ToolPaletteState()
    
    // Tool selection
    @Published var currentTool: Tool = .pencil
    
    // Drawing properties
    @Published var brushSize: CGFloat = 4.0
    @Published var lineWidth: CGFloat = 1.0
    @Published var shapeStyle: ShapeStyle = .outline
    @Published var brushShape: BrushShape = .circle
    
    // Colors
    @Published var foregroundColor: Color = .black
    @Published var backgroundColor: Color = .white
    @Published var customColors: [Color] = []
    
    // Text properties
    @Published var fontName: String = "Helvetica"
    @Published var fontSize: CGFloat = 24
    @Published var isBold: Bool = false
    @Published var isItalic: Bool = false
    @Published var isUnderlined: Bool = false
    
    // View state
    @Published var navigatorImage: NSImage?
    @Published var zoomLevel: CGFloat = 1.0
}
```

### State Flow

```
┌─────────────────────┐
│ ToolPaletteState    │ ← Singleton
│ (ObservableObject)  │
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     │           │
     ▼           ▼
┌─────────┐ ┌─────────────┐
│ SwiftUI │ │ ContentView │
│ Palettes│ │             │
└─────────┘ └──────┬──────┘
                   │
                   ▼
            ┌─────────────┐
            │ CanvasView  │
            │ (props)     │
            └──────┬──────┘
                   │
                   ▼ updateNSView()
            ┌─────────────┐
            │CanvasNSView │
            │ (properties)│
            └─────────────┘
```

SwiftUI views observe `ToolPaletteState` directly via `@ObservedObject`. The `CanvasNSView` receives values as plain properties, set during `updateNSView()`:

```swift
func updateNSView(_ nsView: CanvasNSView, context: Context) {
    nsView.currentColor = currentColor
    nsView.brushSize = brushSize
    nsView.currentTool = currentTool
    // ...
}
```

### Why Not Pass the ObservableObject to CanvasNSView?

`NSView` doesn't natively support Combine observation. While we could add KVO or notification-based observation, passing values through `updateNSView()` is simpler and ensures the view hierarchy controls when updates happen.

---

## The Palette System

### ToolPaletteController

Manages floating `NSPanel` windows for palettes:

```swift
class ToolPaletteController {
    static let shared = ToolPaletteController()
    
    private var toolPaletteWindow: NSPanel?
    private var colorPaletteWindow: NSPanel?
    private var navigatorWindow: NSPanel?
    private var textOptionsWindow: NSPanel?
    private var customColorsWindow: NSPanel?
    
    private var toolPaletteVisible = true
    // ... visibility flags for each
}
```

### Panel Configuration

Palettes use `NSPanel` with specific style masks:

```swift
let panel = NSPanel(
    contentRect: rect,
    styleMask: [
        .titled,           // Has title bar
        .closable,         // Has close button
        .utilityWindow,    // Utility window appearance
        .nonactivatingPanel // Doesn't activate app when clicked
    ],
    backing: .buffered,
    defer: false
)
panel.isFloatingPanel = true          // Floats above regular windows
panel.becomesKeyOnlyIfNeeded = true   // Focus stays on canvas
panel.hidesOnDeactivate = true        // Hides when app loses focus
panel.collectionBehavior = [
    .canJoinAllSpaces,                // Appears on all spaces
    .fullScreenAuxiliary              // Follows into full screen
]
```

### SwiftUI in NSPanel

Palettes host SwiftUI views via `NSHostingView`:

```swift
panel.contentView = NSHostingView(rootView: ToolPaletteView())
```

This allows the palette UI to be written in SwiftUI while retaining NSPanel's floating behavior.

---

## Coordinate Systems

Understanding coordinate systems is critical for bitmap operations.

### NSView Coordinates

- Origin: **Bottom-left**
- Y-axis: **Increases upward**
- Units: **Points** (may differ from pixels on Retina)

### NSBitmapImageRep Coordinates

- Origin: **Top-left**
- Y-axis: **Increases downward**
- Units: **Pixels**

### Conversion

When mapping a click point to a pixel:

```swift
// NSView point to bitmap pixel
let clickX = Int(point.x)
let clickY = height - 1 - Int(point.y)  // Flip Y
```

When the bitmap has different dimensions than the view (e.g., Retina):

```swift
let scaleX = CGFloat(bitmap.pixelsWide) / image.size.width
let scaleY = CGFloat(bitmap.pixelsHigh) / image.size.height
let px = Int((point.x * scaleX).rounded(.down))
let py = Int(((canvasSize.height - point.y) * scaleY).rounded(.down))
```

### Selection Rotation

Selection rotation adds complexity. When a selection is rotated:

1. The `selectionRotation` angle is stored in radians
2. During drawing, the graphics context is rotated around the selection center
3. Mouse coordinates must be inverse-rotated for hit testing:

```swift
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
```

---

## Image Pipeline

### Creating a New Canvas

```swift
func createBlankCanvas() {
    let image = NSImage(size: canvasSize)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: canvasSize).fill()
    image.unlockFocus()
    canvasImage = image
}
```

### Modifying the Canvas

All modifications follow this pattern:

```swift
func commitSomeOperation() {
    guard let image = canvasImage else { return }
    
    let newImage = NSImage(size: canvasSize)
    newImage.lockFocus()
    
    // Draw existing content
    image.draw(in: NSRect(origin: .zero, size: canvasSize))
    
    // Draw new content
    // ...
    
    newImage.unlockFocus()
    canvasImage = newImage
    saveToDocument(actionName: "Operation Name")
}
```

### Saving to Document

```swift
func saveToDocument(actionName: String?) {
    guard let image = canvasImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else { return }
    
    documentDataHash = pngData.hashValue
    
    if let name = actionName {
        delegate?.saveWithUndo(newData: pngData, image: image, actionName: name)
    } else {
        delegate?.saveToDocument(pngData, image: image)
    }
}
```

### Direct Pixel Access (Flood Fill)

For operations requiring pixel-level access:

```swift
// Create controlled bitmap
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,      // RGBA
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: width * 4,
    bitsPerPixel: 32
)

// Draw image into bitmap
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(...)

// Access raw pixels
let pixelData = bitmap.bitmapData!
let offset = (y * width + x) * 4
let r = pixelData[offset]
let g = pixelData[offset + 1]
let b = pixelData[offset + 2]
let a = pixelData[offset + 3]
```

---

## Undo/Redo System

### Integration with SwiftUI

SwiftUI's `DocumentGroup` provides an `UndoManager` via the environment. The Coordinator captures this:

```swift
@Environment(\.undoManager) var undoManager

func makeCoordinator() -> Coordinator {
    Coordinator(document: $document, undoManager: undoManager, ...)
}
```

### Registering Undo Actions

```swift
func saveWithUndo(newData: Data, image: NSImage, actionName: String) {
    guard let undoManager = undoManager else {
        saveToDocument(newData, image: image)
        return
    }
    
    let oldData = document.wrappedValue.canvasData
    guard oldData != newData else { return }
    
    undoManager.registerUndo(withTarget: self) { target in
        target.document.wrappedValue.canvasData = oldData
        if let img = NSImage(data: oldData) {
            target.onCanvasUpdate(img)
        }
    }
    undoManager.setActionName(actionName)
    
    document.wrappedValue.canvasData = newData
    onCanvasUpdate(image)
}
```

### Detecting External Changes

When the user triggers undo/redo, the document changes but `CanvasNSView` isn't directly notified. We detect this via hash comparison:

```swift
func updateNSView(_ nsView: CanvasNSView, context: Context) {
    if nsView.documentDataHash != document.canvasData.hashValue {
        nsView.reloadFromDocument(data: document.canvasData, size: document.canvasSize)
    }
}
```

---

## Event Flow

### Complete Flow: Drawing a Line

```
1. User clicks canvas
   └─▶ mouseDown(with:) in CanvasNSView+Mouse.swift
       └─▶ currentTool == .line
           └─▶ shapeStartPoint = point
               shapeEndPoint = point
               setNeedsDisplay(bounds)

2. System calls draw()
   └─▶ draw(_ dirtyRect) in CanvasNSView.swift
       └─▶ drawShapePreview()
           └─▶ Draws line from shapeStartPoint to shapeEndPoint

3. User drags mouse
   └─▶ mouseDragged(with:)
       └─▶ shapeEndPoint = newPoint
           setNeedsDisplay(bounds)
   └─▶ draw() called again, preview updates

4. User releases mouse
   └─▶ mouseUp(with:)
       └─▶ currentTool == .line
           └─▶ commitLine() in CanvasNSView+Shapes.swift
               ├─▶ Create newImage
               ├─▶ Draw canvasImage into newImage
               ├─▶ Draw line into newImage
               ├─▶ canvasImage = newImage
               ├─▶ resetShapeState()
               └─▶ saveToDocument(actionName: "Line")
                   └─▶ delegate?.saveWithUndo(...)
                       ├─▶ Register undo action
                       ├─▶ document.canvasData = pngData
                       └─▶ onCanvasUpdate(image)
                           └─▶ ToolPaletteState.shared.navigatorImage = image
```

### Complete Flow: Changing Tools

```
1. User clicks tool button in ToolPaletteView
   └─▶ state.currentTool = .brush

2. @Published triggers SwiftUI update
   └─▶ ContentView body re-evaluated
       └─▶ CanvasView initialized with new currentTool

3. SwiftUI calls updateNSView
   └─▶ nsView.currentTool = currentTool

4. CanvasNSView now uses .brush for subsequent mouse events
```

---

## Performance Considerations

### Redraw Optimization

`setNeedsDisplay()` marks the view as needing redraw but doesn't immediately redraw. The system coalesces multiple calls into a single draw pass.

For large canvases, consider using `setNeedsDisplay(_:)` with a specific rect to limit redraw area.

### Image Memory

Each `NSImage` operation (lock/unlock focus) may create image representations. For memory-intensive operations:

1. Prefer direct `NSBitmapImageRep` manipulation
2. Release intermediate images promptly
3. Consider downsampling for preview operations

### Flood Fill Performance

The scanline algorithm is O(n) where n is the number of filled pixels. For very large fills:

1. The algorithm processes horizontal spans, reducing stack operations
2. The visited array prevents redundant checks
3. Direct pixel buffer access avoids per-pixel function call overhead

---

## Future Architecture Considerations

### Layers

Adding layer support would require:
1. Document model changes to store multiple image layers
2. Layer palette UI
3. Compositing logic in draw()
4. Per-layer undo granularity

### Non-Destructive Editing

Currently all operations modify pixels directly. Non-destructive editing would require:
1. Operation stack instead of pixel storage
2. Real-time rendering pipeline
3. Significantly more complex undo/redo

### Metal Acceleration

For large canvases or complex operations, Metal could provide:
1. GPU-accelerated compositing
2. Real-time filter preview
3. Smoother zoom/pan

This would require replacing NSImage-based drawing with Metal textures and shaders.