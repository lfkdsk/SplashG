// SplashG backend Worker.
// =========================================================================
// One Cloudflare Worker + one D1 database, in the SplitStupid mold. The
// Worker is deliberately thin: album data itself lives in each user's
// gallery repo (album_template format) on GitHub and is read by clients
// straight from the GitHub API / CDN. The backend only owns what GitHub
// can't express for us:
//
//   * the registry of users who signed in (so profiles resolve offline),
//   * which gallery repos a user has bound to their profile,
//   * the follow graph.
//
// Auth model: clients send `Authorization: Bearer <gh_oauth_token>` on
// every request. The Worker resolves the token to a GH login by calling
// GitHub's /user endpoint once per request. We *do not* validate scope —
// even a no-scope token can call /user. The token is trusted only for
// "this caller is GH user X"; everything else is checked against the DB.
//
// Routing is hand-rolled (no router framework) — there are 10 endpoints.

interface Env {
  DB: D1Database
  ALLOWED_ORIGINS: string
}

interface GitHubUser {
  login: string
  name: string | null
  avatar_url: string | null
}

// ---------------------------------------------------------------------------
// Entry point + CORS shell

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const origin = request.headers.get('origin')
    const allowedOrigin = pickAllowedOrigin(origin, env)

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders(allowedOrigin) })
    }

    try {
      const res = await route(request, env, ctx)
      const merged = new Headers(res.headers)
      for (const [k, v] of Object.entries(corsHeaders(allowedOrigin))) merged.set(k, v)
      return new Response(res.body, { status: res.status, headers: merged })
    } catch (err: any) {
      return jsonError(500, err?.message || 'internal error', allowedOrigin)
    }
  },
}

function pickAllowedOrigin(origin: string | null, env: Env): string {
  const allowed = (env.ALLOWED_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean)
  if (origin && allowed.includes(origin)) return origin
  // Native apps and curl send no Origin; fall back to the first entry.
  return allowed[0] || '*'
}

function corsHeaders(origin: string): HeadersInit {
  return {
    'access-control-allow-origin': origin,
    'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
    'access-control-allow-headers': 'authorization, content-type',
    'access-control-max-age': '86400',
    'vary': 'origin',
  }
}

function jsonError(status: number, message: string, origin: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { 'content-type': 'application/json', ...corsHeaders(origin) },
  })
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  })
}

// ---------------------------------------------------------------------------
// Router

async function route(request: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
  const url = new URL(request.url)
  const path = url.pathname
  const method = request.method

  if (path === '/' || path === '/healthz') {
    return new Response('splashg-data — ok\n', {
      status: 200,
      headers: { 'content-type': 'text/plain; charset=utf-8' },
    })
  }

  // Everything else needs an authenticated GH identity. authenticate()
  // also hands back the raw token — /repos POST re-uses it to verify the
  // bound repo actually looks like a gallery repo (works for private
  // repos because it's the caller's own token).
  const auth = await authenticate(request)
  if (auth instanceof Response) return auth
  const { user: ghUser, token } = auth
  const me = ghUser.login

  // GET /me — profile + own bindings + following. Also the registration
  // point: upserts the users row so follows/profiles can resolve.
  if (path === '/me') {
    if (method === 'GET') return await readMe(env, ghUser)
    return new Response('method not allowed', { status: 405 })
  }

  // GET  /repos            — my bindings
  // POST /repos            — bind { repo: "owner/name", title? }
  if (path === '/repos') {
    if (method === 'GET') return await listBindings(env, me)
    if (method === 'POST') return await bindRepo(env, me, token, await request.json())
    return new Response('method not allowed', { status: 405 })
  }

  // DELETE /repos/:owner/:name — unbind
  const repoMatch = path.match(/^\/repos\/([^/]+)\/([^/]+)$/)
  if (repoMatch) {
    if (method === 'DELETE') {
      return await unbindRepo(env, me, `${decodeURIComponent(repoMatch[1])}/${decodeURIComponent(repoMatch[2])}`)
    }
    return new Response('method not allowed', { status: 405 })
  }

  // GET  /follows          — who I follow (profiles + bindings)
  // POST /follows          — follow { login }
  if (path === '/follows') {
    if (method === 'GET') return await listFollows(env, me)
    if (method === 'POST') return await follow(env, me, await request.json())
    return new Response('method not allowed', { status: 405 })
  }

  // DELETE /follows/:login — unfollow
  const followMatch = path.match(/^\/follows\/([^/]+)$/)
  if (followMatch) {
    if (method === 'DELETE') return await unfollow(env, me, decodeURIComponent(followMatch[1]))
    return new Response('method not allowed', { status: 405 })
  }

  // GET /feed — me + followees, each with profile + bindings. The client
  // resolves each binding's README.yml/CONFIG.yml from GitHub and merges
  // albums into the actual feed; the Worker stays out of album data.
  if (path === '/feed') {
    if (method === 'GET') return await readFeed(env, me)
    return new Response('method not allowed', { status: 405 })
  }

  // GET /users/:login — a user's public profile + bindings (discovery).
  const userMatch = path.match(/^\/users\/([^/]+)$/)
  if (userMatch) {
    if (method === 'GET') return await readUser(env, me, decodeURIComponent(userMatch[1]))
    return new Response('method not allowed', { status: 405 })
  }

  return new Response('not found', { status: 404 })
}

