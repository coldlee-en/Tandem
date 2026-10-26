import SwiftUI

enum TandemTheme {
    static let background = Color(red: 0.045, green: 0.065, blue: 0.09)
    static let surface = Color(red: 0.075, green: 0.10, blue: 0.135)
    static let mint = Color(red: 0.50, green: 0.93, blue: 0.77)
    static let muted = Color(red: 0.57, green: 0.64, blue: 0.70)
}

struct SystemMark: View {
    let is3DS: Bool
    var body: some View {
        Image(systemName: is3DS ? "rectangle.split.1x2" : "gamecontroller")
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(TandemTheme.mint)
    }
}
