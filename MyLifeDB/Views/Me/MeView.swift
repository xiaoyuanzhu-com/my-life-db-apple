//
//  MeView.swift
//  MyLifeDB
//
//  Main profile and settings tab with avatar header and settings list.
//  Provides access to General, Server, Stats, and About screens.
//

import SwiftUI

struct MeView: View {
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

                            Text("User")
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
