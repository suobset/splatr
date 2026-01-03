//
//  ToolPaletteController.swift
//  Blot
//
//  Created by Kushagra Srivastava on 1/2/26.
//

import AppKit
import SwiftUI
import Combine

// MARK: - Tool Enum (All 16 MS Paint XP Tools)
enum Tool: String, CaseIterable, Identifiable {
    // Selection tools (Row 1)
    case freeFormSelect = "Free-Form Select"
    case rectangleSelect = "Select"
    // Row 2
    case eraser = "Eraser"
    case fill = "Fill"
    // Row 3
    case colorPicker = "Pick Color"
    case magnifier = "Magnifier"
    // Row 4
    case pencil = "Pencil"
    case brush = "Brush"
    // Row 5
    case airbrush = "Airbrush"
    case text = "Text"
    // Row 6
    case line = "Line"
    case curve = "Curve"
    // Row 7
    case rectangle = "Rectangle"
    case polygon = "Polygon"
    // Row 8
    case ellipse = "Ellipse"
    case roundedRectangle = "Rounded Rect"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .freeFormSelect: return "lasso"
        case .rectangleSelect: return "rectangle.dashed"
        case .eraser: return "eraser.fill"
        case .fill: return "drop.fill"
        case .colorPicker: return "eyedropper"
        case .magnifier: return "magnifyingglass"
        case .pencil: return "pencil"
        case .brush: return "paintbrush.fill"
        case .airbrush: return "sprinkler.and.droplets"
        case .text: return "textformat"
        case .line: return "line.diagonal"
        case .curve: return "scribble"
        case .rectangle: return "rectangle"
        case .polygon: return "pentagon"
        case .ellipse: return "circle"
        case .roundedRectangle: return "rectangle.roundedtop"
        }
    }
    
    var shortcut: String {
        switch self {
        case .freeFormSelect: return "S"
        case .rectangleSelect: return "⇧S"
        case .eraser: return "E"
        case .fill: return "G"
        case .colorPicker: return "I"
        case .magnifier: return "Z"
        case .pencil: return "P"
        case .brush: return "B"
        case .airbrush: return "A"
        case .text: return "T"
        case .line: return "L"
        case .curve: return "C"
        case .rectangle: return "R"
        case .polygon: return "Y"
        case .ellipse: return "O"
        case .roundedRectangle: return "⇧R"
        }
    }
}

// MARK: - Shape Style (for shape tools)
enum ShapeStyle: Int, CaseIterable {
    case outline = 0
    case filledWithOutline = 1
    case filledNoOutline = 2
}

// MARK: - Brush Shape
enum BrushShape: Int, CaseIterable {
    case circle = 0
    case square = 1
    case slashRight = 2
    case slashLeft = 3
}

// MARK: - Shared State
class ToolPaletteState: ObservableObject {
    static let shared = ToolPaletteState()
    
    @Published var currentTool: Tool = .pencil
    @Published var brushSize: CGFloat = 4.0
    @Published var foregroundColor: Color = .black
    @Published var backgroundColor: Color = .white
    @Published var navigatorImage: NSImage?
    @Published var shapeStyle: ShapeStyle = .outline
    @Published var brushShape: BrushShape = .circle
    @Published var lineWidth: CGFloat = 1.0
    @Published var zoomLevel: CGFloat = 1.0
    
    // Airbrush settings
    @Published var airbrushIntensity: CGFloat = 0.3
    
    // Text settings
    @Published var fontName: String = "Helvetica"
    @Published var fontSize: CGFloat = 14
}

// MARK: - Palette Controller
class ToolPaletteController {
    static let shared = ToolPaletteController()
    
    private var toolPaletteWindow: NSPanel?
    private var colorPaletteWindow: NSPanel?
    private var navigatorWindow: NSPanel?
    
    private var toolPaletteVisible = true
    private var colorPaletteVisible = true
    private var navigatorVisible = true
    
    private func createPanel(title: String, rect: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.level = .floating
        return panel
    }
    
    func showAllPalettes() {
        toolPaletteVisible = true
        colorPaletteVisible = true
        navigatorVisible = true
        showToolPalette()
        showColorPalette()
        showNavigator()
    }
    
    func hideAllPalettes() {
        toolPaletteVisible = false
        colorPaletteVisible = false
        navigatorVisible = false
        toolPaletteWindow?.orderOut(nil)
        colorPaletteWindow?.orderOut(nil)
        navigatorWindow?.orderOut(nil)
    }
    
