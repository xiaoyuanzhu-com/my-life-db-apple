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
