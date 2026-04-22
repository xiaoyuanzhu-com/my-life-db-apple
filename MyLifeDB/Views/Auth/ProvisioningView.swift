//
//  ProvisioningView.swift
//  MyLifeDB
//
//  Shown when the user's backend instance is being provisioned.
//  Polls the backend until it's ready, then transitions to authenticated state.
//

import SwiftUI

struct ProvisioningView: View {
    @State private var dots = ""
    @State private var pollTask: Task<Void, Never>?

    private let authManager = AuthManager.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .padding(.bottom, 8)

            VStack(spacing: 8) {
                Text(String(localized: "Setting up your space") + dots)
                    .font(.title2.bold())

                Text("This usually takes about 15 seconds")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .task {
            // Animate dots
            let dotsTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    dots = dots.count >= 3 ? "" : dots + "."
                }
            }

            // Poll backend
            await pollUntilReady()

            dotsTask.cancel()
        }
    }

    private func pollUntilReady() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))

            if await APIClient.shared.isBackendReady() {
                await authManager.handleProvisioningComplete()
                return
            }
        }
    }
}

#Preview {
    ProvisioningView()
}
