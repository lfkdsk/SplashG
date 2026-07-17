import Foundation
import SwiftUI

/// Session state. GitHub identity is the only identity: a token in the
/// Keychain means signed in. The SplashG backend just resolves the same
/// token per request (SplitStupid model).
@MainActor
final class AuthManager: ObservableObject {
    @Published var token: String?
    @Published var me: MeProfile?
    @Published var booting = true
    @Published var signingIn = false
    /// Non-nil when the GitHub token works but the SplashG backend didn't
    /// answer — the app stays usable, social features degrade.
    @Published var backendError: String?
    @Published var errorMessage: String?

    private let tokenKey = "gh_token"

    // MARK: Boot

    func boot() async {
        defer { booting = false }
        guard let stored = Keychain.get(tokenKey) else { return }
        token = stored
        await loadMe()
    }

    /// Refresh /me. Falls back to GitHub /user when the backend is down so
    /// browsing still works.
    func loadMe() async {
        guard let token else { return }
        do {
            me = try await SplashGAPI(token: token).me()
            backendError = nil
        } catch let err as APIError where err.status == 401 {
            // GitHub rejected the token — really signed out.
            signOut()
        } catch {
            backendError = error.localizedDescription
            do {
                let gh = try await GitHubAPI(token: token).user()
                me = MeProfile(login: gh.login, name: gh.name, avatarUrl: gh.avatarUrl,
                               repos: [], following: [], followerCount: 0)
            } catch {
                // Can't even reach GitHub; keep token, surface the error.
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: OAuth via lfkdsk-auth broker

    struct OAuthAttempt {
        let url: URL
        let state: String
    }

    func makeAuthorizeAttempt() -> OAuthAttempt {
        let state = UUID().uuidString
        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: Config.githubClientID),
            .init(name: "redirect_uri", value: Config.oauthBrokerCallback),
            .init(name: "scope", value: Config.oauthScope),
            .init(name: "state", value: state),
        ]
        return OAuthAttempt(url: components.url!, state: state)
    }

    /// The broker 302s to `splashg://callback#oauth_token=...&state=...`.
    /// Params may land in the fragment or the query depending on how the
    /// session hands the URL back — accept both (same as SplitStupid mobile).
    func completeOAuth(callback: URL, expectedState: String) async throws {
        var params: [String: String] = [:]
        let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        for item in components?.queryItems ?? [] { params[item.name] = item.value }
        if let fragment = components?.fragment {
            var fc = URLComponents()
            fc.query = fragment
            for item in fc.queryItems ?? [] { params[item.name] = item.value }
        }

        if let err = params["oauth_error"] {
            throw APIError(status: 0, message: "GitHub sign-in failed: \(err)")
        }
        guard params["state"] == expectedState else {
            throw APIError(status: 0, message: "OAuth state mismatch — try again")
        }
        guard let newToken = params["oauth_token"], !newToken.isEmpty else {
            throw APIError(status: 0, message: "No token in OAuth callback")
        }
        adopt(token: newToken)
        await loadMe()
    }

    // MARK: PAT fallback

    func signIn(pat: String) async {
        let trimmed = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        signingIn = true
        defer { signingIn = false }
        do {
            _ = try await GitHubAPI(token: trimmed).user()
            adopt(token: trimmed)
            await loadMe()
        } catch {
            errorMessage = "Token rejected: \(error.localizedDescription)"
        }
    }

    private func adopt(token newToken: String) {
        Keychain.set(newToken, for: tokenKey)
        token = newToken
        errorMessage = nil
    }

    func signOut() {
        Keychain.delete(tokenKey)
        token = nil
        me = nil
        backendError = nil
    }
}
