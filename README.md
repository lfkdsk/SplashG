# SplashG

Browse your [album_template](https://github.com/lfkdsk/album_template) photo galleries on iOS —
your own repos plus a feed of friends you follow. MyerSplash-style UI: dark theme, waterfall
grid, floating pill tab bar.

```
iOS app (SwiftUI)                 splashg-data (CF Worker + D1)
 ├─ GitHub OAuth ──────────────►  auth.lfkdsk.org (lfkdsk-auth broker)
 ├─ /me /repos /follows /feed ─►  api.splashg.lfkdsk.org
 └─ README.yml / CONFIG.yml / ─►  api.github.com + jsDelivr/raw CDN
    git tree / images
```

The backend is deliberately thin (SplitStupid model): no user table beyond a login registry,
no sessions. Clients send their GitHub OAuth token as `Authorization: Bearer`; the Worker
resolves it to a login via GitHub `/user` per request. It stores only:

- **users** — who has signed in (login/name/avatar),
- **bindings** — which gallery repos a user attached to their profile,
- **follows** — the follow graph.

Album/photo data never touches the backend. The iOS app reads each bound repo's
`README.yml` (album manifest) + `CONFIG.yml` (CDN bases) + git tree straight from the
GitHub API, and loads images from jsDelivr (`@master` full / `@thumbnail` thumbs) with
raw.githubusercontent fallback — the same contract PictorG writes and album_template builds.

## Repo layout

```
worker/   Cloudflare Worker backend (TypeScript, D1)
ios/      SwiftUI app (xcodegen project)
```

## Backend deploy

```bash
cd worker
npm install
npx wrangler login
npx wrangler d1 create splashg        # paste database_id into wrangler.toml
npm run db:init                        # apply migrations/0001_init.sql (remote)
npx wrangler deploy
```

Then bind the custom domain `api.splashg.lfkdsk.org` in the CF dashboard
(Workers → splashg-data → Settings → Triggers → Routes). If you use a different
domain, update `Config.apiBase` in `ios/SplashG/Support/Config.swift`.

### API

| Method | Path | Purpose |
|---|---|---|
| GET | `/healthz` | health |
| GET | `/me` | register/refresh my profile; returns bindings + following |
| GET/POST | `/repos` | list / bind `{repo:"owner/name", title?}` (validates README.yml via caller token) |
| DELETE | `/repos/:owner/:name` | unbind |
| GET/POST | `/follows` | list followees (with bindings) / follow `{login}` |
| DELETE | `/follows/:login` | unfollow |
| GET | `/feed` | me + followees, each with profile + bindings |
| GET | `/users/:login` | profile + bindings + `followedByMe` |

## OAuth setup (one-time)

`lfkdsk-auth/wrangler.toml` gained a new project key (already edited in the sibling repo,
needs a redeploy of that Worker):

```
"splashg-mobile": "splashg://callback"
```

The app drives `ASWebAuthenticationSession` at
`github.com/login/oauth/authorize?...redirect_uri=https://auth.lfkdsk.org/splashg-mobile/callback&scope=repo`,
and the broker 302s the token back to `splashg://callback#oauth_token=…`.
Until the broker is redeployed, the in-app **Personal Access Token** sign-in
(repo scope) works as a fallback.

## iOS build

Requires Xcode + [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd ios
xcodegen generate
open SplashG.xcodeproj    # or:
xcodebuild -project SplashG.xcodeproj -scheme SplashG \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Dependencies (SPM, resolved automatically): [Yams](https://github.com/jpsim/Yams) for the
YAML manifests, [Kingfisher](https://github.com/onevcat/Kingfisher) for image loading/caching.

### Release signing / TestFlight

Signing is configured for team `R6QM7B7GB7` (automatic, `ios/project.yml`).

- **Run on your own device**: open the project in Xcode, pick your device, Run —
  automatic signing registers the bundle id `org.lfkdsk.splashg` on first build.
- **TestFlight / App Store**:
  1. One-time: create the app record on [App Store Connect](https://appstoreconnect.apple.com)
     (New App → bundle id `org.lfkdsk.splashg`).
  2. Archive + upload, either from Xcode (Product → Archive → Distribute App), or CLI:

     ```bash
     cd ios && xcodegen generate
     xcodebuild -project SplashG.xcodeproj -scheme SplashG -configuration Release \
       -destination 'generic/platform=iOS' -archivePath build/SplashG.xcarchive \
       archive -allowProvisioningUpdates
     xcodebuild -exportArchive -archivePath build/SplashG.xcarchive \
       -exportOptionsPlist ExportOptions.plist -exportPath build/export \
       -allowProvisioningUpdates
     ```

     `ExportOptions.plist` uploads straight to App Store Connect; set its
     `destination` to `export` if you just want an `.ipa`.
  3. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `ios/project.yml`
     for each release.

The App Store icon lives at `ios/SplashG/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
(single-size, Xcode derives the rest).

**Xcode Cloud**: works out of the box — `ios/ci_scripts/ci_post_clone.sh` regenerates the
project after clone and installs the pinned `ios/Package.resolved`. If you add or bump an
SPM dependency, copy the refreshed resolved file back out:
`cp ios/SplashG.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved ios/Package.resolved`.

## App structure

- **Feed** — waterfall of photos from every album you or your followees published, newest album first.
- **Random** — shuffled sample across all galleries (dice to reshuffle).
- **Collections** — album cards (cover, `N photos · Curated by X`); tap → album page → photo pager.
- **Search** — filter albums/photos, or look up a GitHub login to follow.
- **Profile** — bind/unbind gallery repos (picker over your GitHub repos or manual `owner/name`),
  manage follows, sign out.

Notes:

- Images assume public repos (CDN URLs). Private gallery repos will list but not render images.
- Masonry card aspect ratios are deterministic pseudo-ratios (manifests carry no dimensions);
  cards crop with `scaledToFill`, matching the MyerSplash look.
- If the backend is unreachable the app degrades gracefully: GitHub identity still works,
  social features pause, browsing cached galleries continues.
