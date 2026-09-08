# Admin Presence AI Handoff

This document gives a new AI agent enough context to understand and continue the custom RustDesk admin-presence client work from zero prior knowledge.

It is intentionally public-safe. Do not replace placeholders with private hostnames, IPs, credentials, peer IDs, server keys, or enrolled admin private keys.

## 1. Project overview

This fork customizes the official RustDesk client to add an administrator-only online-device view for a self-hosted RustDesk deployment.

The admin view is only a discovery and navigation surface. Selecting a device launches RustDesk's existing connection flow for that device ID. It must not bypass target passwords, consent dialogs, permission controls, ACLs, unattended-access settings, or any other normal RustDesk security behavior.

## 2. Related repositories

Use two forks:

```text
rustdeskadmin-client/
  origin:   https://github.com/<your-user>/rustdeskadmin-client.git
  upstream: https://github.com/rustdesk/rustdesk.git

rustdeskadmin-server/
  origin:   https://github.com/<your-user>/rustdeskadmin-server.git
  upstream: https://github.com/rustdesk/rustdesk-server.git
```

Push only to your forks. Keep upstream remotes fetch-only or set their push URL to a disabled value.

## 3. Current release state: v2.2.0

The current client state is:

- Windows-only admin-presence UI implemented in Flutter.
- Embedded **Admin online devices** pane selected by the first icon on the left side of the peer-tab row.
- Auto-refresh every 5 seconds, gated by a user-visible **Auto refresh** toggle (refresh icon + checkbox) next to the online-device count; enabled by default, and the user's choice persists locally across restarts.
- The pane header shows only the left-aligned `x/x Online` count — no server address string is shown there (that lives in Settings > Network > Admin Presence instead).
- Friendly device names default to the device's own hostname (as reported by the admin API / local peer cache) rather than repeating the RustDesk ID, plus a client-local rename override per device.
- Every admin API request tries `https://` first automatically and transparently falls back to `http://` only on a transport-level failure (TLS handshake error, connection refused, timeout); a normal HTTP error response is never retried. There is no user-facing scheme setting.
- A padlock indicator next to the online-device count shows which transport actually succeeded on the last request: locked/green for HTTPS, open/orange for the HTTP fallback; hidden until a request has succeeded at least once.
- The error-info icon reports verbose diagnostics: scheme(s) attempted, HTTP status code, server-reported error field or body snippet, and raw transport exception text when neither scheme is reachable.
- Local-admin-client filtering.
- Stale/offline device retention with offline duration and per-row delete.
- Shared list/tile/grid visualization support.
- Online-first, then alphabetical sorting.

### v2.0.0+ compatibility rules

- **Auth model:** per-device ed25519 key enrollment only.
- **Server compatibility:** v2.x clients require v2.0.0+ `rustdeskadmin-server` deployments (v2.1.0/v2.2.0 client changes are client-only; no server-side changes were required).
- **Admin API address:** no separate admin host setting exists anymore. The client reuses the host configured for RustDesk's ID/rendezvous server, tries `https://` first then falls back to `http://` automatically, and always connects to admin API port `21114`.

## 4. Client auth and settings model

In the client:

- The administrator configures the normal RustDesk server under **Settings > Network > ID/Relay Server**.
- The **Admin Presence** dialog derives its display address from that configured host and shows `<id-server-host>:21114` read-only.
- The administrator pastes the private key printed once by `rustdesk-utils genadminkey <label>` and clicks **Enroll key**.
- The client stores the enrolled key locally using Windows DPAPI protection for the private material.
- The client authenticates with the paired server by requesting a challenge, signing the returned nonce with the enrolled ed25519 private key, and verifying to receive a short-lived JWT.
- The device list is then fetched from `GET /admin/v1/devices?status=online` using that JWT.

Important local option keys in this repo:

```dart
const String kOptionAdminPresenceDevices = "admin-presence-devices";
const String kOptionAdminPresencePrivateKeyEnc = "admin-presence-private-key-enc";
const String kOptionAdminPresencePublicKey = "admin-presence-public-key";
```

The normal RustDesk server host still comes from the existing `custom-rendezvous-server` option.

## 5. Important client files

| File | Purpose |
|---|---|
| `flutter/lib/models/admin_presence_model.dart` | Admin API auth, JWT handling, HTTPS-first/HTTP-fallback transport (`_requestWithFallback`), verbose transport/HTTP error builders (`AdminPresenceTransportException`, `_describeHttpError`), `activeScheme` (session-only, drives the padlock icon), refresh logic, device caching, local-ID filtering, fixed port resolution (`21114`). |
| `flutter/lib/models/admin_presence_keypair.dart` | Key import/load/clear, fingerprint derivation, DPAPI-protected private-key storage. |
| `flutter/lib/common/widgets/admin_presence_dialog.dart` | Embedded admin pane and device cards. |
| `flutter/lib/common/widgets/peer_tab_page.dart` | Adds the first-left admin selector icon and renders the admin pane. |
| `flutter/lib/models/peer_tab_model.dart` | Adds `PeerTabIndex.admin` and keeps it out of the draggable normal tab strip. |
| `flutter/lib/common/widgets/peers_view.dart` | Wires the admin logical tab into the shared peer view. |
| `flutter/lib/common/widgets/peer_card.dart` | Handles admin-tab-specific deletion behavior for stale entries. |
| `flutter/lib/desktop/pages/desktop_setting_page.dart` | Adds Settings > Network > Admin Presence, including read-only resolved address and key-enrollment UI. |
| `flutter/lib/consts.dart` | Defines admin-presence local-option keys. |

