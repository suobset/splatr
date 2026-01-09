//
//  ToolPaletteController.swift
//  splatr
//
//  Created by Kushagra Srivastava on 1/2/26.
//

import AppKit
import SwiftUI
import Combine

// MARK: - Tool Enum (All 16 MS Paint XP Tools)

/// Enumeration of all tools the app exposes, with display names,
/// SF Symbols icons, and shortcut string for help tooltips.
enum Tool: String, CaseIterable, Identifiable {
    case freeFormSelect = "Free-Form Select"
    case rectangleSelect = "Select"
    case eraser = "Eraser"
    case fill = "Fill"
    case colorPicker = "Pick Color"
    case magnifier = "Magnifier"
    case pencil = "Pencil"
    case brush = "Brush"
    case airbrush = "Airbrush"
    case text = "Text"
    case line = "Line"
    case curve = "Curve"
    case rectangle = "Rectangle"
    case polygon = "Polygon"
    case ellipse = "Ellipse"
    case roundedRectangle = "Rounded Rect"
    
    var id: String { rawValue }
    
    /// SF Symbols name to represent each tool in the palette UI.
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
    
    /// Human-readable shortcut hint for tooltips (not used for actual key handling here).
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

/// Shape rendering modes for shape tools.
enum ShapeStyle: Int, CaseIterable {
    case outline = 0
    case filledWithOutline = 1
    case filledNoOutline = 2
}

// MARK: - Brush Shape

/// Brush tip shapes for the brush tool.
enum BrushShape: Int, CaseIterable {
    case circle = 0
    case square = 1
    case slashRight = 2
    case slashLeft = 3
}

// MARK: - Shared State

/// Singleton observable state for tools/palettes used across the app.
/// This provides a single source of truth for the currently selected tool,
/// colors, brush attributes, text attributes, and navigator image.
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
    
    // Custom colors (persisted)
    @Published var customColors: [Color] = [] {
        didSet { saveCustomColors() }
    }
    
    // Airbrush settings
    @Published var airbrushIntensity: CGFloat = 0.3
    
    // Text settings
    @Published var fontName: String = "Helvetica"
    @Published var fontSize: CGFloat = 24
    @Published var isBold: Bool = false
    @Published var isItalic: Bool = false
    @Published var isUnderlined: Bool = false
    
    private let customColorsKey = "BlotCustomColors"
    private let maxCustomColors = 28 // 2 rows of 14
    
    private init() {
        loadCustomColors()
    }
    
    /// Adds a custom color to the palette, avoiding duplicates and keeping
    /// the list bounded to `maxCustomColors`.
    func addCustomColor(_ color: Color) {
        // Don't add duplicates
        if customColors.contains(where: { colorsAreEqual($0, color) }) {
            return
        }
        
        // Add to front, remove oldest if at max
        customColors.insert(color, at: 0)
        if customColors.count > maxCustomColors {
            customColors.removeLast()
        }
    }
    
    /// Compares two SwiftUI Colors in deviceRGB space with a tolerance,
    /// to handle floating-point differences.
    private func colorsAreEqual(_ c1: Color, _ c2: Color) -> Bool {
        let ns1 = NSColor(c1).usingColorSpace(.deviceRGB)
        let ns2 = NSColor(c2).usingColorSpace(.deviceRGB)
        guard let ns1, let ns2 else { return false }
        return abs(ns1.redComponent - ns2.redComponent) < 0.01 &&
               abs(ns1.greenComponent - ns2.greenComponent) < 0.01 &&
               abs(ns1.blueComponent - ns2.blueComponent) < 0.01
    }
    
    /// Persists custom colors to UserDefaults as RGBA component arrays.
    private func saveCustomColors() {
        let colorData = customColors.compactMap { color -> [CGFloat]? in
            guard let nsColor = NSColor(color).usingColorSpace(.deviceRGB) else { return nil }
            return [nsColor.redComponent, nsColor.greenComponent, nsColor.blueComponent, nsColor.alphaComponent]
        }
        UserDefaults.standard.set(colorData, forKey: customColorsKey)
    }
    
