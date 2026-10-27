import SwiftUI
import UIKit

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .dark: return .dark; case .light: return .light }
    }
}

enum TandemTheme {
    private static func adaptive(_ dark: UIColor, _ light: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
    static let background = adaptive(UIColor(red: 0.045, green: 0.065, blue: 0.09, alpha: 1), UIColor(red: 0.94, green: 0.96, blue: 0.96, alpha: 1))
    static let surface = adaptive(UIColor(red: 0.075, green: 0.10, blue: 0.135, alpha: 1), .white)
    static let mint = adaptive(UIColor(red: 0.50, green: 0.93, blue: 0.77, alpha: 1), UIColor(red: 0.0, green: 0.39, blue: 0.31, alpha: 1))
    static let muted = adaptive(UIColor(red: 0.57, green: 0.64, blue: 0.70, alpha: 1), UIColor(red: 0.31, green: 0.37, blue: 0.39, alpha: 1))
}

struct SystemMark: View {
    let is3DS: Bool
    var body: some View {
        Image(systemName: is3DS ? "rectangle.split.1x2" : "gamecontroller")
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(TandemTheme.mint)
    }
}