// ---------------------------------------------------------------------------
// Auth: resolve a Bearer GH token to a user. No caching in v1 — one GH
// /user call per request is fine at this traffic. Add a KV cache keyed by
// SHA-256(token) if rate limits ever bite.

async function authenticate(
  request: Request,
): Promise<{ user: GitHubUser; token: string } | Response> {
  const auth = request.headers.get('authorization') || ''
  if (!auth.startsWith('Bearer ')) {
    return json({ error: 'missing bearer token' }, 401)
  }
  const token = auth.slice('Bearer '.length).trim()
  if (!token) return json({ error: 'empty bearer token' }, 401)

  let resp: Response
  try {
    resp = await fetch('https://api.github.com/user', {
      headers: {
        'authorization': `Bearer ${token}`,
        'accept': 'application/vnd.github+json',
        'user-agent': 'splashg-data',
      },
    })
  } catch (e: any) {
    return json({ error: 'github unreachable: ' + (e?.message || e) }, 502)
  }

  if (!resp.ok) return json({ error: 'github rejected token' }, 401)
  const data = await resp.json() as { login?: string; name?: string | null; avatar_url?: string | null }
  if (!data.login) return json({ error: 'github returned no login' }, 502)
  return {
    user: { login: data.login, name: data.name ?? null, avatar_url: data.avatar_url ?? null },
    token,
  }
}

// ---------------------------------------------------------------------------
// Row shapes

interface UserRow {
  login: string
  name: string | null
  avatar_url: string | null
}

interface BindingRow {
  login: string
  repo: string
  title: string | null
  added_at: number
}

function userJson(r: UserRow) {
  return { login: r.login, name: r.name ?? undefined, avatarUrl: r.avatar_url ?? undefined }
}

function bindingJson(r: BindingRow) {
  return { repo: r.repo, title: r.title ?? undefined, addedAt: r.added_at }
}

// Fetch bindings for a set of logins in one query, grouped.
async function bindingsFor(env: Env, logins: string[]): Promise<Map<string, BindingRow[]>> {
  const grouped = new Map<string, BindingRow[]>()
  if (logins.length === 0) return grouped
  const placeholders = logins.map(() => '?').join(',')
  const rows = await env.DB.prepare(
    `SELECT login, repo, title, added_at FROM bindings
     WHERE login IN (${placeholders}) ORDER BY added_at ASC`,
  ).bind(...logins).all<BindingRow>()
  for (const b of rows.results || []) {
    if (!grouped.has(b.login)) grouped.set(b.login, [])
    grouped.get(b.login)!.push(b)
  }
  return grouped
}