    /// Loads custom colors from UserDefaults.
    private func loadCustomColors() {
        guard let colorData = UserDefaults.standard.array(forKey: customColorsKey) as? [[CGFloat]] else { return }
        customColors = colorData.map { components in
            Color(nsColor: NSColor(red: components[0], green: components[1], blue: components[2], alpha: components[3]))
        }
    }
}

// MARK: - Palette Controller

/// Manages creation and visibility of floating palettes (tools, colors, navigator,
/// text options, custom colors) as NSPanels. Also coordinates showing/hiding in response
/// to app activation and current tool selection.
class ToolPaletteController {
    static let shared = ToolPaletteController()
    
    private var toolPaletteWindow: NSPanel?
    private var colorPaletteWindow: NSPanel?
    private var navigatorWindow: NSPanel?
    private var textOptionsWindow: NSPanel?
    private var customColorsWindow: NSPanel?
    
    private var toolPaletteVisible = true
    private var colorPaletteVisible = true
    private var navigatorVisible = true
    private var textOptionsVisible = false
    private var customColorsVisible = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Automatically show text options when the Text tool is selected.
        ToolPaletteState.shared.$currentTool
            .sink { [weak self] tool in
                if tool == .text {
                    self?.showTextOptions()
                }
            }
            .store(in: &cancellables)
    }
    
    /// Convenience for creating consistent floating utility panels.
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
    
    /// Shows all palettes that make sense for the current tool selection.
    func showAllPalettes() {
        toolPaletteVisible = true
        colorPaletteVisible = true
        navigatorVisible = true
        showToolPalette()
        showColorPalette()
        showNavigator()
        if textOptionsVisible || ToolPaletteState.shared.currentTool == .text {
            showTextOptions()
        }
        if customColorsVisible {
            showCustomColors()
        }
    }
    
    /// Hides all palettes and marks them as not visible.
    func hideAllPalettes() {
        toolPaletteVisible = false
        colorPaletteVisible = false
        navigatorVisible = false
        textOptionsVisible = false
        customColorsVisible = false
        toolPaletteWindow?.orderOut(nil)
        colorPaletteWindow?.orderOut(nil)
        navigatorWindow?.orderOut(nil)
        textOptionsWindow?.orderOut(nil)
        customColorsWindow?.orderOut(nil)
    }
    
    /// Re-shows palettes that were previously visible when the app becomes active.
    func showPalettesIfNeeded() {
        if toolPaletteVisible { toolPaletteWindow?.orderFront(nil) }
        if colorPaletteVisible { colorPaletteWindow?.orderFront(nil) }
        if navigatorVisible { navigatorWindow?.orderFront(nil) }
        if textOptionsVisible { textOptionsWindow?.orderFront(nil) }
        if customColorsVisible { customColorsWindow?.orderFront(nil) }
    }
    
    /// Temporarily hides palettes when the app resigns active.
    func hidePalettesTemporarily() {
        toolPaletteWindow?.orderOut(nil)
        colorPaletteWindow?.orderOut(nil)
        navigatorWindow?.orderOut(nil)
        textOptionsWindow?.orderOut(nil)
        customColorsWindow?.orderOut(nil)
    }
    
    /// Shows the Tools palette as a floating NSPanel.
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
    
    /// Shows the Colors palette as a floating NSPanel.
    func showColorPalette() {
        colorPaletteVisible = true
        if let window = colorPaletteWindow {
            window.orderFront(nil)
            return
        }
        
        let panel = createPanel(title: "Colors", rect: NSRect(x: 150, y: 80, width: 370, height: 80))
        panel.contentView = NSHostingView(rootView: ColorPaletteView())
        panel.orderFront(nil)
        colorPaletteWindow = panel
    }
    
    /// Shows the Navigator palette (preview image) as a floating NSPanel.
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
    
    /// Shows the Text Options palette as a floating NSPanel.
    func showTextOptions() {
        textOptionsVisible = true
        if let window = textOptionsWindow {
            window.orderFront(nil)
            return
        }
        
        let screenWidth = NSScreen.main?.frame.width ?? 1200
        let screenHeight = NSScreen.main?.frame.height ?? 800
        let panel = createPanel(title: "Text Options", rect: NSRect(x: screenWidth - 220, y: screenHeight - 430, width: 180, height: 160))
        panel.contentView = NSHostingView(rootView: TextOptionsView())
        panel.delegate = TextOptionsPanelDelegate.shared
        panel.orderFront(nil)
        textOptionsWindow = panel
    }
    
    /// Hides the Text Options palette and marks it as not visible.
    func hideTextOptions() {
        textOptionsVisible = false
        textOptionsWindow?.orderOut(nil)
    }
    
    /// Toggles Text Options palette visibility.
    func toggleTextOptions() {
        if textOptionsVisible {
            hideTextOptions()
        } else {
            showTextOptions()
        }
    }
    
    /// Shows the Custom Colors palette as a floating NSPanel.
    func showCustomColors() {
        customColorsVisible = true
        if let window = customColorsWindow {
            window.orderFront(nil)
            return
        }
        
        let panel = createPanel(title: "Custom Colors", rect: NSRect(x: 150, y: 170, width: 260, height: 130))
        panel.contentView = NSHostingView(rootView: CustomColorsPaletteView())
        panel.delegate = CustomColorsPanelDelegate.shared
        panel.orderFront(nil)
        customColorsWindow = panel
    }
    
    /// Hides the Custom Colors palette and marks it as not visible.
    func hideCustomColors() {
        customColorsVisible = false
        customColorsWindow?.orderOut(nil)
    }
    
    /// Toggles Custom Colors palette visibility.
    func toggleCustomColors() {
        if customColorsVisible {
            hideCustomColors()
        } else {
            showCustomColors()
        }
    }
}

