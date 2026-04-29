//
//  Color+Platform.swift
//  MyLifeDB
//
//  Cross-platform color helpers for iOS and macOS.
//

import SwiftUI

extension Color {
    /// Background color that works on all platforms
    static var platformBackground: Color {
        #if os(iOS)
        return Color(uiColor: .systemBackground)
        #elseif os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color.white
        #endif
    }

    /// Matches the web frontend's `--background` design token so native
    /// chrome (e.g. nav bars wrapping a WebView) blends seamlessly with
    /// the embedded page.  The web side defines this in `globals.css`:
    ///   light: `oklch(1 0 0)`     → pure white
    ///   dark:  `oklch(0.145 0 0)` → near-black (~#0A0A0A in sRGB)
    /// `UIColor.systemBackground` matches in light mode but resolves to
    /// pure black in dark mode, which leaves a visible seam.
    static var webBackground: Color {
        #if os(iOS)
        return Color(uiColor: UIColor { traits in
            switch traits.userInterfaceStyle {
            case .dark:
                return UIColor(red: 10.0 / 255.0, green: 10.0 / 255.0, blue: 10.0 / 255.0, alpha: 1.0)
            default:
                return UIColor.white
            }
        })
        #elseif os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            return isDark
                ? NSColor(red: 10.0 / 255.0, green: 10.0 / 255.0, blue: 10.0 / 255.0, alpha: 1.0)
                : NSColor.white
        })
        #else
        return Color.white
        #endif
    }

    /// Grouped background color that works on all platforms
    static var platformGroupedBackground: Color {
        #if os(iOS)
        return Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }

    /// Light gray background color that works on all platforms
    static var platformGray6: Color {
        #if os(iOS)
        return Color(uiColor: .systemGray6)
        #elseif os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color.gray.opacity(0.05)
        #endif
    }

    /// Medium gray background color that works on all platforms
    static var platformGray5: Color {
        #if os(iOS)
        return Color(uiColor: .systemGray5)
        #elseif os(macOS)
        return Color(nsColor: .quaternaryLabelColor)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }

    /// Secondary background color that works on all platforms
    static var platformSecondaryBackground: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemBackground)
        #elseif os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color.gray.opacity(0.06)
        #endif
    }

    /// Tertiary background color that works on all platforms
    static var platformTertiaryBackground: Color {
        #if os(iOS)
        return Color(uiColor: .tertiarySystemBackground)
        #elseif os(macOS)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color.gray.opacity(0.03)
        #endif
    }

    /// Separator color that works on all platforms
    static var platformSeparator: Color {
        #if os(iOS)
        return Color(uiColor: .separator)
        #elseif os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color.gray.opacity(0.3)
        #endif
    }
}