    func showPalettesIfNeeded() {
        if toolPaletteVisible { toolPaletteWindow?.orderFront(nil) }
        if colorPaletteVisible { colorPaletteWindow?.orderFront(nil) }
        if navigatorVisible { navigatorWindow?.orderFront(nil) }
    }
    
    func hidePalettesTemporarily() {
        toolPaletteWindow?.orderOut(nil)
        colorPaletteWindow?.orderOut(nil)
        navigatorWindow?.orderOut(nil)
    }
    
    func showToolPalette() {
        toolPaletteVisible = true
        if let window = toolPaletteWindow {
            window.orderFront(nil)
            return
        }
        
        let screenHeight = NSScreen.main?.frame.height ?? 800
        let panel = createPanel(title: "Tools", rect: NSRect(x: 50, y: screenHeight - 520, width: 66, height: 440))
        panel.contentView = NSHostingView(rootView: ToolPaletteView())
        panel.orderFront(nil)
        toolPaletteWindow = panel
    }
    
    func showColorPalette() {
        colorPaletteVisible = true
        if let window = colorPaletteWindow {
            window.orderFront(nil)
            return
        }
        
        let panel = createPanel(title: "Colors", rect: NSRect(x: 150, y: 80, width: 340, height: 80))
        panel.contentView = NSHostingView(rootView: ColorPaletteView())
        panel.orderFront(nil)
        colorPaletteWindow = panel
    }
    
    func showNavigator() {
        navigatorVisible = true
        if let window = navigatorWindow {
            window.orderFront(nil)
            return
        }
        
        let screenWidth = NSScreen.main?.frame.width ?? 1200
        let screenHeight = NSScreen.main?.frame.height ?? 800
        let panel = createPanel(title: "Navigator", rect: NSRect(x: screenWidth - 220, y: screenHeight - 250, width: 180, height: 160))
        panel.contentView = NSHostingView(rootView: NavigatorView())
        panel.orderFront(nil)
        navigatorWindow = panel
    }
}

// MARK: - Tool Palette View (Faithful to XP layout: 2 columns, 8 rows)
struct ToolPaletteView: View {
    @ObservedObject var state = ToolPaletteState.shared
    
    // Tools arranged in XP order (2 columns, 8 rows)
    let toolRows: [[Tool]] = [
        [.freeFormSelect, .rectangleSelect],
        [.eraser, .fill],
        [.colorPicker, .magnifier],
        [.pencil, .brush],
        [.airbrush, .text],
        [.line, .curve],
        [.rectangle, .polygon],
        [.ellipse, .roundedRectangle]
    ]
    