// MARK: - Text Options Panel Delegate

/// Tracks Text Options panel lifecycle to keep controller visibility flags in sync.
class TextOptionsPanelDelegate: NSObject, NSWindowDelegate {
    static let shared = TextOptionsPanelDelegate()
    
    func windowWillClose(_ notification: Notification) {
        ToolPaletteController.shared.hideTextOptions()
    }
}

// MARK: - Custom Colors Panel Delegate

/// Tracks Custom Colors panel lifecycle to keep controller visibility flags in sync.
class CustomColorsPanelDelegate: NSObject, NSWindowDelegate {
    static let shared = CustomColorsPanelDelegate()
    
    func windowWillClose(_ notification: Notification) {
        ToolPaletteController.shared.hideCustomColors()
    }
}

// MARK: - Text Options View

/// UI for choosing text font, size, styles, and previewing result.
/// Binds to the shared ToolPaletteState.
struct TextOptionsView: View {
    @ObservedObject var state = ToolPaletteState.shared
    
    /// A small curated font list for convenience.
    let availableFonts = [
        "Helvetica", "Helvetica Neue", "Arial", "Times New Roman",
        "Georgia", "Verdana", "Courier New", "Monaco",
        "Menlo", "SF Pro", "Avenir", "Futura",
        "Palatino", "Optima", "Gill Sans", "Baskerville"
    ].sorted()
    
