---
name: deploy
description: Release a new FVoice version. Bumps the version, writes the English changelog, commits to main, pushes the tag and babysits the GitHub Action until the notarized DMG is published. Use when the user asks to deploy, release, publish a version, or cut a tag.
---

# FVoice deploy

Releases are fully automated by `.github/workflows/release.yml`: pushing a tag
`vX.Y.Z` builds, signs, notarizes, staples, uploads the DMG to a GitHub
Release, signs the Sparkle update and appends the appcast entry. Your job is to
prepare the release correctly, fire the tag, and watch the pipeline through.

## Steps

1. **Pick the version.** Ask the user if not given. Semver, no `v` prefix in
   files (`0.2.0`), `v` prefix only in the tag (`v0.2.0`). Check the latest
   existing tag with `git tag --sort=-v:refname | head -3` to avoid collisions.

2. **Write the changelog (English).** Collect what changed since the last tag:
   `git log $(git describe --tags --abbrev=0)..HEAD --oneline`. Update (or
   create) `CHANGELOG.md` at the repo root, newest release first:

   ```markdown
   ## 0.2.0 - 2026-08-05

   ### Added
   - ...
   ### Changed
   - ...
   ### Fixed
   - ...
   ```

   Write for users, not committers: describe behavior, not refactors. Skip
   internal-only changes. Never use em dashes.

   The workflow converts this section to HTML for Sparkle's "What's new"
   dialog (Sparkle does not render markdown), so stick to the supported
   subset: `### ` section headers, `- ` bullets and plain paragraphs. No
   links, bold, code fences or nested lists.

3. **Bump the version** in `FVoice/App/Info.plist`:
   ```sh
   /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString X.Y.Z" -c "Set :CFBundleVersion X.Y.Z" FVoice/App/Info.plist
   ```
   (The workflow also injects the tag version at build time via
   `MARKETING_VERSION`; keeping the plist in sync is for local builds and
   honesty of the committed tree.)

4. **Sanity check before tagging.** Run the tests:
   `xcodegen generate && xcodebuild -scheme FVoice -derivedDataPath build test`.
   Do not tag on red.

5. **Commit and tag.**
   ```sh
   git add CHANGELOG.md FVoice/App/Info.plist
   git commit -m "chore: release X.Y.Z"
   git push
   git tag vX.Y.Z && git push origin vX.Y.Z
   ```
   Commit message convention: conventional commits, English, with the
   Co-Authored-By trailer used across this repo.

6. **Watch the Action.**
   ```sh
   gh run list -R jacobaraujo7/fvoice -L 1        # grab the run id
   gh run watch <id> -R jacobaraujo7/fvoice --exit-status
   ```
   Watch in the background if it is long-running. On success, verify:
   - `gh release view vX.Y.Z -R jacobaraujo7/fvoice` shows the DMG asset;
   - `git pull` and confirm `appcast.xml` gained the new `<item>` (the workflow
     commits it to main).

7. **If the run fails, fix it.** Read the failing step with
   `gh run view <id> --log-failed -R jacobaraujo7/fvoice`. Common failure
   classes:
   - **Signing/keychain**: secrets `MACOS_CERT_P12`/`MACOS_CERT_PASSWORD`
     broken or expired cert. Re-export from the login keychain and
     `gh secret set`.
   - **Notarization Invalid**: fetch details with
     `xcrun notarytool log <submission-id> --keychain-profile fvoice-notary`.
     Usually a nested binary missing Developer ID or timestamp; fix in
     `tool/package.sh` (the re-sign list) rather than in the workflow.
   - **Sparkle signing**: `SPARKLE_PRIVATE_KEY` secret or the `sign_update`
     path glob in the workflow.
   - **appcast commit conflict**: someone pushed to main mid-run; re-run the
     job after rebasing is fine, the appcast step is idempotent per version.
   After fixing, delete and re-push the tag to re-run:
   `git tag -d vX.Y.Z && git push origin :vX.Y.Z && git tag vX.Y.Z && git push origin vX.Y.Z`
   (also delete the half-made release first if it exists:
   `gh release delete vX.Y.Z -R jacobaraujo7/fvoice -y`).

8. **Report** the release URL and the changelog section to the user.

## Notes

- Local end-to-end equivalent (no CI):
  `tool/package.sh X.Y.Z --keychain-profile fvoice-notary`.
- Auto-update only reaches users once the repo is public (the appcast is read
  from raw.githubusercontent.com) and only for apps installed from a DMG.
- Never put credentials in the repo or chat; secrets live in GitHub repo
  secrets and the local keychain.
