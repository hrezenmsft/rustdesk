# Admin Presence Client Development

## Purpose

This fork adds an administrator-only Windows client view for devices currently online with the paired RustDesk rendezvous server. Selecting a listed device must start the existing RustDesk connection flow; it does not bypass target-side approval, password, or permission controls.

## Server Contract

The client consumes a versioned authenticated endpoint: `GET /admin/v1/devices?status=online`. The server owns presence truth, authorization, expiry, and response filtering. The client must never read a shared file or database directly.

## Development Environment

- Current UI implementation: Flutter under `flutter/`.
- Recommended lab topology: one Windows administrator client, one RustDesk rendezvous/relay server, and at least one Windows endpoint client on a private test network. Keep concrete hostnames, IP addresses, credentials, generated keys, and peer IDs out of this public documentation.

### Networking Notes

- Validate the feature in a private lab before exposing any service publicly.
- Ensure the administrator client and endpoint clients use the same self-hosted RustDesk rendezvous/relay server; the admin device list and RustDesk connection flow are separate paths and must point to the same deployment for click-to-connect to work.
- Do not document or commit lab-specific DHCP leases, public IPs, private IPs, peer IDs, passwords, tokens, or server keys.

### Toolchain

- Rust 1.75.0-x86_64-pc-windows-msvc (client-pinned), rustfmt, VS2022 Build Tools (C++ workload), LLVM, Python 3.12, CMake/Ninja/NASM, Flutter 3.24.5, and the repository-pinned vcpkg revision.
- `x64-windows-static` vcpkg triplet (required by the `hwcodec` dependency's `build.rs`) built successfully via `vcpkg install --classic "ffmpeg[amf,core,nvcodec,qsv]:x64-windows-static" ...`. On this 4c/8t + 12 GB RAM laptop the default parallelism OOM-thrashed; use `VCPKG_MAX_CONCURRENCY=1` and `CL=/MP1` under VsDevCmd if it needs to be rebuilt.
- `flutter_rust_bridge_codegen` must be **v1.80.1** (`cargo install flutter_rust_bridge_codegen --version 1.80.1 --features "uuid" --locked`), matching `flutter_rust_bridge = "=1.80"` pinned in `Cargo.toml`. Do not use the fork referenced in `build.py`'s Docker snippet — it targets an incompatible `ffigen` range.
- Baseline validation performed on the untouched upstream code (no admin-presence changes yet):
  - `cargo build --locked --features flutter,hwcodec --lib` (debug) — passes.
  - `cargo build --release --locked --features flutter,hwcodec --lib` — passes.
  - `flutter build windows --release` — passes, produces `flutter/build/windows/x64/runner/Release/rustdesk.exe`.
  - This release build, deployed to a private Windows endpoint VM and pointed at the private rendezvous service, successfully registered with `hbbs` (`update_pk` logged) — confirms end-to-end reachability of the lab rendezvous path before any admin-presence code is added. Full interactive connect (target consent/password prompt) was not exercised non-interactively by design, since bypassing that prompt is explicitly out of scope; it will be exercised as part of end-to-end validation once the admin device-list view exists.

  ### Implemented Admin Presence Client

  - Added a desktop-only **Admin online devices** pane directly in the existing peer-tab space, ordered beside Recent Sessions.
  - Added an **Admin Presence** entry under Settings > Network for the admin API server address (`host:port`) and admin token, stored in the local Flutter options store for the lab/admin workflow.
  - The pane calls `POST /admin/v1/auth/login`, then `GET /admin/v1/devices?status=online` using the bearer JWT. Selecting a device calls the existing `connect(context, id)` flow, preserving target password, consent, and permission checks.
  - The left-side admin action is the first icon before the normal peer tabs and opens the embedded pane without adding a draggable tab item. The pane auto-refreshes every 5 seconds, shows whether the admin API server is reachable, filters out the local admin client's own RustDesk ID (including formatted IDs with spaces), and keeps previously seen devices as greyed-out offline/stale entries with an offline duration and an `X` delete action.
  - The device list displays a friendly device name above the RustDesk ID when the API or local peer caches provide one; otherwise it falls back to the ID.
  - Administrators can override the displayed name per device via an inline rename (pencil) action; the override is stored **locally on this client only**, is never sent to the server, and persists across refreshes/reconnects until it is changed again or the device row is deleted.
  - The list/tile/grid visualization switch shared with every other peer tab (Recent Sessions, Favorites, etc.) also applies to the admin pane; devices are sorted online-first, then alphabetically by display name.
  - Deployment validation copied the release build to a private endpoint VM and confirmed online/offline/online behavior across the rendezvous registration timeout.
  - If the admin list works but connection fails with "target device is offline or does not exist", check the admin client's normal RustDesk server settings. This usually means the admin API setting points to the self-hosted server but the normal RustDesk connection flow still points to a different rendezvous/relay server. Align the normal RustDesk server settings and server key with the same self-hosted deployment.

## How to Set Up the Development Environment

1. Install Git, GitHub CLI (optional), and `rustup`.
2. Pin the Rust toolchain this repo expects: `rustup toolchain install 1.75.0-x86_64-pc-windows-msvc` then `rustup component add rustfmt --toolchain 1.75.0-x86_64-pc-windows-msvc`. Set it as the directory override from inside the repo: `rustup override set 1.75.0-x86_64-pc-windows-msvc`.
3. Install Visual Studio 2022 Build Tools with the "Desktop development with C++" workload (needed for the MSVC linker and Windows SDK).
4. Install LLVM (used by `bindgen`) and add `C:\Program Files\LLVM\bin` to `PATH`.
5. Install Python 3.12, CMake, Ninja, and NASM (NASM is required to build some vendored codec dependencies).
6. Install Flutter 3.24.5 and add its `bin` directory to `PATH`.
7. Install vcpkg and pin it to the commit this repo's `res/vcpkg` overlay expects; set `VCPKG_ROOT` to the vcpkg checkout.
8. Install `flutter_rust_bridge_codegen` **v1.80.1** exactly (`cargo install flutter_rust_bridge_codegen --version 1.80.1 --features "uuid" --locked`) — this must match the `flutter_rust_bridge = "=1.80"` pin in `Cargo.toml`.
9. Clone your fork and add the upstream remote read-only:
   ```powershell
   git clone https://github.com/<your-fork>/rustdeskadmin-client.git
   cd rustdeskadmin-client
   git remote add upstream https://github.com/rustdesk/rustdesk.git
   git remote set-url --push upstream DISABLED
   ```
10. Install the native dependencies vcpkg needs for the dynamic `x64-windows` triplet, then the static `x64-windows-static` triplet required specifically by the `hwcodec` dependency's `build.rs`:
    ```powershell
    vcpkg install --classic "ffmpeg[amf,core,nvcodec,qsv]:x64-windows-static" `
      --overlay-ports="res\vcpkg" --overlay-triplets="res\vcpkg-triplets"
    ```
    On memory-constrained machines this can OOM-thrash under default parallelism; set `VCPKG_MAX_CONCURRENCY=1` and `CL=/MP1` (run from inside a VS Developer command prompt, e.g. via `VsDevCmd.bat`) if it stalls or fails.

## How to Build

- Rust library only (fast check that FFI/native code compiles): `cargo build --locked --features flutter,hwcodec --lib` (add `--release` for the release profile).
- Full Windows Flutter app (requires the Rust release build to exist first, since Flutter's CMake install step copies `target/release/librustdesk.dll`):
  ```powershell
  cargo build --release --locked --features flutter,hwcodec --lib
  cd flutter
  flutter build windows --release
  ```
  Output: `flutter/build/windows/x64/runner/Release/rustdesk.exe` and its supporting DLLs.
- Static analysis: `flutter analyze` from the `flutter/` directory.
- If you clean `target/` or `flutter/build/` to reclaim disk space, you must rebuild the Rust release library **before** `flutter build windows --release` will succeed again — a stale/missing `librustdesk.dll` is the most common cause of a CMake `INSTALL.vcxproj`/`cmake_install.cmake` failure after a cleanup.
- If a plugin DLL in `flutter/build/windows/x64/runner/Release/` fails to load with Windows error `0xc0e90002` (`STATUS_INVALID_IMAGE_HASH`, "não foi projetada para ser executado no Windows ou contém um erro" on pt-BR systems) even though the same commit runs fine elsewhere, the local CMake build-tree cache for that plugin is corrupted (commonly caused by a build running while the disk was nearly full). Delete `flutter/build/windows/x64/plugins/<plugin_name>/` and the corresponding `.dll` in `Release/`, then rerun `flutter build windows --release` to regenerate it; this is a local build-cache issue, not a source defect.

## How to Package a Windows Installer

This fork uses RustDesk's existing self-extracting "portable" installer packer (`libs/portable`); there is no MSI/Inno Setup step. It bundles the entire `Release/` output (including a `dylib_virtual_display.dll` built separately) into one `.exe`.

1. Build the Rust release library and the Flutter Windows app as in **How to Build** above.
2. Build the virtual-display helper DLL and copy it into the Release folder (the Flutter build does not produce this file):
   ```powershell
   cd libs\virtual_display\dylib
   cargo build --locked --release
   cd ..\..\..
   Copy-Item target\release\dylib_virtual_display.dll flutter\build\windows\x64\runner\Release\
   ```
3. Install the one Python dependency the packer needs (`brotli`), then generate and build the installer:
   ```powershell
   pip install brotli
   cd libs\portable
   python .\generate.py -f ..\..\flutter\build\windows\x64\runner\Release\ -o . -e ..\..\flutter\build\windows\x64\runner\Release\rustdesk.exe
   cd ..\..
   ```
   This compresses the whole Release folder into `libs/portable/data.bin`, then cargo-builds `target/release/rustdesk-portable-packer.exe`, a single self-extracting installer with that data embedded.
4. Rename the output to match the versioned convention (`rustdesk-utils`'s version comes from `Cargo.toml`):
   ```powershell
   Copy-Item target\release\rustdesk-portable-packer.exe ".\rustdesk-<version>-install.exe"
   ```
5. **Validate before shipping**: run the installer once on a disposable/test machine (or VM snapshot) and confirm it shows the "RustDesk - Install" UI and, if you proceed with an install, registers a `RustDesk` Windows service and an uninstall entry (`RustDesk.exe --uninstall` removes both cleanly). Running the installer to completion replaces/stops any other `rustdesk.exe` process on that machine — do not test this on a machine with a dev build you need to keep running, or expect to relaunch your dev build afterward.

## How to Deploy

### Production release package (recommended — no local build required)

Every `vX.Y.Z` tag on this repo produces a signed-off, self-extracting Windows installer (see **How to Package a Windows Installer** above for how it's built) attached to the GitHub release: `rustdeskadmin-client-<version>-install.exe`. **End users should install from this package instead of building from source** — it already contains the Admin Devices pane, no separate "admin" build step is needed.

1. **Download the installer** from the Releases page:
   ```powershell
   # find the latest tag
   gh release list --repo hrezenmsft/rustdeskadmin-client --limit 1
   # download the installer asset for that tag (replace <tag>/<version> from the output above)
   gh release download <tag> --repo hrezenmsft/rustdeskadmin-client --pattern "*-install.exe" --dir .
   ```
   or download it manually from `https://github.com/hrezenmsft/rustdeskadmin-client/releases`.
2. **Run the installer** on the target Windows machine (`rustdeskadmin-client-<version>-install.exe`). This performs a full system install (Program Files, a Windows service, an uninstall entry) and will stop/replace any other running `rustdesk.exe` process of the same name already on the machine — close any in-progress sessions first.
3. **Point the client at your server** (Settings > Network): set the ID/Relay server address and key to your `rustdeskadmin-server` deployment.
4. **Configure the admin pane** (Settings > Network > Admin Presence): set the admin API's `host:port` (default port `21114`) and the plaintext admin token — both must point at the **same** server deployment as step 3, or the device list will show devices the connect flow can't reach (or vice versa).
5. **Verify**: the new admin icon (first icon on the left of the tab bar) should open the Admin Devices pane and list currently-online devices registered with that server, refreshing automatically; selecting one launches the normal connection flow.
6. **Upgrading**: download the newer installer and run it the same way — it replaces the installed binaries and Windows service in place; local per-device rename labels and other client-local settings are preserved (they live outside the install directory).
7. **Uninstalling**: `"C:\Program Files\RustDesk\RustDesk.exe" --uninstall` (or use the uninstall entry created in Windows "Apps & features").

### Deploying an unpackaged build (lab/dev only)

- The Windows admin client and any managed Windows endpoints can also be deployed by copying the contents of `flutter/build/windows/x64/runner/Release/` (the `.exe` plus all sibling DLLs) to the target machine — there is no separate installer required for lab/dev deployments (see the previous section for producing a distributable installer instead).
- Before overwriting a running deployment, stop the existing `rustdesk.exe` process on the target machine (or use a scheduled task / service wrapper if you manage it that way) so the copy isn't blocked by a locked binary.
- Point the deployed client at your self-hosted rendezvous/relay server in Settings > Network (ID/Relay server + key), and separately configure Settings > Network > Admin Presence with the admin API's `host:port` and admin token — both must reference the **same** self-hosted server deployment, or the admin device list will show devices that "connect" flow can't reach (or vice versa).
- There is no separate build/deploy path for the admin API client logic; it ships inside the same `rustdesk.exe` as the rest of the Flutter app.

## Change Discipline

Update this document when the client/server API contract, UI behavior, authentication model, or test workflow changes. Add every user-visible or compatibility-relevant change to `docs/ADMIN_PRESENCE_CHANGELOG.md` in the same change set.
