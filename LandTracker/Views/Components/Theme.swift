import SwiftUI
import UIKit
import CoreText

/// Visual design tokens for LandTracker. Light values come from the design canvas
/// ("Blanco limpio" background, olive + clay brand colors). Dark values are derived so the
/// app keeps following the system appearance; the canvas itself only defines the light theme.
enum AppTheme {
    // MARK: Brand colors

    static let olive = Color(light: 0x5C7048, dark: 0x8FA678)
    static let clay = Color(light: 0xBF5B34, dark: 0xD9774F)
    /// Green of the "LandTracker" wordmark.
    static let wordmark = Color(light: 0x6A7045, dark: 0xA3AA78)

    // Deeper variants for the second stop of gradients under white text.
    static let oliveDeep = Color(light: 0x465838, dark: 0x6F8558)
    static let clayDeep = Color(light: 0xA34A28, dark: 0xC26840)
    static let goldDeep = Color(light: 0x6F5524, dark: 0xA88342)

    // MARK: Semantic colors

    static let accent = clay
    static let positive = olive
    static let warning = Color(light: 0xB8842C, dark: 0xD9A94F)
    static let negative = Color(light: 0xA34A3E, dark: 0xD0685A)
    static let highlight = Color(light: 0x8B6B2E, dark: 0xC29B52)
    static let neutral = Color(light: 0x8E8A82, dark: 0x8A857B)

    // MARK: Fills under white text
    //
    // The dynamic tokens above are lightened in dark mode so they read well as text and icons on
    // dark surfaces. That makes white text on top of them fail WCAG AA (2.2 to 4.1:1). Anything
    // that paints a fill behind white text uses these instead: same value in light and dark, all at
    // or above 4.4:1 against white (4.9:1 or more except clayFill, which is the brand accent).

    static let oliveFill = Color(light: 0x5C7048, dark: 0x5C7048)
    static let oliveDeepFill = Color(light: 0x465838, dark: 0x465838)
    static let clayFill = Color(light: 0xBF5B34, dark: 0xBF5B34)
    static let clayDeepFill = Color(light: 0xA34A28, dark: 0xA34A28)
    static let goldFill = Color(light: 0x8B6B2E, dark: 0x8B6B2E)
    static let goldDeepFill = Color(light: 0x6F5524, dark: 0x6F5524)
    static let warningFill = Color(light: 0x8F6410, dark: 0x8F6410)
    static let negativeFill = Color(light: 0xA34A3E, dark: 0xA34A3E)
    static let neutralFill = Color(light: 0x6F6B64, dark: 0x6F6B64)

    /// Label color for buttons that use the dynamic accent (or `negative`) as their fill:
    /// white on the light values, dark ink on the lightened dark values.
    static let onBrand = Color(light: 0xFFFFFF, dark: 0x1C1B18)

    // MARK: Text on light surfaces
    //
    // `warning` and `clay` are 3.3 to 3.8:1 as small text on the light card/background. These are
    // the AA-safe text versions; keep the base tokens for fills, icons and chart marks.

    static let warningText = Color(light: 0x8A6218, dark: 0xD9A94F)
    static let clayText = Color(light: 0xA34A28, dark: 0xD9774F)

    // MARK: Text

    static let ink = Color(light: 0x1F1D1A, dark: 0xF3F1EC)
    static let inkSecondary = Color(light: 0x67635C, dark: 0xB5B0A6)
    static let inkTertiary = Color(light: 0x8E8A82, dark: 0x8A857B)

    // MARK: Surfaces

    static let backgroundTop = Color(light: 0xFAF9F7, dark: 0x1C1B18)
    static let backgroundBottom = Color(light: 0xF1EFEA, dark: 0x141310)
    static let card = Color(light: 0xFFFFFF, dark: 0x23211D)
    static let hairline = Color(
        lightRGBA: (60, 50, 35, 0.06),
        darkRGBA: (255, 255, 255, 0.08)
    )
    static let divider = Color(
        lightRGBA: (60, 50, 35, 0.10),
        darkRGBA: (255, 255, 255, 0.12)
    )

    // MARK: Fonts

    private static let fontFiles = ["Poppins-Regular", "Poppins-Medium", "Poppins-SemiBold", "Poppins-Bold"]

    /// Registers the bundled Poppins files for this process. Call once, before any view renders.
    static func registerFonts() {
        for file in fontFiles {
            let url = Bundle.main.url(forResource: file, withExtension: "ttf")
                ?? Bundle.main.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts")
            guard let url else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Poppins for the UIKit-drawn navigation titles only. It sets text attributes and never
    /// touches bar backgrounds or appearances, so the system glass navigation is unchanged.
    static func configureNavigationTitleFonts() {
        let bar = UINavigationBar.appearance()
        if let large = UIFont(name: "Poppins-Bold", size: 34) {
            bar.largeTitleTextAttributes = [.font: large, .foregroundColor: UIColor(ink)]
        }
        if let inline = UIFont(name: "Poppins-SemiBold", size: 17) {
            bar.titleTextAttributes = [.font: inline, .foregroundColor: UIColor(ink)]
        }
    }
}

// MARK: - Background

/// Screen background: the soft near-white gradient of the design.
struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - Section header

/// Poppins section header shared by every Form / List `Section { } header: { }`.
struct AppSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.poppins(.footnote, .semibold))
            .foregroundStyle(AppTheme.inkSecondary)
    }
}

// MARK: - Typography

extension Font {
    /// Poppins that scales with Dynamic Type like the system text style it replaces.
    /// With no weight it matches the system default for that style (`.headline` is semibold).
    static func poppins(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        let resolved = weight ?? (style == .headline ? .semibold : .regular)
        return .custom(poppinsFace(for: resolved), size: poppinsBaseSize(for: style), relativeTo: style)
    }

    /// Poppins at a fixed base size (still scales with Dynamic Type relative to `style`).
    static func poppins(size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(poppinsFace(for: weight), size: size, relativeTo: style)
    }

    private static func poppinsFace(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Poppins-Bold"
        case .semibold: return "Poppins-SemiBold"
        case .medium: return "Poppins-Medium"
        default: return "Poppins-Regular"
        }
    }

    private static func poppinsBaseSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }
}

// MARK: - Color helpers

extension Color {
    /// Dynamic color from two 0xRRGGBB values.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Dynamic color from two (r, g, b, a) tuples with r/g/b in 0...255.
    init(lightRGBA: (Double, Double, Double, Double), darkRGBA: (Double, Double, Double, Double)) {
        self.init(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? darkRGBA : lightRGBA
            return UIColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: c.3)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