    var body: some View {
        VStack(spacing: 4) {
            // Tool grid
            ForEach(0..<toolRows.count, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(toolRows[row]) { tool in
                        ToolButton(tool: tool, isSelected: state.currentTool == tool) {
                            state.currentTool = tool
                        }
                    }
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Tool options area (changes based on selected tool)
            toolOptionsView
            
            Spacer()
        }
        .padding(6)
        .frame(width: 66, height: 420)
    }
    
    @ViewBuilder
    var toolOptionsView: some View {
        switch state.currentTool {
        case .eraser, .airbrush:
            // Size options
            VStack(spacing: 2) {
                Text("Size")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach([2, 4, 6, 8], id: \.self) { size in
                    Button {
                        state.brushSize = CGFloat(size)
                    } label: {
                        Rectangle()
                            .fill(state.brushSize == CGFloat(size) ? Color.accentColor : Color.primary)
                            .frame(width: CGFloat(size * 3), height: CGFloat(size))
                    }
                    .buttonStyle(.plain)
                }
            }
            
        case .brush:
            // Brush shapes
            VStack(spacing: 2) {
                Text("Shape")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.fixed(20)), GridItem(.fixed(20))], spacing: 2) {
                    ForEach(BrushShape.allCases, id: \.rawValue) { shape in
                        Button {
                            state.brushShape = shape
                        } label: {
                            brushShapeIcon(shape)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .background(state.brushShape == shape ? Color.accentColor.opacity(0.3) : Color.clear)
                        .cornerRadius(2)
                    }
                }
            }
            
        case .line, .curve:
            // Line widths
            VStack(spacing: 2) {
                Text("Width")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach([1, 2, 3, 4, 5], id: \.self) { width in
                    Button {
                        state.lineWidth = CGFloat(width)
                    } label: {
                        Rectangle()
                            .fill(state.lineWidth == CGFloat(width) ? Color.accentColor : Color.primary)
                            .frame(width: 40, height: CGFloat(width))
                    }
                    .buttonStyle(.plain)
                }
            }
            
        case .rectangle, .ellipse, .roundedRectangle, .polygon:
            // Shape styles (outline, filled+outline, filled)
            VStack(spacing: 2) {
                Text("Style")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(ShapeStyle.allCases, id: \.rawValue) { style in
                    Button {
                        state.shapeStyle = style
                    } label: {
                        shapeStyleIcon(style)
                            .frame(width: 40, height: 20)
                    }
                    .buttonStyle(.plain)
                    .background(state.shapeStyle == style ? Color.accentColor.opacity(0.3) : Color.clear)
                    .cornerRadius(2)
                }
            }
            
        case .magnifier:
            // Zoom levels
            VStack(spacing: 2) {
                Text("Zoom")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach([1, 2, 4, 6, 8], id: \.self) { zoom in
                    Button {
                        state.zoomLevel = CGFloat(zoom)
                    } label: {
                        Text("\(zoom)×")
                            .font(.caption)
                            .frame(width: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(state.zoomLevel == CGFloat(zoom) ? .accentColor : .secondary)
                }
            }
            
        default:
            // Default: brush size slider
            VStack(spacing: 4) {
                Text("Size: \(Int(state.brushSize))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $state.brushSize, in: 1...20, step: 1)
                    .frame(width: 50)
            }
        }
    }
    
    func brushShapeIcon(_ shape: BrushShape) -> some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
            switch shape {
            case .circle:
                context.fill(Circle().path(in: rect), with: .color(.primary))
            case .square:
                context.fill(Rectangle().path(in: rect), with: .color(.primary))
            case .slashRight:
                var path = Path()
                path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                context.stroke(path, with: .color(.primary), lineWidth: 2)
            case .slashLeft:
                var path = Path()
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                context.stroke(path, with: .color(.primary), lineWidth: 2)
            }
        }
    }
    
    func shapeStyleIcon(_ style: ShapeStyle) -> some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
            switch style {
            case .outline:
                context.stroke(Rectangle().path(in: rect), with: .color(.primary), lineWidth: 1)
            case .filledWithOutline:
                context.fill(Rectangle().path(in: rect), with: .color(.secondary))
                context.stroke(Rectangle().path(in: rect), with: .color(.primary), lineWidth: 1)
            case .filledNoOutline:
                context.fill(Rectangle().path(in: rect), with: .color(.primary))
            }
        }
    }
}

struct ToolButton: View {
    let tool: Tool
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: tool.icon)
                .font(.system(size: 14))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .help("\(tool.rawValue) (\(tool.shortcut))")
    }
}

// MARK: - Color Palette View
struct ColorPaletteView: View {
    @ObservedObject var state = ToolPaletteState.shared
    
    // Exact MS Paint XP 28-color palette
    let topColors: [Color] = [
        Color(nsColor: NSColor(red: 0, green: 0, blue: 0, alpha: 1)),         // Black
        Color(nsColor: NSColor(red: 128/255, green: 128/255, blue: 128/255, alpha: 1)), // Gray
        Color(nsColor: NSColor(red: 128/255, green: 0, blue: 0, alpha: 1)),   // Maroon
        Color(nsColor: NSColor(red: 128/255, green: 128/255, blue: 0, alpha: 1)), // Olive
        Color(nsColor: NSColor(red: 0, green: 128/255, blue: 0, alpha: 1)),   // Green
        Color(nsColor: NSColor(red: 0, green: 128/255, blue: 128/255, alpha: 1)), // Teal
        Color(nsColor: NSColor(red: 0, green: 0, blue: 128/255, alpha: 1)),   // Navy
        Color(nsColor: NSColor(red: 128/255, green: 0, blue: 128/255, alpha: 1)), // Purple
        Color(nsColor: NSColor(red: 128/255, green: 128/255, blue: 0, alpha: 1)), // Olive (dup)
        Color(nsColor: NSColor(red: 0, green: 64/255, blue: 64/255, alpha: 1)),   // Dark Teal
        Color(nsColor: NSColor(red: 0, green: 0, blue: 255/255, alpha: 1)),   // Blue
        Color(nsColor: NSColor(red: 0, green: 128/255, blue: 255/255, alpha: 1)), // Light Blue
        Color(nsColor: NSColor(red: 128/255, green: 0, blue: 255/255, alpha: 1)), // Purple-Blue
        Color(nsColor: NSColor(red: 128/255, green: 0, blue: 64/255, alpha: 1)),  // Dark Magenta
    ]
    
