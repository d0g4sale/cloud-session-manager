# Cloud Session Manager

A macOS menu bar app for AWS SSO management: sign in to AWS IAM Identity Center, monitor
session and credential expiry, and switch AWS CLI profiles — all from the menu bar.

## Features

- **Menu bar status** — the AWS logo with a live countdown until the default profile's
  credentials expire (as reported by `aws configure export-credentials`). Above an hour
  it shows `Xh Ym`, under five minutes it counts down `m:ss`, and when a fresh login is
  required a small warning badge appears next to the logo.
- **Automatic token renewal** — Identity Center issues short-lived access tokens (often
  1 hour) alongside a refresh token; the app renews the access token just before expiry,
  exactly like the AWS CLI does, so tools relying on the cache keep working all session.
- **Quick profile switching** — the menu lists every profile in `~/.aws/config`; clicking
  one makes it the default profile (its settings are copied into the `[default]` section,
  with a `profile = <name>` marker recording the selection, so plain `aws` commands use it).
- **Log in / log out** — runs `aws sso login --sso-session <session>` (opens your browser)
  and `aws sso logout` directly from the menu.
- **Profile manager** — a window for creating, editing, and deleting profiles and
  `sso-session` blocks: name, SSO session, account ID, role, region, and output format.
- **Discover accounts from SSO** — when you're signed in, the new-profile editor
  lists the accounts your SSO login can reach (filtered to those that don't already
  have a profile) and the roles available in the account you pick — the same
  `ListAccounts` / `ListAccountRoles` lookups `aws configure sso` performs. Selecting
  an account also suggests a profile name. Both fields keep a "type it manually"
  escape hatch for accounts the lookup can't see or when you're not signed in.
- **Copy export command** — puts `export AWS_PROFILE=<name>` on the clipboard for shells
  or tools that prefer the environment variable over the default profile.
- **AWS CLI status** — the menu shows the installed AWS CLI version (as `aws --version`
  reports it). If the CLI isn't found, it instead offers to copy `brew install awscli`,
  copy AWS's official pkg installer command, or open the official AWS install
  instructions — the app can't sign in or resolve credentials without the CLI.

## Safety

- Comments, blank lines, and unrecognized keys in `~/.aws/config` are preserved on rewrite.
- Before every save, the previous config is backed up to `~/.aws/config.awssso.bak`.
- Token cache writes are limited to the same refresh the AWS CLI performs: exchanging the
  cached refresh token for a new access token and updating `expiresAt` in place.

## Building

Requires macOS 14+ and the Xcode Command Line Tools (Swift 5.10+). No full Xcode needed.

```sh
./build-app.sh                  # builds .build/release and assembles the .app
open "Cloud Session Manager.app"
```

To start it at login: System Settings → General → Login Items → add `Cloud Session Manager.app`.

## Testing

```sh
./run-tests.sh     # runs the Swift Testing suite
```

Tests use the Swift Testing framework. It ships with the Command Line Tools but
its framework/dylib paths aren't wired into `swift test` there, so `run-tests.sh`
passes them explicitly. With a full Xcode selected (`xcode-select`), a plain
`swift test` works too.

## Assets

The menu bar uses Apple's `cloud.fill` SF Symbol. The app icon is an original cloud +
keyhole design in `Resources/AppIcon.svg`, rendered to `Resources/AppIcon.icns` (rebuild
it with `rsvg-convert` + `iconutil` — see the commands in git history). "AWS" and "Amazon
Web Services" are trademarks of Amazon.com, Inc.; this is an unaffiliated personal utility,
not an AWS product, and it does not use any AWS logo or trademark in its branding.

## How status is determined

The menu bar countdown is the expiration of the default profile's resolved **role
credentials**, fetched via `aws configure export-credentials` (polled once a minute and
immediately after logins and profile switches). This is the authoritative answer to
"how long will my aws commands keep working" — the CLI caches these credentials in
`~/.aws/cli/cache`, so polling normally just reads the cached value.

Separately, the app watches the SSO **access token** at
`~/.aws/sso/cache/<sha1(session-name)>.json`. That token is short-lived (often 1 hour);
the app renews it via the cached refresh token shortly before expiry — the same SSO-OIDC
call the AWS CLI makes — so credential fetches keep succeeding for the whole SSO
session. When Identity Center refuses a renewal (`invalid_grant`), the session is
definitively over and the menu bar flips to the warning state, while still counting down
any role credentials that remain valid.
