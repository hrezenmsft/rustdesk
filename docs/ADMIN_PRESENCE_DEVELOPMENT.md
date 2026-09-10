# Admin Presence Client Development

## Purpose

This fork adds an administrator-only Windows client view for devices currently online with the paired RustDesk rendezvous server. Selecting a listed device starts the existing RustDesk connection flow; it does not bypass target-side approval, password, or permission controls.

## Server Contract

The client consumes a versioned authenticated endpoint: `GET /admin/v1/devices?status=online`.

As of v2.0.0, authentication is performed only through the paired server's per-device ed25519 challenge/verify flow. A v2.0.0 client therefore requires a v2.0.0+ `rustdeskadmin-server` deployment.

The client must never read a shared file or database directly.

## Development Environment

- Current UI implementation: Flutter under `flutter/`.
- Recommended validation topology: one Windows administrator client, one RustDesk rendezvous/relay/admin API server, and at least one Windows endpoint client on a private test network. Keep concrete hostnames, IPs, credentials, generated keys, and peer IDs out of public documentation.

### Networking Notes

- Validate the feature in a private lab before exposing any service publicly.
- Ensure the administrator client and endpoint clients use the same self-hosted RustDesk rendezvous/relay server; the admin device list and RustDesk connection flow are separate paths and must point to the same deployment for click-to-connect to work.
- As of v2.0.0, the client derives the admin API host from the normal RustDesk ID server setting (`custom-rendezvous-server`) and always uses TCP port `21114` for the admin API.
- Do not document or commit lab-specific DHCP leases, public IPs, private IPs, peer IDs, passwords, server keys, or enrolled admin private keys.

### Toolchain