// ---------------------------------------------------------------------------
// Handlers

// GET /me — upsert + return the whole "my account" view in one trip.
async function readMe(env: Env, gh: GitHubUser): Promise<Response> {
  const now = Date.now()
  await env.DB.prepare(
    `INSERT INTO users (login, name, avatar_url, created_at, updated_at)
     VALUES (?1, ?2, ?3, ?4, ?4)
     ON CONFLICT(login) DO UPDATE SET name = ?2, avatar_url = ?3, updated_at = ?4`,
  ).bind(gh.login, gh.name, gh.avatar_url, now).run()

  const bindings = await env.DB.prepare(
    `SELECT login, repo, title, added_at FROM bindings WHERE login = ?1 ORDER BY added_at ASC`,
  ).bind(gh.login).all<BindingRow>()

  const following = await env.DB.prepare(
    `SELECT followee FROM follows WHERE follower = ?1 ORDER BY created_at ASC`,
  ).bind(gh.login).all<{ followee: string }>()

  const followers = await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM follows WHERE followee = ?1`,
  ).bind(gh.login).first<{ n: number }>()

  return json({
    login: gh.login,
    name: gh.name ?? undefined,
    avatarUrl: gh.avatar_url ?? undefined,
    repos: (bindings.results || []).map(bindingJson),
    following: (following.results || []).map(f => f.followee),
    followerCount: followers?.n ?? 0,
  })
}

// GET /repos
async function listBindings(env: Env, me: string): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT login, repo, title, added_at FROM bindings WHERE login = ?1 ORDER BY added_at ASC`,
  ).bind(me).all<BindingRow>()
  return json((rows.results || []).map(bindingJson))
}

// POST /repos — body: { repo: "owner/name", title? }. Verifies with the
// caller's own token that the repo exists and carries a README.yml at the
// root (the album_template manifest) so bindings can't point at arbitrary
// non-gallery repos. Idempotent re-bind updates the title.
async function bindRepo(env: Env, me: string, token: string, body: any): Promise<Response> {
  const repo = stringField(body?.repo, 'repo', 3, 140)
  if (typeof repo !== 'string') return repo
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo)) {
    return json({ error: 'repo must be "owner/name"' }, 400)
  }
  let title: string | null = null
  if (body?.title !== undefined) {
    const t = stringField(body.title, 'title', 1, 100)
    if (typeof t !== 'string') return t
    title = t
  }

  // Gallery-shape check via the caller's token (covers private repos).
  let check: Response
  try {
    check = await fetch(`https://api.github.com/repos/${repo}/contents/README.yml`, {
      headers: {
        'authorization': `Bearer ${token}`,
        'accept': 'application/vnd.github+json',
        'user-agent': 'splashg-data',
      },
    })
  } catch (e: any) {
    return json({ error: 'github unreachable: ' + (e?.message || e) }, 502)
  }
  if (check.status === 404) {
    return json({ error: 'repo not found or missing README.yml (not a gallery repo)' }, 400)
  }
  if (!check.ok) {
    return json({ error: `github error checking repo (${check.status})` }, 502)
  }

  // Make sure the users row exists even if the client never called /me
  // (bindings FK-references users).
  const now = Date.now()
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO users (login, name, avatar_url, created_at, updated_at)
       VALUES (?1, NULL, NULL, ?2, ?2)
       ON CONFLICT(login) DO NOTHING`,
    ).bind(me, now),
    env.DB.prepare(
      `INSERT INTO bindings (login, repo, title, added_at) VALUES (?1, ?2, ?3, ?4)
       ON CONFLICT(login, repo) DO UPDATE SET title = ?3`,
    ).bind(me, repo, title, now),
  ])

  return json({ repo, title: title ?? undefined, addedAt: now }, 201)
}

// DELETE /repos/:owner/:name — idempotent.
async function unbindRepo(env: Env, me: string, repo: string): Promise<Response> {
  await env.DB.prepare(
    `DELETE FROM bindings WHERE login = ?1 AND repo = ?2`,
  ).bind(me, repo).run()
  return new Response(null, { status: 204 })
}

// GET /follows — profiles + bindings of everyone I follow.
async function listFollows(env: Env, me: string): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT u.login, u.name, u.avatar_url FROM follows f
     JOIN users u ON u.login = f.followee
     WHERE f.follower = ?1 ORDER BY f.created_at ASC`,
  ).bind(me).all<UserRow>()
  const users = rows.results || []
  const grouped = await bindingsFor(env, users.map(u => u.login))
  return json(users.map(u => ({
    ...userJson(u),
    repos: (grouped.get(u.login) || []).map(bindingJson),
  })))
}

