//
//  CustomTabBar.swift
//  MyLifeDB
//
//  Custom tab bar that replaces the standard SwiftUI TabView.
//  This is necessary because the hybrid architecture uses a single persistent
//  WKWebView in a ZStack — standard TabView would recreate child views on
//  each tab switch, causing the WebView to be detached/reattached.
//
//  Appearance matches the system tab bar: blur material background, SF Symbols,
//  tinted selection color.
//
//  iOS/visionOS only — macOS uses NavigationSplitView sidebar instead.
//

import SwiftUI

#if os(iOS) || os(visionOS)

struct CustomTabBar: View {
    @Binding var selectedTab: Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func tabButton(for tab: Tab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.iconFilled : tab.icon)
                    .font(.system(size: 20))
                    .frame(height: 24)

                Text(tab.rawValue)
                    .font(.caption2)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var tab: Tab = .inbox
    VStack {
        Spacer()
        CustomTabBar(selectedTab: $tab)
    }
}

#endif
