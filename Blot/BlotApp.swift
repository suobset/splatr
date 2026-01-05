//
//  BlotApp.swift
//  Blot
//
//  Created by Kushagra Srivastava on 1/2/26.
//

import SwiftUI
import WelcomeWindow

@main
struct BlotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) var openWindow
    
    // MARK: - Welcome Window  Body
    var body: some Scene {
        WelcomeWindow(
            // Add two action buttons below the app icon
            actions : { dismiss in
                WelcomeButton(
                    iconName: "paintbrush",
                    title: "New Canvas",
                    action: {
                        NSDocumentController.shared.newDocument(nil)
                        dismiss()
                    }
                )
                WelcomeButton(
                    iconName: "doc.on.doc",
                    title: "Open Existing Canvas/Image",
                    action: {
                        NSDocumentController.shared.openDocument(nil)
                        dismiss()
                    }
                )
            },
            onDrop: { url, dismiss in
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in
                    dismiss()
                }
            }
        )
        DocumentGroup(newDocument: BlotDocument()) { file in
            ContentView(document: file.$document)
                .frame(minWidth: 900, minHeight: 700)
        }
        .defaultSize(width: 950, height: 750)
        .commands {
            // Replace default About menu
            CommandGroup(replacing: .appInfo) {
                Button("About Blot") {
                    AboutWindowController.shared.showAboutWindow()
                }
            }
            
            // File menu - Export As
            CommandGroup(after: .saveItem) {
                Menu("Export As") {
                    Button("PNG...") {
                        NotificationCenter.default.post(name: .exportPNG, object: nil)
                    }
                    Button("JPEG...") {
                        NotificationCenter.default.post(name: .exportJPEG, object: nil)
                    }
                    Button("TIFF...") {
                        NotificationCenter.default.post(name: .exportTIFF, object: nil)
                    }
                    Button("BMP...") {
                        NotificationCenter.default.post(name: .exportBMP, object: nil)
                    }
                    Button("GIF...") {
                        NotificationCenter.default.post(name: .exportGIF, object: nil)
                    }
                    Button("PDF...") {
                        NotificationCenter.default.post(name: .exportPDF, object: nil)
                    }
                }
            }
            
            // Edit menu additions
            CommandGroup(after: .undoRedo) {
                Button("Clear Canvas") {
                    NotificationCenter.default.post(name: .clearCanvas, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
            }
            
            // Add to existing View menu
            CommandGroup(after: .toolbar) {
                Divider()
                
                Button("Show Tools Palette") {
                    ToolPaletteController.shared.showToolPalette()
                }
                .keyboardShortcut("1", modifiers: [.command])
                
                Button("Show Colors Palette") {
                    ToolPaletteController.shared.showColorPalette()
                }
                .keyboardShortcut("2", modifiers: [.command])
                
                Button("Show Navigator") {
                    ToolPaletteController.shared.showNavigator()
                }
                .keyboardShortcut("3", modifiers: [.command])
                
                Divider()
                
                Button("Show All Palettes") {
                    ToolPaletteController.shared.showAllPalettes()
                }
                .keyboardShortcut("0", modifiers: [.command])
                
                Button("Hide All Palettes") {
                    ToolPaletteController.shared.hideAllPalettes()
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            }
            
            // Tools menu with all 16 XP Paint tools
            CommandMenu("Tools") {
                Section("Selection") {
                    Button("Free-Form Select") { ToolPaletteState.shared.currentTool = .freeFormSelect }
                        .keyboardShortcut("s", modifiers: [])
                    Button("Select") { ToolPaletteState.shared.currentTool = .rectangleSelect }
                        .keyboardShortcut("s", modifiers: [.shift])
                }
                
                Section("Drawing") {
                    Button("Pencil") { ToolPaletteState.shared.currentTool = .pencil }
                        .keyboardShortcut("p", modifiers: [])
                    Button("Brush") { ToolPaletteState.shared.currentTool = .brush }
                        .keyboardShortcut("b", modifiers: [])
                    Button("Airbrush") { ToolPaletteState.shared.currentTool = .airbrush }
                        .keyboardShortcut("a", modifiers: [])
                }
                
                Section("Editing") {
                    Button("Eraser") { ToolPaletteState.shared.currentTool = .eraser }
                        .keyboardShortcut("e", modifiers: [])
                    Button("Fill With Color") { ToolPaletteState.shared.currentTool = .fill }
                        .keyboardShortcut("g", modifiers: [])
                    Button("Pick Color") { ToolPaletteState.shared.currentTool = .colorPicker }
                        .keyboardShortcut("i", modifiers: [])
                }
                
                Section("View") {
                    Button("Magnifier") { ToolPaletteState.shared.currentTool = .magnifier }
                        .keyboardShortcut("z", modifiers: [])
                    Button("Text") { ToolPaletteState.shared.currentTool = .text }
                        .keyboardShortcut("t", modifiers: [])
                }
                
                Section("Shapes") {
                    Button("Line") { ToolPaletteState.shared.currentTool = .line }
                        .keyboardShortcut("l", modifiers: [])
                    Button("Curve") { ToolPaletteState.shared.currentTool = .curve }
                        .keyboardShortcut("c", modifiers: [])
                    Button("Rectangle") { ToolPaletteState.shared.currentTool = .rectangle }
                        .keyboardShortcut("r", modifiers: [])
                    Button("Polygon") { ToolPaletteState.shared.currentTool = .polygon }
                        .keyboardShortcut("y", modifiers: [])
                    Button("Ellipse") { ToolPaletteState.shared.currentTool = .ellipse }
                        .keyboardShortcut("o", modifiers: [])
                    Button("Rounded Rectangle") { ToolPaletteState.shared.currentTool = .roundedRectangle }
                        .keyboardShortcut("r", modifiers: [.shift])
                }
                
                Divider()
                
                Button("Increase Brush Size") {
                    ToolPaletteState.shared.brushSize = min(50, ToolPaletteState.shared.brushSize + 2)
                }
                .keyboardShortcut("]", modifiers: [])
                
                Button("Decrease Brush Size") {
                    ToolPaletteState.shared.brushSize = max(1, ToolPaletteState.shared.brushSize - 2)
                }
                .keyboardShortcut("[", modifiers: [])
            }
            
            // Image menu
            CommandMenu("Image") {
                Button("Resize Canvas...") {
                    NotificationCenter.default.post(name: .resizeCanvas, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Flip Horizontal") {
                    NotificationCenter.default.post(name: .flipHorizontal, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                
                Button("Flip Vertical") {
                    NotificationCenter.default.post(name: .flipVertical, object: nil)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Invert Colors") {
                    NotificationCenter.default.post(name: .invertColors, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let clearCanvas = Notification.Name("clearCanvas")
    static let resizeCanvas = Notification.Name("resizeCanvas")
    static let invertColors = Notification.Name("invertColors")
    static let flipHorizontal = Notification.Name("flipHorizontal")
    static let flipVertical = Notification.Name("flipVertical")
    static let canvasDidUpdate = Notification.Name("canvasDidUpdate")
    static let exportPNG = Notification.Name("exportPNG")
    static let exportJPEG = Notification.Name("exportJPEG")
    static let exportTIFF = Notification.Name("exportTIFF")
    static let exportBMP = Notification.Name("exportBMP")
    static let exportGIF = Notification.Name("exportGIF")
    static let exportPDF = Notification.Name("exportPDF")
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            ToolPaletteController.shared.showAllPalettes()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        ToolPaletteController.shared.showPalettesIfNeeded()
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        ToolPaletteController.shared.hidePalettesTemporarily()
    }
}
