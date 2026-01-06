//
//  splatrApp.swift
//  splatr
//
//  Created by Kushagra Srivastava on 1/2/26.
//

import SwiftUI

@main
struct splatrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        
        DocumentGroup(newDocument: splatrDocument()) { file in
            ContentView(document: file.$document)
                .frame(minWidth: 640, minHeight: 480)
        }
        .defaultSize(width: 950, height: 750)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About splatr") {
                    AboutWindowController.shared.showAboutWindow()
                }
            }
            
            CommandGroup(after: .saveItem) {
                Menu("Export As") {
                    Button("PNG...") { NotificationCenter.default.post(name: .exportPNG, object: nil) }
                    Button("JPEG...") { NotificationCenter.default.post(name: .exportJPEG, object: nil) }
                    Button("TIFF...") { NotificationCenter.default.post(name: .exportTIFF, object: nil) }
                    Button("BMP...") { NotificationCenter.default.post(name: .exportBMP, object: nil) }
                    Button("GIF...") { NotificationCenter.default.post(name: .exportGIF, object: nil) }
                    Button("PDF...") { NotificationCenter.default.post(name: .exportPDF, object: nil) }
                }
            }
            
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    if let undoManager = NSApp.keyWindow?.undoManager, undoManager.canUndo {
                        undoManager.undo()
                    }
                }
                .keyboardShortcut("z", modifiers: .command)
                
                Button("Redo") {
                    if let undoManager = NSApp.keyWindow?.undoManager, undoManager.canRedo {
                        undoManager.redo()
                    }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Clear Canvas") {
                    NotificationCenter.default.post(name: .clearCanvas, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
            }
            
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
                
                Button("Show Text Options") {
                    ToolPaletteController.shared.showTextOptions()
                }
                .keyboardShortcut("4", modifiers: [.command])
                
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
            
            // Format menu for text styling shortcuts
            CommandMenu("Format") {
                Button("Bold") {
                    ToolPaletteState.shared.isBold.toggle()
                }
                .keyboardShortcut("b", modifiers: [.command])
                
                Button("Italic") {
                    ToolPaletteState.shared.isItalic.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command])
                
                Button("Underline") {
                    ToolPaletteState.shared.isUnderlined.toggle()
                }
                .keyboardShortcut("u", modifiers: [.command])
                
                Divider()
                
                Button("Bigger") {
                    ToolPaletteState.shared.fontSize = min(200, ToolPaletteState.shared.fontSize + 2)
                }
                .keyboardShortcut("+", modifiers: [.command, .shift])
                
                Button("Smaller") {
                    ToolPaletteState.shared.fontSize = max(1, ToolPaletteState.shared.fontSize - 2)
                }
                .keyboardShortcut("-", modifiers: [.command])
                
                Divider()
                
                Button("Show Text Options...") {
                    ToolPaletteController.shared.showTextOptions()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            
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
        WelcomeWindowController.shared.show()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        
        // Ignore if it's the welcome window itself or a panel
        if closingWindow === WelcomeWindowController.shared.window {
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Check if any document windows exist
            let hasDocumentWindows = NSDocumentController.shared.documents.count > 0
            let hasVisibleDocuments = NSApp.windows.contains { window in
                window.isVisible &&
                window.windowController?.document != nil
            }
            
            if !hasDocumentWindows && !hasVisibleDocuments {
                WelcomeWindowController.shared.show()
            }
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
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WelcomeWindowController.shared.show()
        }
        return true
    }
    
    func applicationDidUpdate(_ notification: Notification) {
        let visibleWindows = NSApp.windows.filter {
            $0.isVisible &&
            !$0.className.contains("Welcome") &&
            $0.className != "NSStatusBarWindow" &&
            $0.level == .normal
        }
        
        if visibleWindows.isEmpty {
            _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        }
    }
}
