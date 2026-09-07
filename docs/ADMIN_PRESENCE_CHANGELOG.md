# Admin Presence Change Log

All notable changes to this custom administrator-presence feature are recorded here.

Entries are grouped by date, newest first. Each dated section corresponds to one or more commits on that date; the `Unreleased` section at the top holds changes not yet committed.

## Unreleased

### Added

- Added inline rename ("edit"/pencil icon) on each device row in the admin online-devices pane. The custom display name is stored **locally on this client only** (never sent to the server), overrides the reported hostname, and persists across refreshes/reconnects until the administrator renames it again or deletes the device row.
- Added fork-specific sections to the top-level `README.md` describing this fork's admin-presence feature, linking to the paired server fork and the unmodified upstream `rustdesk/rustdesk` project, and giving a quick-start clone/build snippet.

### Changed

- Fixed the admin online-devices pane to honor the same list/tile/grid visualization switch used by Recent Sessions and every other peer tab (previously the pane always rendered a fixed list regardless of the selected view type).
- Device list sort now explicitly sorts online devices first, then alphabetically by display name (custom name if set, otherwise hostname, otherwise ID), applied both on initial cached-list load and after every refresh.
- Diagnosed and fixed a corrupted `desktop_multi_window_plugin.dll` in a stale local CMake build-tree cache on the development laptop (Windows reported `STATUS_INVALID_IMAGE_HASH` / error `0xc0e90002`) by clearing the plugin's CMake build directory and forcing `flutter build windows --release` to regenerate it; this was a local build-cache corruption issue, not a source-code defect (the same commit built and ran correctly on the endpoint test VM).
- Repository renamed on GitHub from `rustdesk` to `rustdeskadmin-client` (origin remote updated to match; `upstream` remote unchanged, still points read-only at `rustdesk/rustdesk`).

## 2026-09-07 01:23 (`e990e01d9` — Polish admin-presence UI, sanitize docs, add AI handoff and build/deploy guides)

### Added

- Added a public-safe AI handoff document (`docs/ADMIN_PRESENCE_AI_HANDOFF.md`) with generated/example values for future agents with no prior context on this fork.
- Added consolidated "How to Build", "How to Set Up the Development Environment", and "How to Deploy" sections to `docs/ADMIN_PRESENCE_DEVELOPMENT.md` and the AI handoff document.

### Changed

- Moved the admin selector to the first left-side icon (previously first-right, then a popup), removed the manual refresh and logout actions from the pane (the pane already auto-refreshes and auto-authenticates from saved settings).
- Fixed friendly-device-name lookup so RustDesk IDs formatted with spaces (for example a 10-digit ID displayed as `1 262 916 439`) are normalized before comparison, so the hostname is found and shown instead of falling back to the raw ID.
- Fixed an admin-presence device-list request that was sending a literal placeholder string instead of the real `Bearer <jwt>` Authorization header.
- Added inline code comments at every admin-presence integration point (`admin_presence_dialog.dart`, `admin_presence_model.dart`, `peer_card.dart`, `peer_tab_page.dart`, `peers_view.dart`, `peer_tab_model.dart`, `desktop_setting_page.dart`, `consts.dart`) to make the customizations easy to locate and review.
- Added public deployment guidance reminders in the docs about keeping the admin token high-entropy and rotating the JWT secret if disclosure is suspected.
- Removed lab-specific hostnames, IP addresses, peer IDs, paths, generated keys, and credentials from public documentation.
- Reorganized this changelog into dated sections (newest first) matching actual commit history instead of a single flat "Unreleased" list.

## 2026-09-07 00:25 (`ab8fd959a` — Embed admin presence pane in peer tabs)

### Added

- Added friendly device-name display above the RustDesk ID when the API or local peer caches provide a name.
- Added a live server status indicator, 5-second auto-refresh, local-admin-client filtering, greyed-out stale/offline device entries with offline duration, and an `X` action to delete stale entries.

### Changed

- Reworked the admin-presence UI from a popup dialog into an embedded peer-tab pane ordered beside Recent Sessions.
- The admin-presence pane now auto-authenticates from saved settings and directs users to Settings > Network when configuration is missing.

## 2026-09-06 23:55 (`adb2739cf` — Document lab client server alignment)

### Added

- Documented that the admin API setting and normal RustDesk rendezvous/relay settings must point to the same self-hosted deployment for click-to-connect to find listed devices.

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
