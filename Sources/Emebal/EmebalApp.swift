import SwiftUI

@main
struct EmebalApp: App {
    var body: some Scene {
        MenuBarExtra("Emebal", systemImage: "character.bubble") {
            Text("Emebal")
            Divider()
            Button("Quit Emebal") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
