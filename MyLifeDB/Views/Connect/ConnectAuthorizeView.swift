//
//  ConnectAuthorizeView.swift
//  MyLifeDB
//
//  Native consent UI for third-party OAuth Connect requests.
//
//  Triggered by a Universal Link of the form:
//    https://my.xiaoyuanzhu.com/connect/authorize?response_type=code&client_id=...
//      &redirect_uri=<thirdparty-scheme>://callback&scope=...&state=...
//      &code_challenge=...&code_challenge_method=S256&app_name=...
//
//  Flow:
//    1) Fetch GET /api/connect/authorize/preview to validate params and
//       resolve the client + scope metadata.
//    2) Render app card with Approve / Deny buttons.
//    3) POST /api/connect/consent with the original params + approve flag.
//    4) Open the returned `redirectTo` URL to bounce back to the calling
//       app via its custom URL scheme.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Request

/// Captures the OAuth Connect request as parsed from a Universal Link.
/// Held by the app and passed into ConnectAuthorizeView for presentation.
struct ConnectAuthorizeRequest: Identifiable, Equatable {
    let id = UUID()
    /// All Connect params as `name → value` (response_type, client_id, etc).
    let params: [String: String]

    /// Returns nil if the URL is not a well-formed Connect authorize request.
    /// We validate presence of required params client-side as a fail-fast;
    /// the server re-validates and the preview call surfaces detailed errors.
    static func from(url: URL) -> ConnectAuthorizeRequest? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            return nil
        }

        var dict: [String: String] = [:]
        for item in items {
            if let v = item.value, !v.isEmpty {
                dict[item.name] = v
            }
        }

        let required = [
            "response_type", "client_id", "redirect_uri", "scope", "state",
            "code_challenge", "code_challenge_method", "app_name",
        ]
        for key in required where dict[key] == nil {
            print("[ConnectAuthorize] missing required param: \(key)")
            return nil
        }
        guard dict["response_type"] == "code" else {
            print("[ConnectAuthorize] unsupported response_type: \(dict["response_type"] ?? "<nil>")")
            return nil
        }
        guard dict["code_challenge_method"] == "S256" else {
            print("[ConnectAuthorize] unsupported code_challenge_method: \(dict["code_challenge_method"] ?? "<nil>")")
            return nil
        }

        // Carry app_icon through if present (optional).
        if let icon = dict["app_icon"], icon.isEmpty {
            dict.removeValue(forKey: "app_icon")
        }

        return ConnectAuthorizeRequest(params: dict)
    }
}

// MARK: - View

struct ConnectAuthorizeView: View {

    let request: ConnectAuthorizeRequest
    let onDismiss: () -> Void

    private enum LoadState {
        case loading
        case loaded(ConnectPreviewResponse.PreviewData)
        case error(String)
        case submitting(approve: Bool, preview: ConnectPreviewResponse.PreviewData)
        case done
    }

