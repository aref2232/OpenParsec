import SwiftUI

@main
struct OpenParsecApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            // macOS menu commands if you want to add them
            CommandGroup(replacing: .appInfo) {
                Button("About OpenParsec") {
                    // Show About panel or custom UI
                }
            }
        }
    }
}
