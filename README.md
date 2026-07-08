# AWS Sessions

A macOS menu-bar app for managing AWS IAM Identity Center (SSO) sessions. It lives in your menu bar, shows your sign-in and credential status at a glance, keeps your SSO session alive by auto-renewing the access token before it expires, and gives you a GUI for editing the profiles and sso-sessions in `~/.aws/config` — no hand-editing INI files required.

The AWS CLI and its files remain the source of truth: the app reads and writes `~/.aws/config`, reads the CLI's SSO token cache, and shells out to `aws` for sign-in and credential export. Changes you make outside the app — editing your config by hand, running `aws sso login` in a terminal — are picked up automatically without a relaunch.

## Features

- **Status at a glance** — the menu-bar icon carries a colored badge: signed in (green), signed out (gray), attention needed (orange), or working (renewing/signing in).
- **Auto-renewing sessions** — when your short-lived access token is about to expire, the app exchanges the refresh token for a new one automatically, the same way the CLI does on demand. It only prompts you to sign in again when the underlying Identity Center session has genuinely ended.
- **Credential countdown** — shows when your default profile's resolved role credentials expire (via `aws configure export-credentials`).
- **Profile & session editor** — add, edit, and delete `[profile …]` and `[sso-session …]` entries. Account and role dropdowns are populated live from the SSO portal for the accounts your login can reach.
- **Default profile management** — pick a default with one click; the app copies the profile's settings into `[default]` and keeps them in sync if the source profile changes. Hand-authored `[default]` sections are left untouched.
- **Config-safe** — comments, blank lines, and unknown keys round-trip untouched, and every save keeps a `config.awssso.bak` backup.
- **Sign in / out** — trigger `aws sso login` / `aws sso logout` from the menu.

## Requirements

- macOS 26.0 or later
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) — if it isn't installed, the app points you at `brew install awscli` and the official installer.

## Installation

Download the latest `AWS-Sessions.dmg` from the [Releases](../../releases) page, open it, and drag **AWS Sessions** to your Applications folder. The build is Developer ID–signed and notarized, so it runs without Gatekeeper warnings.

The app runs as a menu-bar item only — it has no Dock icon or main window. On first launch, if you have no profiles configured yet, it opens the profile editor automatically.

## Getting started

1. Launch **AWS Sessions**; its icon appears in the menu bar.
2. Open **Manage Profiles** and add an sso-session (your Identity Center start URL and region), then a profile that uses it (account + role).
3. Choose a default profile.
4. Click **Log In to SSO** and complete the browser prompt.

Your shell commands then resolve against the default profile; the menu bar shows when those credentials expire and renews the session in the background.

## Development

Built with SwiftUI (`MenuBarExtra`). Open `cloud-session-manager.xcodeproj` in Xcode, or use the command line:

```bash
# Build
xcodebuild build -project cloud-session-manager.xcodeproj -scheme cloud-session-manager

# Test (Swift Testing framework)
xcodebuild test -project cloud-session-manager.xcodeproj -scheme cloud-session-manager \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

See [CLAUDE.md](CLAUDE.md) for a full tour of the architecture.

### Releasing

Releases are produced by GitHub Actions. Run the **Auto Release** workflow and pick a semver bump (patch/minor/major); it tags the commit, then builds, signs, notarizes, and attaches the DMG to a GitHub Release. Pushing a `v*` tag directly triggers the same build.
