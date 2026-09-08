# Admin Presence Change Log

All notable changes to this custom administrator-presence feature are recorded here.

Entries are grouped by date, newest first.

## v2.1.0 (2026-09-08)

### Changed

- Removed the "Server: `<ip>`:`<port>`" text from the Admin online devices pane header; the online-device count now shows left-aligned on its own.
- Added an "Auto refresh" control (refresh icon + checkbox, enabled by default) to the pane header. The 5-second periodic refresh now honors this toggle, and the user's choice persists locally across restarts.

### Investigated (no change)

- Investigated why a device's default editable display name repeats its RustDesk ID instead of showing its hostname. Root cause: the upstream `RegisterPeer` rendezvous message carries only `id`/`serial`, never a hostname, so the server has no hostname to hand back for devices the admin client has never connected to directly. The existing local-cache fallback (Recent Sessions/Favorites/LAN/Address Book) remains the best available behavior without forking the shared `hbb_common` protocol submodule; kept as-is per product decision.

## v2.0.0 (2026-09-08)

### Breaking changes

- Removed the legacy shared-token authentication path from the client documentation and release guidance. v2.0.0 clients use per-device ed25519 key enrollment only and are compatible only with v2.0.0+ `rustdeskadmin-server` deployments.
- Removed the separate configurable admin server address from the client workflow. The Admin Presence dialog now reuses the host already configured for the RustDesk ID/rendezvous server and always targets admin API port `21114`.

### Added

- Added per-device ed25519 key enrollment in Settings > Network > Admin Presence. Administrators paste the private key printed once by `rustdesk-utils genadminkey <label>`, enroll it locally, and can verify the enrolled fingerprint against `rustdesk-utils listadminkeys`.
- Added DPAPI-protected local storage for the enrolled admin private key material on Windows.
- Added inline per-device rename support in the Admin online devices pane; rename overrides remain local to the admin client and are never sent to the server.
- Added a public-safe AI handoff document plus expanded build, packaging, deployment, and release-installation guidance for this fork.

### Changed

- Switched the client auth flow to the paired server's ed25519 challenge/verify API, while keeping downstream device-list behavior unchanged after JWT issuance.
- Updated the Admin Presence dialog to show the resolved admin API address read-only instead of editable host/port fields.
- Kept the admin pane embedded in the peer-tab area with the first-left selector icon, 5-second auto-refresh, API reachability indicator, local-client filtering, stale/offline retention with offline duration, and `X` deletion of stale rows.
- Kept friendly-name display and local friendly-name overrides, and ensured the shared list/tile/grid visualization switch applies to the admin pane.
- Sorted devices online-first, then alphabetically by display name.
- Clarified public documentation, installer-based deployment guidance, and compatibility notes for the v2.0.0 release.

## 2026-09-07 01:23 (`e990e01d9` — Polish admin-presence UI, sanitize docs, add AI handoff and build/deploy guides)

### Added

- Added a public-safe AI handoff document (`docs/ADMIN_PRESENCE_AI_HANDOFF.md`) with generated/example values for future agents with no prior context on this fork.
- Added consolidated "How to Build", "How to Set Up the Development Environment", and "How to Deploy" sections to `docs/ADMIN_PRESENCE_DEVELOPMENT.md` and the AI handoff document.

### Changed

- Moved the admin selector to the first left-side icon (previously first-right, then a popup), removed the manual refresh and logout actions from the pane (the pane already auto-refreshes and auto-authenticates from saved settings).
- Fixed friendly-device-name lookup so RustDesk IDs formatted with spaces (for example a 10-digit ID displayed as `1 262 916 439`) are normalized before comparison, so the hostname is found and shown instead of falling back to the raw ID.
- Fixed an admin-presence device-list request that was sending a literal placeholder string instead of the real `Authorization` header.
- Added inline code comments at every admin-presence integration point (`admin_presence_dialog.dart`, `admin_presence_model.dart`, `peer_card.dart`, `peer_tab_page.dart`, `peers_view.dart`, `peer_tab_model.dart`, `desktop_setting_page.dart`, `consts.dart`) to make the customizations easy to locate and review.
- Added public deployment guidance reminders in the docs about keeping administrative credentials high-entropy and rotating the JWT secret if disclosure is suspected.
- Removed lab-specific hostnames, IP addresses, peer IDs, paths, generated keys, and credentials from public documentation.
- Reorganized this changelog into dated sections (newest first) matching actual commit history instead of a single flat `Unreleased` list.

## 2026-09-07 00:25 (`ab8fd959a` — Embed admin presence pane in peer tabs)

### Added

- Added friendly device-name display above the RustDesk ID when the API or local peer caches provide a name.
- Added a live server status indicator, 5-second auto-refresh, local-admin-client filtering, greyed-out stale/offline device entries with offline duration, and an `X` action to delete stale entries.

### Changed

- Reworked the admin-presence UI from a popup dialog into an embedded peer-tab pane ordered beside Recent Sessions.
- The admin-presence pane now auto-authenticates from saved settings and directs users to Settings > Network when configuration is missing.

## 2026-09-06 23:55 (`adb2739cf` — Document lab client server alignment)

### Added

- Documented that the admin API path and normal RustDesk rendezvous/relay settings must point to the same self-hosted deployment for click-to-connect to find listed devices.

## 2026-09-06 23:51 (`ef8121494` — Document admin presence deployment validation)

### Added

- Deployed the release build to a private Windows endpoint VM and validated online/offline/online presence behavior against the lab admin API.

## 2026-09-06 23:31 (`1679f4532` — Add Windows admin presence view)

### Added

- Implemented the Windows Flutter admin-presence UI: desktop entry beside Recent Sessions, online-device list, refresh/logout, and standard click-to-connect behavior.
- Added Settings > Network > Admin Presence configuration for the admin API server address and token, so administrators do not have to enter them each time.

### Changed

- Added persisted admin-presence settings for the server address (`admin-presence-server`) and admin token (`admin-presence-token`).

## 2026-09-06 21:27 (`e46c9a351` — Record completed dev environment setup and baseline validation)

### Added

- Completed Windows dev toolchain setup: Rust 1.75.0 (pinned), rustfmt, VS2022 Build Tools/C++, LLVM, Python 3.12, CMake/Ninja/NASM, Flutter 3.24.5, and the repository-pinned vcpkg revision.
- Diagnosed and completed the static (`x64-windows-static`) vcpkg FFmpeg build required by the upstream `hwcodec` dependency; root cause was RAM exhaustion from default build parallelism on this laptop, fixed with `VCPKG_MAX_CONCURRENCY=1` / `CL=/MP1`.
- Installed the correct `flutter_rust_bridge_codegen` v1.80.1 and regenerated the gitignored FFI bridge sources; verified the untouched upstream baseline builds cleanly (`cargo build` debug and release, `flutter build windows --release`).
- Stood up a private Hyper-V lab and corrected a subnet-mask mismatch that blocked VM-to-VM traffic.
- Validated, using the untouched upstream baseline client build, that a Windows endpoint registers with the lab rendezvous server — confirming the environment is ready for admin-presence feature development.

## 2026-09-06 18:06 (`f36c43811` — Add admin-presence development environment and changelog)

### Added

- Initial development environment and integration contract documentation for the administrator-only online-device view.
