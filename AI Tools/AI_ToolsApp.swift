//
//  AI_ToolsApp.swift
//  AI Tools
//
//  Created by Ben Milford on 27/02/2026.
//

import SwiftUI

@main
struct AI_ToolsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(AppTheme.brandTint)
                .background(AppTheme.canvasBackground)
        }
#if os(macOS)
        .defaultSize(width: 1320, height: 860)
#endif
    }
}
