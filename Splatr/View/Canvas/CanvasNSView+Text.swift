//
//  CanvasNSView+Text.swift
//  Splatr
//
//  Created by Kushagra Srivastava on 1/16/26.
//

import AppKit

// MARK: - Text Tool

extension CanvasNSView {
    
    /// Places an NSTextField at the click point for inline text entry.
    func handleTextTool(at point: NSPoint) {
        if let tf = textField {
            commitText()
            tf.removeFromSuperview()
            textField = nil
        }
        
        textInsertPoint = point
        
        let state = ToolPaletteState.shared
        let font = NSFont(name: state.fontName, size: state.fontSize) ?? NSFont.systemFont(ofSize: state.fontSize)
        
        let tf = NSTextField(frame: NSRect(x: point.x, y: point.y - state.fontSize - 4, width: 300, height: state.fontSize + 8))
        tf.isBordered = true
        tf.backgroundColor = .white
        tf.font = font
        tf.textColor = currentColor
        tf.target = self
        tf.action = #selector(textFieldEntered(_:))
        tf.focusRingType = .none
        tf.lineBreakMode = .byWordWrapping
        tf.usesSingleLineMode = false
        tf.cell?.wraps = true
        tf.cell?.isScrollable = false
        addSubview(tf)
        tf.becomeFirstResponder()
        textField = tf
        hasActiveTextBox = true
    }

    /// Called when the user presses Return in the text field.
    @objc func textFieldEntered(_ sender: NSTextField) {
        commitText()
        sender.removeFromSuperview()
        textField = nil
        hasActiveTextBox = false
    }

    /// Renders the text field's contents into the canvas image.
    func commitText() {
        guard let tf = textField, let image = canvasImage else { return }
        let rect = tf.frame
        let text = tf.stringValue
        guard !text.isEmpty else { return }

        let newImage = NSImage(size: canvasSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: canvasSize))

        var attrs: [NSAttributedString.Key: Any] = [
            .font: tf.font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: tf.textColor ?? NSColor.black
        ]
        let state = ToolPaletteState.shared
        if state.isUnderlined {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        let attrString = NSAttributedString(string: text, attributes: attrs)
        attrString.draw(in: rect)
        newImage.unlockFocus()
        canvasImage = newImage
        textInsertPoint = nil
        saveToDocument(actionName: "Text")
    }

    /// Renders the contents of an NSTextField to an NSImage.
    func renderTextFieldToImage(_ tf: NSTextField) -> NSImage {
        tf.sizeToFit()
        var frame = tf.frame
        frame.size.width = max(frame.size.width, tf.intrinsicContentSize.width)
        frame.size.height = tf.intrinsicContentSize.height
        tf.frame = frame

        let size = tf.frame.size
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrString = NSAttributedString(string: tf.stringValue, attributes: [
            .font: tf.font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: tf.textColor ?? NSColor.black
        ])
        attrString.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        return image
    }
}
