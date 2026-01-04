//
//  AboutView.swift
//  Blot
//
//  Created by Kushagra Srivastava on 1/2/26.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 24)
            
            // App Icon - load from bundle
            if let iconImage = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                Image(nsImage: iconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 128, height: 128)
            }
            
            Spacer()
                .frame(height: 16)
            
            // App Name
            Text("Blot")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            
            Spacer()
                .frame(height: 4)
            
            // Version
            Text("Version 1.0.0")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            
            Spacer()
                .frame(height: 20)
            
            Divider()
                .frame(width: 240)
            
            Spacer()
                .frame(height: 20)
            
            // Description
            Text("A bitmap image editor for macOS.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            Text("Simple. Native. No bloat.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            
            Spacer()
                .frame(height: 20)
            
            // Creator
            Text("Kushagra Srivastava")
                .font(.system(size: 13, weight: .medium))
            
            Link("skushagra.com", destination: URL(string: "https://skushagra.com")!)
                .font(.system(size: 12))
                .padding(.top, 2)
            
            Spacer()
                .frame(height: 16)
            
            // GitHub
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10))
                Link("github.com/suobset/blot", destination: URL(string: "https://github.com/suobset/blot")!)
            }
            .font(.system(size: 11))
            
            Spacer()
                .frame(height: 20)
            
            Divider()
                .frame(width: 240)
            
            Spacer()
                .frame(height: 16)
            
            // License
            Text("MIT License • Open Source")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            
            Spacer()
                .frame(height: 12)
            
            Text("© 2026 Kushagra Srivastava")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
            
            Spacer()
                .frame(height: 20)
        }
        .frame(width: 320, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

class AboutWindowController {
    static let shared = AboutWindowController()
    private var aboutWindow: NSWindow?
    
    func showAboutWindow() {
        if let window = aboutWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Blot"
        window.center()
        window.contentView = NSHostingView(rootView: AboutView())
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        aboutWindow = window
    }
}

#Preview {
    AboutView()
}
