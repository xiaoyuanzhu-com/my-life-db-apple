//
//  MeView.swift
//  MyLifeDB
//
//  Main profile and settings tab with avatar header and settings list.
//  Provides access to General, Server, Stats, and About screens.
//

import SwiftUI

struct MeView: View {
    private var authManager: AuthManager { .shared }

    var body: some View {
        NavigationStack {
            List {
                // Avatar header section
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            // Gray placeholder avatar
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 90, height: 90)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.gray)
                                )

                            Text(authManager.username ?? "User")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)

                // Settings sections
                Section {
                    NavigationLink {
                        GeneralSettingsView()
                    } label: {
                        Label("General", systemImage: "gearshape")
                    }

                    NavigationLink {
                        ServerSettingsView()
                    } label: {
                        Label("Server", systemImage: "server.rack")
                    }

                    NavigationLink {
                        StatsView()
                    } label: {
                        Label("Stats", systemImage: "chart.bar")
                    }

                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }

                // Sign out (only when authenticated via OAuth)
                if case .authenticated = authManager.state {
                    Section {
                        Button(role: .destructive) {
                            Task {
                                await authManager.logout()
                            }
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.sidebar)
            #endif
            .navigationTitle("Me")
        }
    }
}

#Preview {
    MeView()
}