// POST /follows — body: { login }. The followee must have signed in at
// least once (exist in users); following an arbitrary GitHub login would
// yield an empty profile with nothing to feed from.
async function follow(env: Env, me: string, body: any): Promise<Response> {
  const login = stringField(body?.login, 'login', 1, 39)
  if (typeof login !== 'string') return login
  if (login.toLowerCase() === me.toLowerCase()) {
    return json({ error: 'cannot follow yourself' }, 400)
  }

  const target = await env.DB.prepare(
    `SELECT login FROM users WHERE login = ?1 COLLATE NOCASE`,
  ).bind(login).first<{ login: string }>()
  if (!target) {
    return json({ error: 'user has not joined SplashG yet' }, 404)
  }

  await env.DB.prepare(
    `INSERT OR IGNORE INTO follows (follower, followee, created_at) VALUES (?1, ?2, ?3)`,
  ).bind(me, target.login, Date.now()).run()
  return json({ ok: true, login: target.login })
}

// DELETE /follows/:login — idempotent.
async function unfollow(env: Env, me: string, login: string): Promise<Response> {
  await env.DB.prepare(
    `DELETE FROM follows WHERE follower = ?1 AND followee = ?2 COLLATE NOCASE`,
  ).bind(me, login).run()
  return new Response(null, { status: 204 })
}

// GET /feed — me + followees with their bindings, one payload. Album
// resolution happens client-side.
async function readFeed(env: Env, me: string): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT u.login, u.name, u.avatar_url FROM users u
     WHERE u.login = ?1
        OR u.login IN (SELECT followee FROM follows WHERE follower = ?1)`,
  ).bind(me).all<UserRow>()
  const users = rows.results || []
  const grouped = await bindingsFor(env, users.map(u => u.login))
  return json(users.map(u => ({
    ...userJson(u),
    isMe: u.login === me || undefined,
    repos: (grouped.get(u.login) || []).map(bindingJson),
  })))
}

// GET /users/:login — profile + bindings + follow state relative to me.
async function readUser(env: Env, me: string, login: string): Promise<Response> {
  const user = await env.DB.prepare(
    `SELECT login, name, avatar_url FROM users WHERE login = ?1 COLLATE NOCASE`,
  ).bind(login).first<UserRow>()
  if (!user) return json({ error: 'user has not joined SplashG yet' }, 404)

  const grouped = await bindingsFor(env, [user.login])
  const followerCount = await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM follows WHERE followee = ?1`,
  ).bind(user.login).first<{ n: number }>()
  const followedByMe = await env.DB.prepare(
    `SELECT 1 AS x FROM follows WHERE follower = ?1 AND followee = ?2`,
  ).bind(me, user.login).first<{ x: number }>()

  return json({
    ...userJson(user),
    repos: (grouped.get(user.login) || []).map(bindingJson),
    followerCount: followerCount?.n ?? 0,
    followedByMe: !!followedByMe,
  })
}

// ---------------------------------------------------------------------------
// Helpers

function stringField(v: unknown, name: string, min: number, max: number): string | Response {
  if (typeof v !== 'string') return json({ error: `${name} must be a string` }, 400)
  const trimmed = v.trim()
  if (trimmed.length < min || trimmed.length > max) {
    return json({ error: `${name} length must be ${min}..${max}` }, 400)
  }
  return trimmed
}
