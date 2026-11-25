//
//  TempoApp.swift
//  Tempo
//

import Foundation
import SwiftUI

@main
struct TempoApp: App {
    @State private var engine = MetronomeEngine()

    var body: some Scene {
        WindowGroup {
            MetronomeView()
                .environment(engine)
                .tint(Color.accentColor)
                .task {
                    #if targetEnvironment(simulator)
                    // Simulator-only convenience for screenshots and manual
                    // smoke tests: `simctl launch … -tempo-autostart`.
                    if ProcessInfo.processInfo.arguments.contains("-tempo-autostart") {
                        engine.start()
                    }
                    #endif
                }
        }
    }
}
