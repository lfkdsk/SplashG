import Foundation

/// Client for the SplashG thin backend (worker/). Same auth model as the
/// worker expects: every request carries the GitHub token as a Bearer.
struct SplashGAPI {
    let token: String

    private func makeRequest(_ method: String, _ path: String, body: [String: String]? = nil) -> URLRequest {
        var req = URLRequest(url: Config.apiBase.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    @discardableResult
    private func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError(status: 0, message: "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw APIError(status: http.statusCode, message: msg ?? "API error \(http.statusCode)")
        }
        return data
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(makeRequest("GET", path))
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Calls

    func me() async throws -> MeProfile { try await get("me") }

    func feed() async throws -> [FeedUser] { try await get("feed") }

    func bindings() async throws -> [RepoBinding] { try await get("repos") }

    func bind(repo: String, title: String?) async throws {
        var body = ["repo": repo]
        if let title, !title.isEmpty { body["title"] = title }
        try await send(makeRequest("POST", "repos", body: body))
    }

    func unbind(repo: String) async throws {
        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw APIError(status: 0, message: "bad repo name") }
        try await send(makeRequest("DELETE", "repos/\(parts[0])/\(parts[1])"))
    }

    func follows() async throws -> [FeedUser] { try await get("follows") }

    func follow(_ login: String) async throws {
        try await send(makeRequest("POST", "follows", body: ["login": login]))
    }

    func unfollow(_ login: String) async throws {
        try await send(makeRequest("DELETE", "follows/\(login)"))
    }

    func user(_ login: String) async throws -> UserProfile { try await get("users/\(login)") }
}