    /// Common font sizes.
    let fontSizes: [CGFloat] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 64, 72, 96]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Font picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Font").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $state.fontName) {
                    ForEach(availableFonts, id: \.self) { font in
                        Text(font).font(.custom(font, size: 12)).tag(font)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            
            // Size picker + stepper
            VStack(alignment: .leading, spacing: 4) {
                Text("Size").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Picker("", selection: $state.fontSize) {
                        ForEach(fontSizes, id: \.self) { size in
                            Text("\(Int(size))").tag(size)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 70)
                    
                    Stepper("", value: $state.fontSize, in: 1...200, step: 1).labelsHidden()
                }
            }
            
            // Styles toggles
            VStack(alignment: .leading, spacing: 4) {
                Text("Style").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Toggle(isOn: $state.isBold) { Image(systemName: "bold") }
                        .toggleStyle(.button).help("Bold (⌘B)")
                    Toggle(isOn: $state.isItalic) { Image(systemName: "italic") }
                        .toggleStyle(.button).help("Italic (⌘I)")
                    Toggle(isOn: $state.isUnderlined) { Image(systemName: "underline") }
                        .toggleStyle(.button).help("Underline (⌘U)")
                }
            }
            
            // Live preview reflects current settings.
            VStack(alignment: .leading, spacing: 4) {
                Text("Preview").font(.caption).foregroundStyle(.secondary)
                Text("AaBbCc")
                    .font(.custom(state.fontName, size: min(state.fontSize, 24)))
                    .fontWeight(state.isBold ? .bold : .regular)
                    .italic(state.isItalic)
                    .underline(state.isUnderlined)
                    .foregroundStyle(state.foregroundColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(4)
                    .background(Color.white)
                    .cornerRadius(4)
            }
        }
        .padding(10)
        .frame(width: 180, height: 200)
    }
}

// MARK: - Tool Palette View

/// Grid of tool buttons and a compact options area that changes depending
/// on the selected tool (e.g., brush size, line width, shape style).
struct ToolPaletteView: View {
    @ObservedObject var state = ToolPaletteState.shared
    
    /// 8 rows × 2 columns to mirror classic MS Paint layout.
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
            // Tool buttons
            ForEach(0..<toolRows.count, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(toolRows[row]) { tool in
                        ToolButton(tool: tool, isSelected: state.currentTool == tool) {
                            state.currentTool = tool
                        }
                    }
                }
            }
            
            Divider().padding(.vertical, 4)
            // Contextual options for the current tool
            toolOptionsView
            Spacer()
        }
        .padding(6)
        .frame(width: 66, height: 420)
    }
    
    /// Small contextual UI for the selected tool.
    @ViewBuilder
    var toolOptionsView: some View {
        switch state.currentTool {
        case .eraser, .airbrush:
            VStack(spacing: 2) {
                Text("Size").font(.caption2).foregroundStyle(.secondary)
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
            VStack(spacing: 2) {
                Text("Size: \(Int(state.brushSize.rounded(.down)))").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $state.brushSize, in: 2...20, step:1).frame(width: 50)
                Text("Shape").font(.caption2).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.fixed(20)), GridItem(.fixed(20))], spacing: 2) {
                    ForEach(BrushShape.allCases, id: \.rawValue) { shape in
                        Button { state.brushShape = shape } label: {
                            brushShapeIcon(shape).frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .background(state.brushShape == shape ? Color.accentColor.opacity(0.3) : Color.clear)
                        .cornerRadius(2)
                    }
                }
            }
        case .line, .curve:
            VStack(spacing: 2) {
                Text("Width").font(.caption2).foregroundStyle(.secondary)
                ForEach([1, 2, 3, 4, 5], id: \.self) { width in
                    Button { state.lineWidth = CGFloat(width) } label: {
                        Rectangle()
                            .fill(state.lineWidth == CGFloat(width) ? Color.accentColor : Color.primary)
                            .frame(width: 40, height: CGFloat(width))
                    }
                    .buttonStyle(.plain)
                }
            }
        case .rectangle, .ellipse, .roundedRectangle, .polygon:
            VStack(spacing: 2) {
                Text("Style").font(.caption2).foregroundStyle(.secondary)
                ForEach(ShapeStyle.allCases, id: \.rawValue) { style in
                    Button { state.shapeStyle = style } label: {
                        shapeStyleIcon(style).frame(width: 40, height: 20)
                    }
                    .buttonStyle(.plain)
                    .background(state.shapeStyle == style ? Color.accentColor.opacity(0.3) : Color.clear)
                    .cornerRadius(2)
                }
            }
        case .magnifier:
            VStack(spacing: 2) {
                Text("Zoom").font(.caption2).foregroundStyle(.secondary)
                ForEach([1, 2, 4, 6, 8], id: \.self) { zoom in
                    Button { state.zoomLevel = CGFloat(zoom) } label: {
                        Text("\(zoom)×").font(.caption).frame(width: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(state.zoomLevel == CGFloat(zoom) ? .accentColor : .secondary)
                }
            }
        default:
            VStack(spacing: 4) {
                Text("Size: \(Int(state.brushSize))").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $state.brushSize, in: 1...20, step: 1).frame(width: 50)
            }
        }
    }
    
    /// Simple icons to visualize brush shapes.
    func brushShapeIcon(_ shape: BrushShape) -> some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
            switch shape {
            case .circle: context.fill(Circle().path(in: rect), with: .color(.primary))
            case .square: context.fill(Rectangle().path(in: rect), with: .color(.primary))
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
    
    /// Simple icons to visualize shape styles.
    func shapeStyleIcon(_ style: ShapeStyle) -> some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
            switch style {
            case .outline: context.stroke(Rectangle().path(in: rect), with: .color(.primary), lineWidth: 1)
            case .filledWithOutline:
                context.fill(Rectangle().path(in: rect), with: .color(.secondary))
                context.stroke(Rectangle().path(in: rect), with: .color(.primary), lineWidth: 1)
            case .filledNoOutline: context.fill(Rectangle().path(in: rect), with: .color(.primary))
            }
        }
    }
}

