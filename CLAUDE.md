# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS menu-bar app (SwiftUI, `MenuBarExtra`) that manages AWS IAM Identity Center (SSO) sessions. It shows SSO/credential status at a glance, signs in/out, auto-renews the SSO access token before it expires, and provides a GUI editor for the profiles and sso-sessions in `~/.aws/config`. The product ships as **"AWS Sessions.app"** (bundle id `com.mckaymic.cloud-session-manager`); the Xcode target/scheme is `cloud-session-manager`.

## Commands

Xcode project (`cloud-session-manager.xcodeproj`), scheme `cloud-session-manager`. There is no Package.swift — build via xcodebuild.

```bash
# Build
xcodebuild build -project cloud-session-manager.xcodeproj -scheme cloud-session-manager

# Run all unit tests (matches what CI gates releases on)
xcodebuild test -project cloud-session-manager.xcodeproj -scheme cloud-session-manager \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# Run a single test suite or test (Swift Testing, not XCTest)
xcodebuild test -project cloud-session-manager.xcodeproj -scheme cloud-session-manager \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:cloud-session-managerTests/ConfigSaveTests
```

Tests use the **Swift Testing** framework (`import Testing`, `@Suite`, `@Test`, `#expect`), not XCTest. Deployment target is macOS 26.0; Swift 5.

Releases run via GitHub Actions: `auto-release.yml` (manual `workflow_dispatch`, computes the next semver tag) and `release.yml` (on `v*` tags), both calling the reusable `release-build.yml`, which runs the unit tests, then Developer ID–signs, notarizes, and attaches a DMG to the GitHub Release. `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in the bundle are stamped by CI; a local build shows "dev" (see `AppVersion`).

## Architecture

The app does **not** own AWS state — the AWS CLI and its files are the source of truth. The app reads/writes `~/.aws/config`, reads the CLI's SSO token cache, replicates two CLI network calls itself, and shells out to `aws` only for actions with side effects (login/logout, credential export). Everything is polled on a **1-second timer** in `AppState`, so changes made outside the app (editing config by hand, `aws sso login` in a terminal) are picked up without a relaunch.

**`AppState`** (`AppState.swift`) — the single `@MainActor ObservableObject` that drives the whole UI. Its `tick()` re-locates the CLI, reloads config if the file's mtime changed, refreshes token status, and polls credential expiry (throttled to 60s). Key derived state: `activeSessionName`, `loginNeeded`, `menuBarBadge`, `statusDescription`, `needsSetup`. It is constructed with injectable `config` and `cliPath` and an `autostart` flag so tests can drive it without a timer or real subprocesses.

**Config layer** (`ConfigFile.swift`) — `ConfigDocument`/`ConfigSection` parse and serialize the AWS shared-config INI **while preserving comments, blank lines, and unknown keys** (round-trip safe). `AWSConfig` locates the files under an injectable `.aws` directory and keeps a `config.awssso.bak` backup on every save. `Models.swift` maps sections to `ProfileInfo`/`SSOSessionInfo` (`[profile X]`, `[sso-session Y]`).

**The `[default]` marker convention** — making a profile the default copies its keys into `[default]` plus a `profile = <name>` marker line recording the source. This marker lets the app (a) know which named profile is default and (b) re-sync `[default]` when the source profile drifts (`reconcileDefaultFromMarker` / `reconcileDefaultDrift`). A **hand-authored `[default]` with no marker is never touched.** When exactly one profile exists and there's no `[default]` at all, it's auto-adopted as default.

**SSO token & credentials** (`Models.swift`, `TokenRefresher.swift`, `CredentialsFetcher.swift`) — the CLI caches the OIDC token at `~/.aws/sso/cache/<sha1(sessionName)>.json` (`SSOTokenCache`). `expiresAt` is the short-lived **access token** (~1h); the session lives longer and is kept alive by exchanging the refresh token. `TokenRefresher` replicates the CLI's SSO-OIDC `CreateToken` refresh call directly (`https://oidc.<region>.amazonaws.com/token`) and rewrites the cache file with 0600 perms — distinguishing a genuine session-ended (`invalid_grant` etc.) from a transient failure. `CredentialsFetcher` shells out to `aws configure export-credentials` for the authoritative role-credential expiry driving the countdown.

**Account/role discovery** (`SSOPortalClient.swift`) — lists accounts/roles by calling the SSO Portal REST API (`portal.sso.<region>.amazonaws.com`) directly with the cached bearer token, so the token stays out of process arguments (unlike shelling out). Populates the profile editor's account/role dropdowns.

**UI** — `CloudSessionManagerApp.swift` (menu-bar-only, `.accessory` activation policy / `LSUIElement`; the label's `onAppear` auto-opens the Profile Manager when `needsSetup`), `MenuContent.swift` (the menu), `ProfileManagerView.swift` (the "AWS Profiles" window editor), `MenuBarIcon.swift` (AWS-logo icon with a colored status badge), `AWSReference.swift` (static region/output lists + form controls).

## Conventions worth keeping

- **`AppState.awsSubprocessEnvironment()` strips `AWS_PROFILE`/`AWS_DEFAULT_PROFILE`** before every `aws` subprocess. The app always selects the profile explicitly; a stale inherited env var must not leak in. Use it for any new subprocess.
- Config-mutating logic lives on `ConfigDocument` where possible (filesystem-free, unit-testable); `AppState` handles persistence and reload.
- Network/subprocess helpers return explicit result enums (`.success`/`.unauthorized`/`.failure`, `.refreshed`/`.sessionEnded`/`.transientFailure`) rather than throwing, so callers can distinguish "sign in again" from "retry later" — preserve that distinction when extending them.
- Keep the read side poll-based and side-effect-free; only login/logout and credential export invoke the CLI.
