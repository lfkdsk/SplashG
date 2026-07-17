-- SplashG initial schema. Three tables, mirroring the SplitStupid
-- "identity is GitHub, roles are data" model:
--
--   users     — everyone who has signed in at least once (upserted by /me).
--               Needed so follows can be validated and profiles rendered
--               without a GitHub round-trip.
--   bindings  — which gallery repos (album_template format) a user has
--               attached to their profile. The repo itself stays on GitHub;
--               we only store the pointer plus a display title.
--   follows   — the social edge. Feed = my bindings + my followees' bindings,
--               resolved client-side against the repos' README.yml.

CREATE TABLE users (
  login TEXT PRIMARY KEY,          -- canonical GitHub login (as returned by /user)
  name TEXT,                       -- display name, may be null
  avatar_url TEXT,
  created_at INTEGER NOT NULL,     -- unix ms of first sign-in
  updated_at INTEGER NOT NULL      -- unix ms of last /me refresh
);

CREATE TABLE bindings (
  login TEXT NOT NULL REFERENCES users(login) ON DELETE CASCADE,
  repo TEXT NOT NULL,              -- "owner/name" as on GitHub
  title TEXT,                      -- display title (defaults to repo name client-side)
  added_at INTEGER NOT NULL,       -- unix ms
  PRIMARY KEY (login, repo)
);
CREATE INDEX idx_bindings_login ON bindings(login);

CREATE TABLE follows (
  follower TEXT NOT NULL REFERENCES users(login) ON DELETE CASCADE,
  followee TEXT NOT NULL REFERENCES users(login) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,     -- unix ms
  PRIMARY KEY (follower, followee),
  CHECK (follower <> followee)
);
CREATE INDEX idx_follows_followee ON follows(followee);