/// Small tool button with selection highlighting and help tooltip.
struct ToolButton: View {
    let tool: Tool
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: tool.icon).font(.system(size: 14)).frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .help("\(tool.rawValue) (\(tool.shortcut))")
    }
}

// MARK: - Color Palette View

/// The main color palette showing foreground/background swatches,
/// a default color grid, and a button to show the custom colors palette.
struct ColorPaletteView: View {
    @ObservedObject var state = ToolPaletteState.shared
    @State private var showingColorPicker = false
    
    // Two rows of default colors reminiscent of classic palettes.
    let topColors: [Color] = [
        Color(nsColor: NSColor(red: 0, green: 0, blue: 0, alpha: 1)),
        Color(nsColor: NSColor(red: 128/255, green: 128/255, blue: 128/255, alpha: 1)),
        Color(nsColor: NSColor(red: 128/255, green: 0, blue: 0, alpha: 1)),
        Color(nsColor: NSColor(red: 128/255, green: 128/255, blue: 0, alpha: 1)),
        Color(nsColor: NSColor(red: 0, green: 128/255, blue: 0, alpha: 1)),
        Color(nsColor: NSColor(red: 0, green: 128/255, blue: 128/255, alpha: 1)),
        Color(nsColor: NSColor(red: 0, green: 0, blue: 128/255, alpha: 1)),
        Color(nsColor: NSColor(red: 128/255, green: 0, blue: 128/255, alpha: 1)),
        Color(nsColor: NSColor(red: 128/255, green: 128/255, blue: 0, alpha: 1)),
        Color(nsColor: NSColor(red: 0, green: 64/255, blue: 64/255, alpha: 1)),
        Color(nsColor: NSColor(red: 0, green: 0, blue: 255/255, alpha: 1)),
        Color(nsColor: NSColor(red: 0, green: 128/255, blue: 255/255, alpha: 1)),
        Color(nsColor: NSColor(red: 128/255, green: 0, blue: 255/255, alpha: 1)),
        Color(nsColor: NSColor(red: 128/255, green: 0, blue: 64/255, alpha: 1)),
    ]
    
