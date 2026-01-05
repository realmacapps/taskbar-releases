# RealTaskBar Releases

This repository hosts the public update feed (`appcast.xml`) for RealTaskBar using Sparkle 2.

## Appcast URL

- `https://realmacapps.github.io/taskbar-releases/appcast.xml`

## Publishing a release (zip for Sparkle)

This repo is designed to fully automate publishing via GitHub Actions.

### One-time setup

1. Add repository secret `SPARKLE_ED25519_PRIVATE_KEY` (Settings → Secrets and variables → Actions).
   - Must match the public key embedded in the app’s `Info.plist` as `SUPublicEDKey`.

### Publish flow (fully automated)

1. Put a raw artifact zip into `releases/raw/`.
   - Supported: a `.zip` containing `RealTaskBar.app` OR a `.zip` containing a `.xcarchive` with `Products/Applications/*.app`.
2. Commit + push to `main` (or use `./scripts/submit_raw.sh /path/to/raw.zip`).

GitHub Actions will:
- Extract the `.app`, build a Sparkle-friendly update `.zip` and a `.dmg` (for website downloads).
- Sign the update zip with Sparkle `sign_update` (Ed25519).
- Create/update a GitHub Release tag `v<shortVersion>-<build>`, upload assets.
- Update `appcast.xml` and remove the raw artifact from the repo.