    @State private var state: LoadState = .loading

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding()
                    .frame(maxWidth: 500)
                    .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss() }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .task { await loadPreview() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            VStack(spacing: 16) {
                ProgressView()
                Text("Loading authorization request…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 80)

        case .error(let message):
            errorView(message: message)

        case .loaded(let preview):
            consentCard(preview: preview, submitting: nil)

        case .submitting(let approve, let preview):
            consentCard(preview: preview, submitting: approve)

        case .done:
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Done")
                    .font(.headline)
            }
            .padding(.top, 80)
        }
    }

    // MARK: - Consent Card

    @ViewBuilder
    private func consentCard(preview: ConnectPreviewResponse.PreviewData, submitting: Bool?) -> some View {
        let client = preview.client
        let isReturning = !preview.grantedMethods.isEmpty
        let onlyNewMatters = isReturning && !preview.newMethods.isEmpty
        let methodsToShow = onlyNewMatters ? preview.newMethods : preview.requestedMethods
        let isSubmitting = submitting != nil

        VStack(alignment: .leading, spacing: 16) {
            // Header: icon + name + verified badge
            HStack(alignment: .top, spacing: 12) {
                appIcon(client: client)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(client.name)
                            .font(.headline)
                            .lineLimit(2)
                        if client.verified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.tint)
                                .font(.subheadline)
                                .accessibilityLabel("Verified")
                        }
                    }
                    Text(client.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }

            Divider()

            // Body
            Text(onlyNewMatters
                ? "\(client.name) is requesting additional access to your MyLifeDB:"
                : "\(client.name) is requesting access to your MyLifeDB:")
                .font(.subheadline)

            VStack(spacing: 8) {
                ForEach(methodsToShow, id: \.self) { method in
                    methodRow(method: method)
                }
            }

            if onlyNewMatters {
                Text("Already granted: \(preview.grantedMethods.map(\.label).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Buttons
            HStack(spacing: 12) {
                Button(role: .cancel) {
                    Task { await submit(approve: false, preview: preview) }
                } label: {
                    Group {
                        if case .submitting(false, _) = state {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Deny")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isSubmitting)

                Button {
                    Task { await submit(approve: true, preview: preview) }
                } label: {
                    Group {
                        if case .submitting(true, _) = state {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Text("Allow")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSubmitting)
            }
            .padding(.top, 4)

            Text("You'll be redirected back to \(client.name) after you decide.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        #if os(iOS)
        .background(Color(.secondarySystemBackground))
        #else
        .background(Color.gray.opacity(0.1))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - App Icon

    @ViewBuilder
    private func appIcon(client: ConnectPreviewResponse.Client) -> some View {
        if let url = URL(string: client.iconUrl), !client.iconUrl.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    iconFallback(name: client.name)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            iconFallback(name: client.name)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func iconFallback(name: String) -> some View {
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.25))
            Text(String(name.prefix(1)).uppercased())
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Method Row

    private func methodRow(method: ConnectPreviewResponse.Method) -> some View {
        // Write capabilities get a warning treatment; read does not.
        // Path-level distinctions no longer exist in the methods model
        // (see docs/specs/2026-05-19-oauth-methods-design.md in the gateway repo).
        let destructive = method.name == "write_file"
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: destructive ? "exclamationmark.shield.fill" : "checkmark.shield")
                .foregroundStyle(destructive ? .red : .secondary)
                .font(.body)
                .frame(width: 20)
            Text(method.label.isEmpty ? method.name : method.label)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(destructive ? Color.red.opacity(0.1) : Color.gray.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(destructive ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Authorization request rejected")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Close") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .padding(.top, 60)
    }

    // MARK: - Actions

    private func loadPreview() async {
        do {
            let preview = try await APIClient.shared.connect.preview(params: request.params)
            await MainActor.run { state = .loaded(preview.data) }
        } catch {
            let msg = (error as? APIError)?.errorDescription ?? error.localizedDescription
            await MainActor.run { state = .error(msg) }
        }
    }

    private func submit(approve: Bool, preview: ConnectPreviewResponse.PreviewData) async {
        await MainActor.run { state = .submitting(approve: approve, preview: preview) }
        do {
            let consent = try await APIClient.shared.connect.consent(
                params: request.params, approve: approve
            )
            guard let url = URL(string: consent.data.redirectTo) else {
                await MainActor.run { state = .error("Invalid redirect URL from server") }
                return
            }
            await openRedirect(url: url)
            await MainActor.run {
                state = .done
                onDismiss()
            }
        } catch {
            let msg = (error as? APIError)?.errorDescription ?? error.localizedDescription
            await MainActor.run { state = .error(msg) }
        }
    }

    @MainActor
    private func openRedirect(url: URL) async {
        #if os(iOS) || os(visionOS)
        await UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}

// MARK: - Preview

#Preview {
    ConnectAuthorizeView(
        request: ConnectAuthorizeRequest(params: [
            "response_type": "code",
            "client_id": "com.example.myhealth",
            "redirect_uri": "myhealth://callback",
            "scope": "read_file write_file",
            "state": "abc123",
            "code_challenge": "xyz",
            "code_challenge_method": "S256",
            "app_name": "MyHealth",
        ]),
        onDismiss: {}
    )
}
