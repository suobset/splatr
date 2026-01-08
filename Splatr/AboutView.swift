//
//  AboutView.swift
//  splatr
//
//  Created by Kushagra Srivastava on 1/2/26.
//

import SwiftUI

/// Simple About panel content showing app icon, name, version, author, links, and license.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 24)
            
            // App Icon - load from bundle or fallback to application icon.
            if let iconImage = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                Image(nsImage: iconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 128, height: 128)
            }
            
            Spacer()
                .frame(height: 16)
            
            // App Name
            Text("splatr")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            
            Spacer()
                .frame(height: 4)
            
            // Version (read from Info.plist via Bundle extension)
            Text("Version \(Bundle.main.appVersion)")
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
                Link("github.com/suobset/splatr", destination: URL(string: "https://github.com/suobset/splatr")!)
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

/// A small controller to manage the About window lifecycle and keep a strong
/// reference to the NSWindow to prevent premature deallocation.
class AboutWindowController {
    static let shared = AboutWindowController()
    private var aboutWindow: NSWindow?
    
    /// Shows the About window, creating it if necessary, and brings the app to front.
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
        window.title = "About splatr"
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
