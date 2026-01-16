//
//  CanvasView.swift
//  splatr
//
//  Created by Kushagra Srivastava on 1/2/26.
//

import SwiftUI
import AppKit

/// SwiftUI wrapper for an AppKit-based canvas view that handles pixel drawing,
/// tools (pencil, brush, eraser, airbrush, shapes, selection, text, color picker),
/// resize handles, and undo integration. The view synchronizes with the document
/// model and notifies the Navigator palette of updates.
struct CanvasView: NSViewRepresentable {
    @Binding var document: splatrDocument
    /// Foreground drawing color (converted from SwiftUI Color by the caller).
    var currentColor: NSColor
    /// Base brush size (interpreted per tool).
    var brushSize: CGFloat
    /// Currently selected tool from the shared tool palette state.
    var currentTool: Tool
    /// Whether to render resize handles and accept resize drags.
    var showResizeHandles: Bool
    /// Callback to request a canvas resize (delegated to ContentView).
    var onCanvasResize: (CGSize) -> Void
    /// Callback to update the Navigator image after changes.
    var onCanvasUpdate: (NSImage) -> Void
    /// Undo manager injected from SwiftUI environment for registration.
    @Environment(\.undoManager) var undoManager
    
    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.delegate = context.coordinator
        view.currentColor = currentColor
        view.brushSize = brushSize
        view.currentTool = currentTool
        view.showResizeHandles = showResizeHandles
        
        // Load from document - document is source of truth
        // Notify navigator on initial load
        view.reloadFromDocument(data: document.canvasData, size: document.canvasSize, notifyNavigator: true)
        return view
    }
    
    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        // Keep undo manager up-to-date for new windows/contexts.
        context.coordinator.undoManager = undoManager
        
        // Propagate tool and UI state into the NSView.
        nsView.currentColor = currentColor
        nsView.brushSize = brushSize
        nsView.currentTool = currentTool
        nsView.showResizeHandles = showResizeHandles
        
        // Detect external document changes (undo/redo/clear/flip/etc.) and reload image.
        if nsView.documentDataHash != document.canvasData.hashValue ||
           nsView.canvasSize != document.canvasSize {
            // Don't notify during update - just reload the image
            nsView.reloadFromDocument(data: document.canvasData, size: document.canvasSize, notifyNavigator: false)
        }
        
        // Request a redraw to reflect any state changes.
        nsView.setNeedsDisplay(nsView.bounds)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(document: $document, undoManager: undoManager, onCanvasResize: onCanvasResize, onCanvasUpdate: onCanvasUpdate)
    }
    
    /// Mediates between the NSView and SwiftUI: writes to the document binding,
    /// registers undo, and forwards callbacks to ContentView.
    class Coordinator {
        var document: Binding<splatrDocument>
        var undoManager: UndoManager?
        var onCanvasResize: (CGSize) -> Void
        var onCanvasUpdate: (NSImage) -> Void
        
        init(document: Binding<splatrDocument>, undoManager: UndoManager?, onCanvasResize: @escaping (CGSize) -> Void, onCanvasUpdate: @escaping (NSImage) -> Void) {
            self.document = document
            self.undoManager = undoManager
            self.onCanvasResize = onCanvasResize
            self.onCanvasUpdate = onCanvasUpdate
        }
        
        /// Saves new image data into the document and updates the Navigator without undo registration.
        func saveToDocument(_ data: Data, image: NSImage) {
            document.wrappedValue.canvasData = data
            onCanvasUpdate(image)
        }
        
        /// Requests the outer SwiftUI view to perform a canvas resize.
        func requestCanvasResize(_ size: CGSize) {
            onCanvasResize(size)
        }
        
        /// Updates the shared foreground color after a color pick operation.
        func colorPicked(_ color: NSColor) {
            DispatchQueue.main.async {
                ToolPaletteState.shared.foregroundColor = Color(nsColor: color)
            }
        }
        
        /// Saves new image data into the document and registers an undo operation.
        func saveWithUndo(newData: Data, image: NSImage, actionName: String) {
            guard let undoManager = undoManager else {
                saveToDocument(newData, image: image)
                return
            }
            
            let oldData = document.wrappedValue.canvasData
            guard oldData != newData else { return }
            
            // Register undo to restore previous canvas data and navigator image.
            undoManager.registerUndo(withTarget: self) { [weak self] _ in
                guard let self = self else { return }
                self.document.wrappedValue.canvasData = oldData
                if let img = NSImage(data: oldData) {
                    self.onCanvasUpdate(img)
                }
            }
            undoManager.setActionName(actionName)
            
            document.wrappedValue.canvasData = newData
            onCanvasUpdate(image)
        }
    }
}
