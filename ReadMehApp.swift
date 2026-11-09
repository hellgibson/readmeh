import SwiftUI

@main
struct ReadMehApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var speech = SpeechPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(speech)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.77, green: 0.91, blue: 0.46))
        }
    }
}