    let bottomColors: [Color] = [
        Color(nsColor: NSColor(red: 1, green: 1, blue: 1, alpha: 1)),
        Color(nsColor: NSColor(red: 192/255, green: 192/255, blue: 192/255, alpha: 1)),
        Color(nsColor: NSColor(red: 1, green: 0, blue: 0, alpha: 1)),
        Color(nsColor: NSColor(red: 1, green: 1, blue: 0, alpha: 1)),
        Color(nsColor: NSColor(red: 0, green: 1, blue: 0, alpha: 1)),
        Color(nsColor: NSColor(red: 0, green: 1, blue: 1, alpha: 1)),
        Color(nsColor: NSColor(red: 0, green: 0, blue: 1, alpha: 1)),
        Color(nsColor: NSColor(red: 1, green: 0, blue: 1, alpha: 1)),
        Color(nsColor: NSColor(red: 1, green: 1, blue: 128/255, alpha: 1)),
        Color(nsColor: NSColor(red: 128/255, green: 1, blue: 128/255, alpha: 1)),
        Color(nsColor: NSColor(red: 128/255, green: 1, blue: 1, alpha: 1)),
        Color(nsColor: NSColor(red: 128/255, green: 128/255, blue: 1, alpha: 1)),
        Color(nsColor: NSColor(red: 1, green: 128/255, blue: 128/255, alpha: 1)),
        Color(nsColor: NSColor(red: 1, green: 128/255, blue: 1, alpha: 1)),
    ]
    
    var body: some View {
        HStack(spacing: 10) {
            // Foreground/Background color indicator
            ZStack(alignment: .topLeading) {
                Rectangle().fill(state.backgroundColor).frame(width: 20, height: 20)
                    .border(Color.primary.opacity(0.4), width: 1).offset(x: 10, y: 10)
                Rectangle().fill(state.foregroundColor).frame(width: 20, height: 20)
                    .border(Color.primary.opacity(0.6), width: 1)
            }
            .frame(width: 34, height: 34)
            .onTapGesture(count: 2) {
                // Double-click swaps colors.
                let temp = state.foregroundColor
                state.foregroundColor = state.backgroundColor
                state.backgroundColor = temp
            }
            .help("Double-click to swap colors")
            
            Divider().frame(height: 36)
            
            // Default color grid
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
            
            Divider().frame(height: 36)
            
            // Custom colors button
            Button {
                ToolPaletteController.shared.toggleCustomColors()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 16))
                    Text("Custom")
                        .font(.caption2)
                }
                .frame(width: 44, height: 36)
            }
            .buttonStyle(.bordered)
            .help("Show custom colors palette")
        }
        .padding(10)
        .frame(height: 60)
    }
}

// MARK: - Color Picker with Custom Save

/// A ColorPicker that automatically saves newly chosen colors into the shared
/// custom colors list (with duplicate suppression).
struct ColorPickerWithCustomSave: View {
    @Binding var selection: Color
    @ObservedObject var state = ToolPaletteState.shared
    @State private var previousColor: Color = .black
    
    var body: some View {
        ColorPicker("", selection: $selection)
            .labelsHidden()
            .onChange(of: selection) { newColor in
                // Add to custom colors when user picks a new color
                // (only if it's different from the previous one)
                if !colorsAreEqual(newColor, previousColor) {
                    state.addCustomColor(newColor)
                    previousColor = newColor
                }
            }
            .onAppear {
                previousColor = selection
            }
    }
    
    /// Local color equality with a tolerance to avoid noisy re-saves.
    private func colorsAreEqual(_ c1: Color, _ c2: Color) -> Bool {
        let ns1 = NSColor(c1).usingColorSpace(.deviceRGB)
        let ns2 = NSColor(c2).usingColorSpace(.deviceRGB)
        guard let ns1, let ns2 else { return false }
        return abs(ns1.redComponent - ns2.redComponent) < 0.01 &&
               abs(ns1.greenComponent - ns2.greenComponent) < 0.01 &&
               abs(ns1.blueComponent - ns2.blueComponent) < 0.01
    }
}

// MARK: - Custom Colors Palette View

/// A compact palette that shows up to 28 custom colors in two rows,
/// with a ColorPicker to add new ones and a button to clear all.
struct CustomColorsPaletteView: View {
    @ObservedObject var state = ToolPaletteState.shared
    
    private let columns = 14
    
