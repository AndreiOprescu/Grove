import SwiftUI
import GroveCore

@main
struct GroveApp: App {
    var body: some Scene {
        WindowGroup(id: "main") {
            Text("Grove \(GroveCore.version)")
                .font(.system(.largeTitle, design: .serif))
                .frame(minWidth: 960, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
    }
}
