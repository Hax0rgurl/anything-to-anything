import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct CodexMediaConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Codex Media Converter", id: "converter") {
            ContentView()
        }
        .defaultSize(width: 720, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
