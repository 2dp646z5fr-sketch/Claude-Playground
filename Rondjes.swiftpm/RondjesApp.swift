import SwiftUI

@main
struct RondjesApp: App {
    @StateObject private var store = LoopStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
