import SwiftUI

@main
struct TandemApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("appearance") private var appearance = AppearanceChoice.dark.rawValue
    var body: some Scene {
        WindowGroup {
            LibraryView(model: model)
                .preferredColorScheme((AppearanceChoice(rawValue: appearance) ?? .dark).colorScheme)
                .tint(TandemTheme.mint)
        }
    }
}