    let bottomColors: [Color] = [
        Color(nsColor: NSColor(red: 1, green: 1, blue: 1, alpha: 1)),         // White
        Color(nsColor: NSColor(red: 192/255, green: 192/255, blue: 192/255, alpha: 1)), // Silver
        Color(nsColor: NSColor(red: 1, green: 0, blue: 0, alpha: 1)),         // Red
        Color(nsColor: NSColor(red: 1, green: 1, blue: 0, alpha: 1)),         // Yellow
        Color(nsColor: NSColor(red: 0, green: 1, blue: 0, alpha: 1)),         // Lime
        Color(nsColor: NSColor(red: 0, green: 1, blue: 1, alpha: 1)),         // Cyan
        Color(nsColor: NSColor(red: 0, green: 0, blue: 1, alpha: 1)),         // Blue
        Color(nsColor: NSColor(red: 1, green: 0, blue: 1, alpha: 1)),         // Magenta
        Color(nsColor: NSColor(red: 1, green: 1, blue: 128/255, alpha: 1)),   // Light Yellow
        Color(nsColor: NSColor(red: 128/255, green: 1, blue: 128/255, alpha: 1)), // Light Green
        Color(nsColor: NSColor(red: 128/255, green: 1, blue: 1, alpha: 1)),   // Light Cyan
        Color(nsColor: NSColor(red: 128/255, green: 128/255, blue: 1, alpha: 1)), // Light Blue
        Color(nsColor: NSColor(red: 1, green: 128/255, blue: 128/255, alpha: 1)), // Light Red
        Color(nsColor: NSColor(red: 1, green: 128/255, blue: 1, alpha: 1)),   // Light Magenta
    ]
    
    var body: some View {
        HStack(spacing: 10) {
            // Foreground/Background color display (XP style overlapping squares)
            ZStack(alignment: .topLeading) {
                // Background color (bottom-right)
                Rectangle()
                    .fill(state.backgroundColor)
                    .frame(width: 20, height: 20)
                    .border(Color.primary.opacity(0.4), width: 1)
                    .offset(x: 10, y: 10)
                
                // Foreground color (top-left)
                Rectangle()
                    .fill(state.foregroundColor)
                    .frame(width: 20, height: 20)
                    .border(Color.primary.opacity(0.6), width: 1)
            }
            .frame(width: 34, height: 34)
            .onTapGesture(count: 2) {
                // Swap colors
                let temp = state.foregroundColor
                state.foregroundColor = state.backgroundColor
                state.backgroundColor = temp
            }
            .help("Double-click to swap colors")
            
            // Color picker
            ColorPicker("", selection: $state.foregroundColor)
                .labelsHidden()
            
            Divider()
                .frame(height: 36)
            
            // Color grid
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    ForEach(0..<14, id: \.self) { i in
                        ColorGridButton(color: topColors[i])
                    }
                }
                HStack(spacing: 1) {
                    ForEach(0..<14, id: \.self) { i in
                        ColorGridButton(color: bottomColors[i])
                    }
                }
            }
        }
        .padding(10)
        .frame(height: 60)
    }
}

struct ColorGridButton: View {
    let color: Color
    @ObservedObject var state = ToolPaletteState.shared
    
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 14, height: 14)
            .border(Color.primary.opacity(0.2), width: 0.5)
            .onTapGesture {
                state.foregroundColor = color
            }
            .simultaneousGesture(
                TapGesture().modifiers(.control).onEnded {
                    state.backgroundColor = color
                }
            )
            .help("Left-click: foreground, Ctrl-click: background")
    }
}

// MARK: - Navigator View
struct NavigatorView: View {
    @ObservedObject var state = ToolPaletteState.shared
    
    var body: some View {
        VStack(spacing: 8) {
            if let image = state.navigatorImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 160, maxHeight: 120)
                    .border(Color.primary.opacity(0.2), width: 1)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 160, height: 120)
                    .overlay(
                        Text("No canvas")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .padding(8)
        .frame(width: 180, height: 140)
    }
}
