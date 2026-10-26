import SwiftUI

@main
struct TandemApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            LibraryView(model: model)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.48, green: 0.95, blue: 0.77))
        }
    }
}
