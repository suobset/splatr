# Contributing to Splatr

Splatr is not currently accepting any code contributions, in accordance to the poilicies laid out by the Swift Student Developer Challenge. Please refrain from any code contributions until the app is submitted to the Challenge.

However, the following documentation (and more documentation) exist for when contributions will be accepted later this year. 

## Table of Contents

1. [Project Overview](#project-overview)
2. [Development Environment Setup](#development-environment-setup)
3. [Architecture](#architecture)
4. [Directory Structure](#directory-structure)
5. [Core Concepts](#core-concepts)
6. [Module Documentation](#module-documentation)
7. [Adding New Features](#adding-new-features)
8. [Code Style Guidelines](#code-style-guidelines)
9. [Testing](#testing)
10. [Building and Distribution](#building-and-distribution)

---

## Project Overview

Splatr is a native macOS bitmap image editor written entirely in Swift. It uses a hybrid approach combining SwiftUI for declarative UI components and AppKit for low-level canvas operations that require direct pixel manipulation.

### Design Philosophy

- **Native first**: No Electron, no web views, no cross-platform frameworks. Splatr uses Apple's native frameworks exclusively.
- **Simplicity**: The application does one thing well—bitmap editing. Features are added only when they serve this core purpose.
- **Performance**: Direct pixel buffer manipulation where necessary, avoiding abstraction layers that introduce latency.
- **Classic UX**: The interface draws inspiration from MS Paint (Windows XP era), prioritizing discoverability and immediate feedback.

### Technology Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| UI Framework | SwiftUI | Declarative UI for palettes, dialogs, and document management |
| Canvas Rendering | AppKit (NSView) | Direct control over drawing, mouse events, and pixel manipulation |
| Graphics | Core Graphics | Bitmap operations, color space conversions, image compositing |
| Document Model | SwiftUI Document Architecture | File I/O, undo/redo integration, recent documents |
| Floating Panels | NSPanel | Tool palettes that float above document windows |

---

## Development Environment Setup

### Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Apple Silicon or Intel Mac

### Getting Started

```bash
# Clone the repository
git clone https://github.com/suobset/splatr.git
cd splatr

# Open in Xcode
open Splatr.xcodeproj
```

Press `Cmd + R` to build and run.

### Project Configuration

The project uses standard Xcode project configuration with no external dependencies or package managers. All code is first-party Swift.

Key build settings:
- **Deployment Target**: macOS 13.0
- **Swift Language Version**: Swift 5
- **Code Signing**: Sign to Run Locally (for development)

---

## Architecture

Splatr follows a modified Model-View-Context architecture pattern, adapted for the hybrid SwiftUI/AppKit approach.

```
┌─────────────────────────────────────────────────────────────┐
│                        SplatrApp                             │
│                    (Application Entry)                       │
└─────────────────────┬───────────────────────────────────────┘
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
┌─────────────────┐     ┌─────────────────────┐
│  DocumentGroup  │     │ ToolPaletteController│
│   (SwiftUI)     │     │    (NSPanel mgmt)    │
└────────┬────────┘     └──────────┬──────────┘
         │                         │
         ▼                         ▼
┌─────────────────┐     ┌─────────────────────┐
│   ContentView   │     │  ToolPaletteState   │
│   (SwiftUI)     │◄────│    (Observable)     │
└────────┬────────┘     └─────────────────────┘
         │
         ▼
┌─────────────────┐
│   CanvasView    │
│(NSViewRepresent)│
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  CanvasNSView   │
│    (AppKit)     │
└─────────────────┘
```

### Data Flow

1. **User Input**: Mouse/keyboard events captured by `CanvasNSView`
2. **State Updates**: Tool selection and properties flow through `ToolPaletteState` (singleton)
3. **Document Changes**: Canvas modifications propagate through the `Coordinator` to `splatrDocument`
4. **Undo/Redo**: Managed by SwiftUI's `UndoManager`, integrated via the Coordinator pattern

---

## Directory Structure

```
Splatr/
├── App/                          # Application lifecycle
│   └── SplatrApp.swift           # @main entry point, DocumentGroup setup
│
├── Model/                        # Data structures and enums
│   ├── SplatrDocument.swift      # Document model (canvas data, size, file I/O)
│   ├── Tool.swift                # Tool enum with icons and shortcuts
│   ├── ShapeStyle.swift          # Shape rendering modes
│   └── BrushShape.swift          # Brush tip shapes
│
├── Context/                      # Shared state and controllers
│   ├── ToolPaletteState.swift    # Observable singleton for tool/color state
│   └── ToolPaletteController.swift # NSPanel creation and visibility management
│
├── View/                         # All UI components
│   ├── ContentView.swift         # Main document view container
│   ├── WelcomeView.swift         # Welcome window for new users
│   ├── AboutView.swift           # About panel
│   │
│   ├── Canvas/                   # Canvas implementation (split for maintainability)
│   │   ├── CanvasView.swift      # NSViewRepresentable wrapper + Coordinator
│   │   ├── CanvasNSView.swift    # Core NSView subclass, properties, drawing
│   │   ├── CanvasNSView+Mouse.swift      # Mouse event handling
│   │   ├── CanvasNSView+Drawing.swift    # Pencil, Brush, Eraser, Airbrush
│   │   ├── CanvasNSView+Shapes.swift     # Shape tools (Line, Rect, etc.)
│   │   ├── CanvasNSView+Selection.swift  # Selection tools and transforms
│   │   ├── CanvasNSView+Text.swift       # Text tool
│   │   ├── CanvasNSView+Fill.swift       # Flood fill and color picker
│   │   └── CanvasNSView+Helpers.swift    # Utility functions
│   │
│   └── [Palette Views]           # Floating palette UIs
│       ├── ToolPaletteView.swift
│       ├── ColorPaletteView.swift
│       ├── CustomColorsPaletteView.swift
│       ├── NavigatorView.swift
│       └── TextOptionsView.swift
│
├── Assets.xcassets/              # Images, colors, app icon
├── SplatrIcon.icon/              # Icon source files
└── Info.plist                    # Application metadata
```

---

## Core Concepts

### The Canvas Architecture

The canvas is the most complex part of Splatr. Understanding its architecture is essential for any non-trivial contribution.

#### Why NSView instead of SwiftUI Canvas?

SwiftUI's `Canvas` view is designed for declarative drawing but lacks:
- Direct pixel buffer access for flood fill
- Fine-grained mouse event control (drag vs. click distinction)
- NSTextField embedding for text tool
- Cursor customization per-region

Therefore, `CanvasNSView` is a traditional `NSView` subclass wrapped in `NSViewRepresentable`.

#### The Coordinator Pattern

```swift
struct CanvasView: NSViewRepresentable {
    @Binding var document: splatrDocument
    
    func makeCoordinator() -> Coordinator {
        Coordinator(document: $document, ...)
    }
    
    class Coordinator {
        // Bridge between AppKit and SwiftUI
        // Handles undo registration
        // Forwards document changes
    }
}
```

The Coordinator:
1. Holds a binding to the SwiftUI document
2. Receives callbacks from `CanvasNSView` when the canvas changes
3. Registers undo actions with the document's `UndoManager`
4. Updates the Navigator preview image

#### Canvas State vs. Document State

| State Type | Location | Persistence |
|------------|----------|-------------|
| Canvas image (pixels) | `splatrDocument.canvasData` | Saved to disk |
| Canvas size | `splatrDocument.canvasSize` | Saved to disk |
| Current tool | `ToolPaletteState.shared` | Session only |
| Selection state | `CanvasNSView` properties | Transient |
| In-progress stroke | `CanvasNSView.currentPath` | Transient |

### Tool State Management

`ToolPaletteState` is an `ObservableObject` singleton that holds all tool-related state:

```swift
class ToolPaletteState: ObservableObject {
    static let shared = ToolPaletteState()
    
    @Published var currentTool: Tool = .pencil
    @Published var brushSize: CGFloat = 4.0
    @Published var foregroundColor: Color = .black
    @Published var backgroundColor: Color = .white
    // ... more properties
}
```

SwiftUI views observe this object directly. The `CanvasNSView` receives values through its properties, set during `updateNSView()`.

### Floating Palettes

Palettes are `NSPanel` instances (a special `NSWindow` subclass for utility windows):

```swift
let panel = NSPanel(
    contentRect: rect,
    styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.isFloatingPanel = true
panel.hidesOnDeactivate = true
```

Key behaviors:
- Float above document windows
- Don't steal focus from the canvas
- Hide when the app is deactivated
- Can follow into full-screen mode

---

## Module Documentation

### Model Layer

#### SplatrDocument.swift

The document model conforming to `FileDocument`.

```swift
struct splatrDocument: FileDocument {
    var canvasData: Data      // PNG-encoded image data
    var canvasSize: CGSize    // Canvas dimensions in points
    
    // File I/O
    init(configuration: ReadConfiguration) throws
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper
}
```

Supported formats:
- Native: `.splatr` (actually PNG with metadata)
- Import: PNG, JPEG, BMP, TIFF, GIF
- Export: PNG, JPEG, TIFF, BMP, GIF, PDF

#### Tool.swift

Enumeration of all 16 tools:

```swift
enum Tool: String, CaseIterable, Identifiable {
    case freeFormSelect, rectangleSelect
    case eraser, fill, colorPicker, magnifier
    case pencil, brush, airbrush, text
    case line, curve, rectangle, polygon, ellipse, roundedRectangle
    
    var icon: String        // SF Symbol name
    var shortcut: String    // Keyboard shortcut hint
}
```

### Canvas Layer

#### CanvasNSView.swift

The core canvas class. Key properties:

```swift
class CanvasNSView: NSView {
    // Canvas state
    var canvasImage: NSImage?       // The actual bitmap
    var canvasSize: CGSize          // Dimensions
    var documentDataHash: Int       // For change detection
    
    // Tool state (set by CanvasView.updateNSView)
    var currentTool: Tool
    var currentColor: NSColor
    var brushSize: CGFloat
    
    // Drawing state
    var currentPath: [NSPoint]      // Points in current stroke
    var shapeStartPoint: NSPoint?   // Shape tool anchor
    
    // Selection state
    var selectionRect: NSRect?
    var selectionImage: NSImage?    // Captured selection content
    var selectionPath: NSBezierPath? // Free-form selection outline
}
```

#### CanvasNSView+Mouse.swift

Mouse event handling is centralized here. The `mouseDown` method routes to tool-specific handlers:

```swift
override func mouseDown(with event: NSEvent) {
    switch currentTool {
    case .pencil, .brush, .eraser:
        // Start stroke
    case .fill:
        floodFill(at: point)
    case .rectangleSelect:
        // Begin selection or move existing
    // ... etc
    }
}
```

#### CanvasNSView+Fill.swift

Contains the flood fill implementation. This was rewritten from scratch to solve coordinate system issues.

Key implementation details:
1. Creates a fresh `NSBitmapImageRep` with known format (32-bit RGBA)
2. Draws the canvas image into this controlled bitmap
3. Accesses raw pixel buffer via `bitmap.bitmapData`
4. Uses scanline flood fill algorithm for efficiency
5. Flips Y coordinate (NSView origin is bottom-left, bitmap is top-left)

```swift
// Coordinate transformation
let clickX = Int(point.x)
let clickY = height - 1 - Int(point.y)  // Flip Y
```

#### CanvasNSView+Selection.swift

Selection tools are the most complex, supporting:
- Rectangular and free-form (lasso) selection
- Move, resize, rotate transforms
- Copy/paste via NSPasteboard
- Context menu operations

Selection lifecycle:
1. User drags to create selection rect/path
2. `captureSelection()` extracts pixels into `selectionImage`
3. Original area cleared to white (on first move)
4. User can transform the floating selection
5. `commitSelection()` composites back into canvas
6. ESC key commits and clears selection state

### View Layer

#### ContentView.swift

The main document view. Responsibilities:
- Hosts the `CanvasView` in a scroll view
- Applies zoom transforms
- Handles keyboard shortcuts for tools
- Manages canvas resize operations
- Coordinates with `ToolPaletteController`

#### Palette Views

Each palette is a self-contained SwiftUI view that observes `ToolPaletteState`:

```swift
struct ToolPaletteView: View {
    @ObservedObject var state = ToolPaletteState.shared
    
    var body: some View {
        // Tool buttons in 8x2 grid
        // Context-sensitive options below
    }
}
```

---

## Adding New Features

### Adding a New Tool

1. **Add to Tool enum** (`Model/Tool.swift`):
```swift
case myNewTool = "My New Tool"

var icon: String {
    case .myNewTool: return "sf.symbol.name"
}

var shortcut: String {
    case .myNewTool: return "X"
}
```

2. **Add tool state** (if needed) to `ToolPaletteState.swift`:
```swift
@Published var myToolProperty: CGFloat = 1.0
```

3. **Add to tool palette grid** (`ToolPaletteView.swift`):
```swift
let toolRows: [[Tool]] = [
    // ... existing rows
    [.existingTool, .myNewTool]
]
```

4. **Handle in mouse events** (`CanvasNSView+Mouse.swift`):
```swift
case .myNewTool:
    handleMyNewTool(at: p)
```

5. **Implement tool logic** (new file or existing extension):
```swift
// CanvasNSView+MyTool.swift
extension CanvasNSView {
    func handleMyNewTool(at point: NSPoint) {
        // Implementation
    }
}
```

6. **Add keyboard shortcut** (`ContentView.swift`):
```swift
case "x": state.currentTool = .myNewTool
```

### Adding a New Palette

1. **Create the view** (`View/MyPaletteView.swift`):
```swift
struct MyPaletteView: View {
    @ObservedObject var state = ToolPaletteState.shared
    var body: some View { ... }
}
```

2. **Add window management** (`ToolPaletteController.swift`):
```swift
private var myPaletteWindow: NSPanel?
private var myPaletteVisible = false

func showMyPalette() {
    myPaletteVisible = true
    if let window = myPaletteWindow {
        window.orderFront(nil)
        return
    }
    let panel = createPanel(title: "My Palette", rect: ...)
    panel.contentView = NSHostingView(rootView: MyPaletteView())
    panel.orderFront(nil)
    myPaletteWindow = panel
}
```

3. **Add menu command** (in `SplatrApp.swift` or `ContentView.swift`)

### Modifying the Document Format

The `.splatr` format is currently PNG with a custom UTI. To add metadata:

1. Update `SplatrDocument.swift` to include new properties
2. Modify `fileWrapper()` to encode metadata (consider JSON sidecar or PNG chunks)
3. Modify `init(configuration:)` to decode
4. Update `Info.plist` if changing UTI

---

## Code Style Guidelines

### General Principles

- **Clarity over brevity**: Descriptive names, even if longer
- **Comments for "why"**: Code shows what; comments explain why
- **One responsibility per file**: Split large files into extensions

### Swift Conventions

```swift
// Properties: camelCase
var currentTool: Tool
var isMovingSelection: Bool

// Functions: camelCase, verb phrases
func commitSelection()
func handleMouseDown(at point: NSPoint)

// Types: PascalCase
enum Tool { }
struct CanvasView { }
class CanvasNSView { }

// Constants: camelCase (Swift convention)
let maxCustomColors = 28
let handleSize: CGFloat = 8
```

### File Organization

Each file should follow this structure:
```swift
//
//  FileName.swift
//  splatr
//
//  Created by [Name] on [Date].
//

import [Frameworks]

// MARK: - [Section Name]

// Code...
```

### Extension Files

When splitting a class into extensions:
- Main file contains class declaration and stored properties
- Extensions contain related methods grouped by functionality
- Each extension file named `ClassName+Feature.swift`

---

## Testing

### Current State

The project includes test targets but comprehensive tests are not yet implemented. This is an area for contribution.

### Running Tests

```bash
# From Xcode
Cmd + U

# From command line
xcodebuild test -scheme Splatr -destination 'platform=macOS'
```

### Areas Needing Tests

1. **Document I/O**: Round-trip save/load verification
2. **Flood Fill**: Edge cases, tolerance behavior
3. **Selection**: Transform mathematics, boundary conditions
4. **Color Conversion**: RGB/HSB consistency

---

## Building and Distribution

Building and Distribution of the main Splatr app is handled entirely by [Kush S.](https://skushagra.com/)

---

## Getting Help

- **Issues**: Report bugs or request features on GitHub
- **Discussions**: For questions and design discussions
- **Code Review**: All PRs are reviewed for consistency and quality

When submitting a PR:
1. Reference any related issues
2. Describe what changed and why
3. Include screenshots for UI changes
4. Ensure the project builds without warnings

---

## License

Splatr is released under the MIT License. Contributions are made under the same license.