- Rust 1.75.0-x86_64-pc-windows-msvc (client-pinned), rustfmt, VS2022 Build Tools (C++ workload), LLVM, Python 3.12, CMake/Ninja/NASM, Flutter 3.24.5, and the repository-pinned vcpkg revision.
- `x64-windows-static` vcpkg triplet (required by the `hwcodec` dependency's `build.rs`) built successfully via `vcpkg install --classic "ffmpeg[amf,core,nvcodec,qsv]:x64-windows-static" ...`. On memory-constrained machines the default parallelism can OOM-thrash; use `VCPKG_MAX_CONCURRENCY=1` and `CL=/MP1` under VsDevCmd if it needs to be rebuilt.
- `flutter_rust_bridge_codegen` must be **v1.80.1** (`cargo install flutter_rust_bridge_codegen --version 1.80.1 --features "uuid" --locked`), matching `flutter_rust_bridge = "=1.80"` pinned in `Cargo.toml`.

### Implemented Admin Presence Client

- Added a desktop-only **Admin online devices** pane directly in the existing peer-tab space, ordered beside Recent Sessions.
- Added an **Admin Presence** entry under Settings > Network. The dialog now shows the resolved admin API address read-only (`<id-server-host>:21114`) and provides the per-device key-enrollment UI.
- The pane authenticates by calling `POST /admin/v1/auth/challenge`, signing the server nonce with the locally enrolled ed25519 private key, then calling `POST /admin/v1/auth/verify`. Successful auth returns the short-lived JWT bearer token later used for `GET /admin/v1/devices?status=online`.
- Selecting a device calls the existing `connect(context, id)` flow, preserving target password, consent, and permission checks.
- The left-side admin action is the first icon before the normal peer tabs and opens the embedded pane without adding a draggable tab item.
- The pane auto-refreshes every 5 seconds, shows whether the admin API server is reachable, filters out the local admin client's own RustDesk ID (including formatted IDs with spaces), and keeps previously seen devices as greyed-out offline/stale entries with an offline duration and an `X` delete action.
- The device list displays a friendly device name above the RustDesk ID when the API or local peer caches provide one; otherwise it falls back to the ID.
- Administrators can override the displayed name per device via an inline rename action. The override is stored **locally on this client only**, is never sent to the server, and persists across refreshes/reconnects until it is changed again or the device row is deleted.
- The list/tile/grid visualization switch shared with every other peer tab also applies to the admin pane; devices are sorted online-first, then alphabetically by display name.
- The enrolled private key seed is encrypted at rest with Windows DPAPI (current-user scope) before being written to the local options store.
- This is a pure-Dart client customization. No Rust source file or `flutter_rust_bridge` binding changed for the v2.0.0 auth model.

## v2.0.0 Enrollment Flow

1. On the server, run `rustdesk-utils genadminkey <label>` once for each admin workstation.
2. Copy the printed private key immediately; it is shown once.
3. In this client, open **Settings > Network > Admin Presence**.
4. Confirm the read-only resolved address shown in the dialog. It should match the host already configured in **ID Server**, with port `21114` appended.
5. Paste the private key into **Admin key** and click **Enroll key**.
6. Verify that the fingerprint shown by the client matches `rustdesk-utils listadminkeys` on the server.
7. If needed, **Remove key from this device** only clears local enrollment. Server-side revocation is separate and must be performed with `rustdesk-utils revokeadminkey <fingerprint>`.

## How to Set Up the Development Environment

1. Install Git, GitHub CLI (optional), and `rustup`.
2. Pin the Rust toolchain this repo expects: `rustup toolchain install 1.75.0-x86_64-pc-windows-msvc` then `rustup component add rustfmt --toolchain 1.75.0-x86_64-pc-windows-msvc`. Set it as the directory override from inside the repo: `rustup override set 1.75.0-x86_64-pc-windows-msvc`.
3. Install Visual Studio 2022 Build Tools with the "Desktop development with C++" workload.
4. Install LLVM and add `C:\Program Files\LLVM\bin` to `PATH`.
5. Install Python 3.12, CMake, Ninja, and NASM.
6. Install Flutter 3.24.5 and add its `bin` directory to `PATH`.
7. Install vcpkg and pin it to the commit this repo's `res/vcpkg` overlay expects; set `VCPKG_ROOT` to the vcpkg checkout.
8. Install `flutter_rust_bridge_codegen` **v1.80.1** exactly (`cargo install flutter_rust_bridge_codegen --version 1.80.1 --features "uuid" --locked`).
9. Clone your fork and add the upstream remote read-only:
   ```powershell
   git clone https://github.com/<your-fork>/rustdeskadmin-client.git
   cd rustdeskadmin-client
   git remote add upstream https://github.com/rustdesk/rustdesk.git
   git remote set-url --push upstream DISABLED
   ```
10. Install the static `x64-windows-static` triplet required by the `hwcodec` dependency's `build.rs`:
    ```powershell
    vcpkg install --classic "ffmpeg[amf,core,nvcodec,qsv]:x64-windows-static" `
      --overlay-ports="res\vcpkg" --overlay-triplets="res\vcpkg-triplets"
    ```
    On memory-constrained machines this can OOM-thrash under default parallelism; set `VCPKG_MAX_CONCURRENCY=1` and `CL=/MP1` if it stalls or fails.

## How to Build

### Release build: v2.2.1

Release **v2.2.1** was published as **Latest** on **2026-09-10 UTC**, neither draft nor prerelease, using source/runtime version **2.2.1**, runner resource **2.2.1+0**, MSI **2.2.1.0**, and SFX **2.2.1**. See the [release notes](https://github.com/hrezenmsft/rustdeskadmin-client/releases/tag/v2.2.1) for downloads and SHA-256 checksums. The application was built once from `458b4e96281041b40ef4197f1ae48c4f052386af` (Rust: 51m34s; Flutter: 415.3s). Tag commit `f326ef46b1bcf19941cafc62723ad8b901a3b41a` adds documentation only; runtime/build/package source was verified unchanged from the build commit. Do not merely rename older binaries. Product name: **RustDeskAdmin - RustDesk Fork**, with upstream copyright retained and Henrique Rezende's attribution added; keep `rustdesk.exe` and compatibility-sensitive internal names.

All three packages reuse the frozen 91-file payload. MSI and ZIP hashes match all 91 files; the SFX contains the complete 24,093,932-byte frozen data blob. SFX `CompanyName` is intentionally blank and the MSI upstream contact is unchanged.

All three draft-stage downloads and subsequent public HTTPS downloads matched the local originals and GitHub SHA-256 digests. After verification and backup, all three old v2.2.0 assets were retired; the release page, unchanged tag, and automatic source archives remain, with replacement links in the description. Temporarily paused workflow states were restored without unwanted rebuilds. Validation covered runtime `--version` and package/static/signature/hash checks; no real MSI install or installation smoke test was performed.

Build the client application once (Rust library followed by Flutter runner), then reuse that exact completed payload for MSI, SFX, and portable ZIP packaging. Run this build and the server build **sequentially**. Packaging helpers may be built separately; they do not justify rebuilding the application per format.

- Rust library only: `cargo build --locked --features flutter,hwcodec --lib` (add `--release` for the release profile).
- Full Windows Flutter app:
  ```powershell
  cargo build --release --locked --features flutter,hwcodec --lib
  cd flutter
  flutter build windows --release
  ```
  Output: `flutter/build/windows/x64/runner/Release/rustdesk.exe` and supporting DLLs.
- Static analysis: `flutter analyze` from the `flutter/` directory.
- If you clean `target/` or `flutter/build/`, rebuild the Rust release library **before** `flutter build windows --release`.
- All Windows artifacts are unsigned. If loading fails with `0xc0e90002` (`STATUS_INVALID_IMAGE_HASH`), inspect Windows Code Integrity/security-policy diagnostics and artifact integrity rather than assuming a corrupt build cache. Do not bypass Smart App Control or other execution controls.

## How to Package a Windows Installer

This fork ships three package formats: RustDesk's existing self-extracting "portable" installer packer (`libs/portable`), a plain portable zip, and a native MSI built from the also-upstream `res/msi` WiX v4 project. There is no Inno Setup step.

For this release, use `<version> = 2.2.1` throughout. All three assets are required: `rustdeskadmin-client-2.2.1-install.exe`, `rustdeskadmin-client-2.2.1-portable.zip`, and `rustdeskadmin-client-2.2.1-x64.msi`. Do not include `RustDeskDeploy.exe`. Preserve attribution/release notices in the package payload. Use a fresh MSI packaging staging tree containing the committed fork changes: preprocessing generates entries and must not be rerun over an already-generated tree. Never reset `res/msi` in the source worktree to discard fork branding.

1. Build the Rust release library and the Flutter Windows app as in **How to Build** above.
2. Build the virtual-display helper DLL and copy it into the Release folder:
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
4. Rename the output to match the versioned convention:
   ```powershell
   Copy-Item target\release\rustdesk-portable-packer.exe ".\rustdeskadmin-client-<version>-install.exe"
   ```
5. Produce a portable (no-install) zip package straight from the same Release folder — extract and run `rustdesk.exe` directly, no admin rights or install step required:
   ```powershell
   Compress-Archive -Path "flutter\build\windows\x64\runner\Release\*" -DestinationPath ".\rustdeskadmin-client-<version>-portable.zip" -CompressionLevel Optimal
   ```
6. Build a native MSI with the WiX v4 project under `res\msi` in the fresh packaging staging tree (requires the .NET SDK; `winget install Microsoft.DotNet.SDK.8`):
   ```powershell
   Copy-Item -Recurse flutter\build\windows\x64\runner\Release rustdesk
   cd res\msi
   python preprocess.py --arp -d ..\..\rustdesk -v <version> --revision-version 0
   & 'C:\path\to\nuget.exe' restore msi.sln
   & $env:ComSpec /c 'call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=x64 >nul && msbuild msi.sln -p:Configuration=Release -p:Platform=x64 /p:TargetVersion=Windows10'
   Copy-Item Package\bin\x64\Release\en-us\Package.msi ..\..\rustdeskadmin-client-<version>-x64.msi
   cd ..\..
   Remove-Item -Recurse -Force rustdesk
   ```
   The MSI supports silent/unattended install (`msiexec /i rustdeskadmin-client-<version>-x64.msi /qn`) and Group Policy/SCCM distribution.
7. For future releases, validate package contents, version/product metadata, unsigned status, and installation/portable startup on an appropriate test machine before shipping. After publication as Latest, verify every download before retiring superseded assets; keep old tags/source archives. The completed v2.2.1 verification and retirement milestone is recorded above; installation smoke testing was not part of that validation.

## How to Deploy

### Production release package (recommended — no local build required)

The three published v2.2.1 Windows assets are listed below. Download them and compare SHA-256 checksums with the [release notes](https://github.com/hrezenmsft/rustdeskadmin-client/releases/tag/v2.2.1):
- `rustdeskadmin-client-2.2.1-install.exe` — self-extracting installer (installs to `C:\Program Files\RustDesk`).
- `rustdeskadmin-client-2.2.1-x64.msi` — native MSI installer; suited for silent/unattended install and Group Policy/SCCM distribution.
- `rustdeskadmin-client-2.2.1-portable.zip` — portable, no-install package; extract anywhere and run `rustdesk.exe` directly.

1. **Download a package** from the Releases page:
   ```powershell
   gh release view v2.2.1 --repo hrezenmsft/rustdeskadmin-client
   gh release download v2.2.1 --repo hrezenmsft/rustdeskadmin-client --pattern "*-install.exe" --dir .
   # or, for the MSI:
   gh release download v2.2.1 --repo hrezenmsft/rustdeskadmin-client --pattern "*-x64.msi" --dir .
   # or, for the portable package:
   gh release download v2.2.1 --repo hrezenmsft/rustdeskadmin-client --pattern "*-portable.zip" --dir .
   ```
   or download it manually from `https://github.com/hrezenmsft/rustdeskadmin-client/releases/tag/v2.2.1`.
2. **Run the installer** (`.exe` or `msiexec /i <file>.msi`), or **extract the portable zip** and run `rustdesk.exe` from the extracted folder, on the target Windows machine.
3. **Point the client at your server** in Settings > Network by setting the ID/Relay server address and key to your `rustdeskadmin-server` deployment.
4. **Open Settings > Network > Admin Presence**. The dialog should show the resolved admin API address using the same host as the configured ID Server with fixed port `21114`. Enroll the private key printed by `rustdesk-utils genadminkey <label>`.
5. **Verify** that the admin icon opens the Admin Devices pane, the pane refreshes automatically, and selecting an online device launches the normal connection flow.
6. **Upgrading**: run the newer installer the same way; local client settings such as rename labels remain outside the install directory.
7. **Uninstalling**: `"C:\Program Files\RustDesk\RustDesk.exe" --uninstall`.

### Deploying an unpackaged build (lab/dev only)

- You can deploy by copying the contents of `flutter/build/windows/x64/runner/Release/` (the `.exe` plus all sibling DLLs) to the target machine.
- Before overwriting a running deployment, stop the existing `rustdesk.exe` process on the target machine so the copy is not blocked.
- Point the deployed client at your self-hosted rendezvous/relay server in Settings > Network, then use Settings > Network > Admin Presence only to review the resolved admin API address and enroll the device-specific private key.
- There is no separate build/deploy path for the admin API client logic; it ships inside the same `rustdesk.exe` as the rest of the Flutter app.

## Change Discipline

Update this document when the client/server API contract, UI behavior, authentication model, or test workflow changes. Add every user-visible or compatibility-relevant change to `docs/ADMIN_PRESENCE_CHANGELOG.md` in the same change set.
