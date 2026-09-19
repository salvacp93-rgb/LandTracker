import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        default:
            (r, g, b) = (0, 122, 255)
        }

        // Palette colors resolve to the adaptive AppTheme tokens (same light value, lighter in
        // dark mode) so tints, dots and text keep enough contrast on dark surfaces.
        if let token = Self.appThemeToken(forHex: cleaned) {
            self = token
            return
        }

        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    private static func appThemeToken(forHex hex: String) -> Color? {
        switch hex.uppercased() {
        case "5C7048": return AppTheme.olive
        case "BF5B34": return AppTheme.clay
        case "B8842C": return AppTheme.warning
        case "A34A3E": return AppTheme.negative
        case "8B6B2E": return AppTheme.highlight
        case "6A7045": return AppTheme.wordmark
        case "8E8A82": return AppTheme.neutral
        default: return nil
        }
    }
}

struct GroupColorPalette {
    static let hexValues = [
        "5C7048",
        "BF5B34",
        "B8842C",
        "A34A3E",
        "8B6B2E",
        "6A7045",
        "6F8791",
        "8E8A82"
    ]
}