    var body: some View {
        VStack(spacing: 10) {
            // Color picker row
            HStack(spacing: 8) {
                Text("Pick Color:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                ColorPickerWithCustomSave(selection: $state.foregroundColor)
                
                Spacer()
                
                Text("\(state.customColors.count)/28")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            
            Divider()
            
            // Custom colors grid
            if state.customColors.isEmpty {
                VStack(spacing: 4) {
                    Text("No custom colors yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Use the color picker above to add colors")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(height: 32)
            } else {
                VStack(spacing: 1) {
                    // First row
                    HStack(spacing: 1) {
                        ForEach(0..<columns, id: \.self) { i in
                            if i < state.customColors.count {
                                CustomColorGridButton(color: state.customColors[i], index: i)
                            } else {
                                EmptyColorSlot()
                            }
                        }
                    }
                    // Second row
                    HStack(spacing: 1) {
                        ForEach(0..<columns, id: \.self) { i in
                            let index = i + columns
                            if index < state.customColors.count {
                                CustomColorGridButton(color: state.customColors[index], index: index)
                            } else {
                                EmptyColorSlot()
                            }
                        }
                    }
                }
            }
            
            // Clear button
            HStack {
                Spacer()
                Button("Clear All") {
                    state.customColors.removeAll()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(state.customColors.isEmpty)
            }
        }
        .padding(10)
        .frame(width: 260, height: 110)
    }
}

/// An interactive color swatch that can set foreground (left click),
/// background (Ctrl-click), or be removed via context menu.
struct CustomColorGridButton: View {
    let color: Color
    let index: Int
    @ObservedObject var state = ToolPaletteState.shared
    
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 14, height: 14)
            .border(Color.primary.opacity(0.3), width: 0.5)
            .onTapGesture {
                state.foregroundColor = color
            }
            .simultaneousGesture(
                TapGesture().modifiers(.control).onEnded {
                    state.backgroundColor = color
                }
            )
            .contextMenu {
                Button("Set as Foreground") {
                    state.foregroundColor = color
                }
                Button("Set as Background") {
                    state.backgroundColor = color
                }
                Divider()
                Button("Remove", role: .destructive) {
                    state.customColors.remove(at: index)
                }
            }
            .help("Left-click: foreground, Ctrl-click: background, Right-click: options")
    }
}

/// Empty placeholder slot for the custom colors grid.
struct EmptyColorSlot: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.1))
            .frame(width: 14, height: 14)
            .border(Color.primary.opacity(0.1), width: 0.5)
    }
}

/// A default palette color swatch; left click sets foreground, Ctrl-click sets background.
struct ColorGridButton: View {
    let color: Color
    @ObservedObject var state = ToolPaletteState.shared
    
    var body: some View {
        Rectangle().fill(color).frame(width: 14, height: 14).border(Color.primary.opacity(0.2), width: 0.5)
            .onTapGesture { state.foregroundColor = color }
            .simultaneousGesture(TapGesture().modifiers(.control).onEnded { state.backgroundColor = color })
            .help("Left-click: foreground, Ctrl-click: background")
    }
}

// MARK: - Navigator View

/// Displays a live preview of the current canvas (if provided by the editor),
/// typically scaled down, in a small floating panel.
struct NavigatorView: View {
    @ObservedObject var state = ToolPaletteState.shared
    
    var body: some View {
        VStack(spacing: 8) {
            if let image = state.navigatorImage {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 160, maxHeight: 120).border(Color.primary.opacity(0.2), width: 1)
            } else {
                Rectangle().fill(Color.secondary.opacity(0.1)).frame(width: 160, height: 120)
                    .overlay(Text("No canvas").font(.caption).foregroundStyle(.secondary))
            }
        }
        .padding(8)
        .frame(width: 180, height: 140)
    }
}

/// Preview
#Preview {
    ToolPaletteView()
}

#Preview {
    ColorPaletteView()
    CustomColorsPaletteView()
    NavigatorView()
    TextOptionsView()
}
