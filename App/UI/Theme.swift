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
    static let background = adaptive(UIColor(red: 0.035, green: 0.055, blue: 0.05, alpha: 1), UIColor(red: 0.95, green: 0.96, blue: 0.94, alpha: 1))
    static let surface = adaptive(UIColor(red: 0.07, green: 0.09, blue: 0.08, alpha: 1), .white)
    static let mint = adaptive(UIColor(red: 0.24, green: 0.84, blue: 0.56, alpha: 1), UIColor(red: 0.0, green: 0.40, blue: 0.25, alpha: 1))
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
