import Foundation

/// Thin GitHub REST client — only the calls SplashG needs to read
/// album_template-format gallery repos.
struct GitHubAPI {
    /// nil = unauthenticated (demo mode over public repos, 60 req/h limit).
    let token: String?

    private func request(_ path: String,
                         query: [URLQueryItem] = [],
                         accept: String = "application/vnd.github+json") -> URLRequest {
        var components = URLComponents(url: Config.githubAPIBase.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var req = URLRequest(url: components.url!)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue("SplashG-iOS", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func data(for req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError(status: 0, message: "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["message"]
            throw APIError(status: http.statusCode,
                           message: msg ?? "GitHub error \(http.statusCode) for \(req.url?.path ?? "")")
        }
        return data
    }

    private func getJSON<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await data(for: request(path, query: query))
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Calls

    func user() async throws -> GHUser {
        try await getJSON("user")
    }

    func repos(page: Int = 1) async throws -> [GHRepo] {
        try await getJSON("user/repos", query: [
            .init(name: "per_page", value: "100"),
            .init(name: "page", value: String(page)),
            .init(name: "visibility", value: "all"),
            .init(name: "affiliation", value: "owner,collaborator,organization_member"),
            .init(name: "sort", value: "updated"),
        ])
    }

    func repoDetail(_ fullName: String) async throws -> GHRepoDetail {
        try await getJSON("repos/\(fullName)")
    }

    /// Raw file contents at a path (Accept: raw skips the base64 dance).
    func fileText(repo: String, path: String, ref: String) async throws -> String {
        let req = request("repos/\(repo)/contents/\(path)",
                          query: [.init(name: "ref", value: ref)],
                          accept: "application/vnd.github.raw+json")
        let bytes = try await data(for: req)
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw APIError(status: 0, message: "\(path) is not UTF-8 text")
        }
        return text
    }

    /// Full recursive file listing of a branch — one call enumerates every
    /// album's photos, so we never need per-directory Contents calls.
    func tree(repo: String, ref: String) async throws -> [GHTreeEntry] {
        let resp: GHTreeResponse = try await getJSON("repos/\(repo)/git/trees/\(ref)",
                                                     query: [.init(name: "recursive", value: "1")])
        return resp.tree
    }
}
