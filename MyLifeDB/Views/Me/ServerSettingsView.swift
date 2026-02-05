//
//  ServerSettingsView.swift
//  MyLifeDB
//
//  Server configuration screen for API base URL.
//  Validates URL format and stores in AppStorage for app-wide access.
//

import SwiftUI

struct ServerSettingsView: View {
    @AppStorage("apiBaseURL") private var apiBaseURL = "http://localhost:12345"
    @State private var urlInput: String = ""
    @State private var validationError: String?
    @State private var isCheckingConnection = false
    @State private var connectionStatus: ConnectionStatus = .unknown

    enum ConnectionStatus {
        case unknown, connected, unreachable

        var text: String {
            switch self {
            case .unknown: return "Not checked"
            case .connected: return "Connected"
            case .unreachable: return "Not reachable"
            }
        }

        var color: Color {
            switch self {
            case .unknown: return .secondary
            case .connected: return .green
            case .unreachable: return .orange
            }
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Base URL")
                        .font(.headline)

                    TextField("http://localhost:12345", text: $urlInput)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        #endif
                        .disableAutocorrection(true)
                        .onChange(of: urlInput) { oldValue, newValue in
                            validateAndSave(newValue)
                        }

                    if let error = validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            } header: {
                Text("Server Configuration")
            } footer: {
                Text("Enter the base URL of your MyLifeDB server. Changes are saved automatically.")
            }

            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    if isCheckingConnection {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text(connectionStatus.text)
                            .foregroundColor(connectionStatus.color)
                    }
                }

                Button("Check Connection") {
                    checkConnection()
                }
            } header: {
                Text("Connection")
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle("Server")
        .onAppear {
            urlInput = apiBaseURL
        }
    }

    private func validateAndSave(_ urlString: String) {
        // Reset error
        validationError = nil
        connectionStatus = .unknown

        // Empty is allowed (will use default)
        guard !urlString.isEmpty else {
            apiBaseURL = "http://localhost:12345"
            return
        }

        // Validate URL format
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme),
              url.host != nil else {
            validationError = "Invalid URL format. Must start with http:// or https://"
            return
        }

        // Valid - save it
        apiBaseURL = urlString
    }

    private func checkConnection() {
        isCheckingConnection = true

        Task {
            do {
                // Try to construct health check URL
                guard let baseURL = URL(string: apiBaseURL) else {
                    await MainActor.run {
                        connectionStatus = .unreachable
                        isCheckingConnection = false
                    }
                    return
                }

                let healthURL = baseURL.appendingPathComponent("api/health")

                // Simple HEAD request with 5 second timeout
                var request = URLRequest(url: healthURL)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 5

                let (_, response) = try await URLSession.shared.data(for: request)

                await MainActor.run {
                    if let httpResponse = response as? HTTPURLResponse,
                       (200...299).contains(httpResponse.statusCode) {
                        connectionStatus = .connected
                    } else {
                        connectionStatus = .unreachable
                    }
                    isCheckingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .unreachable
                    isCheckingConnection = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ServerSettingsView()
    }
}
