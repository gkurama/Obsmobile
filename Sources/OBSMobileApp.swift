import SwiftUI

@main
struct OBSMobileApp: App {
    @StateObject private var studio = StudioModel()

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .environmentObject(studio)
                .preferredColorScheme(.dark)
        }
    }
}