## 6. Client behavior details

`AdminPresencePane` behavior:

- Embedded in the peer-tab content area.
- Opens from the first icon on the left of the tab row.
- Auto-logins using the enrolled key when prerequisites are present.
- Auto-refreshes every 5 seconds.
- Shows server reachable/unreachable state.
- Lists online devices.
- Keeps missing devices as greyed-out stale/offline rows after successful refreshes.
- Shows offline duration for stale rows.
- Allows deleting stale rows with an `X`.
- Filters out the local admin client's own RustDesk ID.
- Shows a friendly name above the ID when the API or local peer caches provide one; defaults to the device's own hostname rather than repeating its RustDesk ID when no local rename override is set.
- Shows a padlock icon (locked/green = HTTPS, open/orange = HTTP fallback) next to the online-device count once at least one request has succeeded.

Clicking an online row calls the existing `connect(context, id)` path.

### ID normalization

RustDesk IDs may appear formatted with spaces in some UI/cache paths.

Normalize before comparisons:

```dart
String _normalizeId(String id) => id.replaceAll(' ', '').trim();
```

Use normalized comparisons for:

- Filtering out the admin client's own ID.
- Matching API devices against local peer caches for friendly names.
- Deleting stale cached entries.

## 7. Development and validation workflow

### Toolchain summary

For the Windows client build machine, install:

- Git and optional GitHub CLI.
- Rustup with the repo-pinned Rust toolchain `1.75.0-x86_64-pc-windows-msvc` plus `rustfmt`.
- Visual Studio 2022 Build Tools with the C++ workload.
- LLVM.
- Python 3.12.
- CMake, Ninja, and NASM.
- Flutter 3.24.5.
- vcpkg pinned to the revision expected by this repo.
- `flutter_rust_bridge_codegen` version `1.80.1`.

The upstream `hwcodec` dependency requires the static `x64-windows-static` vcpkg FFmpeg triplet used by this repo's overlays.

### Build commands

```powershell
cd C:\path\to\rustdeskadmin-client
cargo build --locked --features flutter,hwcodec --lib
cargo build --release --locked --features flutter,hwcodec --lib
cd flutter
flutter build windows --release
```

### Targeted validation

When changing the admin-presence client code, the narrow validation set is:

```powershell
cd C:\path\to\rustdeskadmin-client\flutter
flutter analyze lib\models\admin_presence_model.dart lib\models\admin_presence_keypair.dart lib\common\widgets\admin_presence_dialog.dart lib\common\widgets\peer_tab_page.dart lib\common\widgets\peers_view.dart lib\common\widgets\peer_card.dart lib\models\peer_tab_model.dart lib\desktop\pages\desktop_setting_page.dart lib\consts.dart
flutter test test\admin_presence_keypair_test.dart
flutter build windows --release
```

For docs-only changes, code validation is not required.

## 8. Deployment summary

Recommended end-user path: install one of the release assets from this repo's Releases page — `rustdeskadmin-client-<version>-install.exe` (self-extracting installer), `rustdeskadmin-client-<version>-x64.msi` (native MSI, suited for silent/unattended install and Group Policy/SCCM), or `rustdeskadmin-client-<version>-portable.zip` (no-install, extract and run).

After installation:

1. Configure **Settings > Network > ID/Relay Server** to point at the paired self-hosted deployment.
2. Open **Settings > Network > Admin Presence**.
3. Confirm the read-only resolved admin API address shown there.
4. Enroll the per-device private key printed by `rustdesk-utils genadminkey <label>`.
5. Verify the fingerprint against `rustdesk-utils listadminkeys` if needed.
6. Open the admin pane and confirm that listed online devices start the normal RustDesk connection flow.

## 9. Server-side reference

This repository does not contain the paired server implementation. For server internals, operational details, key lifecycle behavior, and server-side key-store hot-reload behavior, read the AI handoff and release docs in the companion `rustdeskadmin-server` repository.

From the client repo's perspective, assume only this stable contract:

- Auth is ed25519 challenge/verify.
- Online-device listing stays behind authenticated `GET /admin/v1/devices?status=online`.
- The admin API host matches the normal RustDesk ID server host, with fixed port `21114`.

## 10. Change discipline

When continuing this work:

- Keep changes additive and localized.
- Do not bypass target-side RustDesk security.
- Do not expose unauthenticated enumeration.
- Do not expose direct database/file/log access to clients.
- Update public docs and changelogs with sanitized information.
- Do not commit passwords, tokens, private keys, generated server keys, real peer IDs, or private/public lab addresses.
- Validate with the narrowest relevant tests/builds.
- Push only to fork remotes.
