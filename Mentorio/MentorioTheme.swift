import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "Системная"
    case light = "Светлая"
    case dark = "Темная"
    
    var id: String { self.rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum MentorioTheme {
    static let accent = Color(red: 1.0, green: 0.6706, blue: 0.5686) // Peach
    
    static let background = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? .black : UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1.0)
    })
    
    static let card = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 1.0, alpha: 0.08) : .white
    })
    
    static let stroke = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 1.0, alpha: 0.14) : UIColor(white: 0.0, alpha: 0.18)
    })
    
    static let primaryText = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? .white : .black
    })
    
    static let secondaryText = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 1.0, alpha: 0.6) : UIColor(white: 0.0, alpha: 0.6)
    })
}
