# RealTaskBar Releases

This repository hosts the public update feed (`appcast.xml`) for RealTaskBar using Sparkle 2.

## Appcast URL

- `https://realmacapps.github.io/taskbar-releases/appcast.xml`

## Publishing a release (zip for Sparkle)

High-level steps:

1. Build a signed Release build (Developer ID), notarize it, and staple the ticket.
2. Create a `.zip` update archive from the `.app` (Sparkle-friendly zip).
3. Upload the `.zip` as a GitHub Release asset.
4. Update `appcast.xml` with a new `<item>` entry including:
   - `sparkle:version` (CFBundleVersion)
   - `sparkle:shortVersionString` (CFBundleShortVersionString)
   - `sparkle:edSignature` + `length` (from Sparkle `sign_update`)
