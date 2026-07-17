import Foundation

enum Config {
    /// Shared OAuth App for all lfkdsk projects; secret lives in the
    /// lfkdsk-auth Worker, never in the client.
    static let githubClientID = "Ov23liCg29llKxJ7b0jv"

    /// The lfkdsk-auth broker callback for this app's project key.
    /// PROJECT_ORIGINS maps "splashg-mobile" -> "splashg://callback".
    static let oauthBrokerCallback = "https://auth.lfkdsk.org/splashg-mobile/callback"
    static let callbackScheme = "splashg"

    /// `repo` so private gallery repos can be listed and read.
    static let oauthScope = "repo"

    /// The SplashG thin backend (worker/ in this repo). Swap for
    /// api.splashg.lfkdsk.org once that custom domain is bound in the
    /// Cloudflare dashboard.
    static let apiBase = URL(string: "https://splashg-data.lfk-dsk.workers.dev")!

    static let githubAPIBase = URL(string: "https://api.github.com")!

    /// Dev/preview escape hatch: set SPLASHG_DEMO_REPO=owner/name (public
    /// repo) to skip sign-in and browse that gallery unauthenticated.
    static var demoRepo: String? {
        ProcessInfo.processInfo.environment["SPLASHG_DEMO_REPO"]
    }

    /// Optional initial tab for demo runs: "feed" | "random" | "collections".
    static var demoTab: String? {
        ProcessInfo.processInfo.environment["SPLASHG_DEMO_TAB"]
    }
}
