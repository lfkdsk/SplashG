import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.webAuthenticationSession) private var webAuthSession

    @State private var showPATField = false
    @State private var pat = ""

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "photo.stack")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Theme.titleGradient)
                    .padding(.bottom, 20)

                Text("SplashG")
                    .font(.system(size: 40, weight: .bold))
                Text("Your GitHub albums, as a feed")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtle)
                    .padding(.top, 6)

                Spacer()

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 12)
                }

                VStack(spacing: 12) {
                    Button(action: signInWithGitHub) {
                        HStack {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                            Text("Sign in with GitHub")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Capsule().fill(Theme.accent))
                        .foregroundStyle(.white)
                    }
                    .disabled(auth.signingIn)

                    if showPATField {
                        VStack(spacing: 10) {
                            SecureField("Personal Access Token (repo scope)", text: $pat)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                            Button {
                                Task { await auth.signIn(pat: pat) }
                            } label: {
                                Text(auth.signingIn ? "Checking…" : "Use Token")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Capsule().fill(Theme.card))
                            }
                            .disabled(auth.signingIn || pat.isEmpty)
                        }
                        .transition(.opacity)
                    } else {
                        Button {
                            withAnimation { showPATField = true }
                        } label: {
                            Text("Use a Personal Access Token instead")
                                .font(.footnote)
                                .foregroundStyle(Theme.subtle)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }

    private func signInWithGitHub() {
        let attempt = auth.makeAuthorizeAttempt()
        Task {
            do {
                let callback = try await webAuthSession.authenticate(
                    using: attempt.url,
                    callbackURLScheme: Config.callbackScheme,
                    preferredBrowserSession: .shared)
                try await auth.completeOAuth(callback: callback, expectedState: attempt.state)
            } catch is CancellationError {
                // user closed the sheet — not an error
            } catch let err as ASWebAuthenticationSessionError where err.code == .canceledLogin {
                // ditto
            } catch {
                auth.errorMessage = error.localizedDescription
            }
        }
    }
}
