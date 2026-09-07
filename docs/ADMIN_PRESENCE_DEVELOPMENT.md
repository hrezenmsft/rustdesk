# Admin Presence Client Development

## Purpose

This fork adds an administrator-only Windows client view for devices currently online with the paired RustDesk rendezvous server. Selecting a listed device must start the existing RustDesk connection flow; it does not bypass target-side approval, password, or permission controls.

## Server Contract

The client consumes a versioned authenticated endpoint: `GET /admin/v1/devices?status=online`. The server owns presence truth, authorization, expiry, and response filtering. The client must never read a shared file or database directly.

## Development Environment

- Development/admin client: `NINA-LAPTOP` (Windows, Hyper-V host)
- Test rendezvous server: `rd-admin-server` (Ubuntu Server 24.04, 1 vCPU / 2 GB RAM), Hyper-V "Default Switch" (NAT), current IP `172.27.17.85` (DHCP; the switch's real subnet is `172.27.16.0/20`, not `/24` — see Networking Notes)
- Test endpoint: `rd-endpoint-01` (Windows 11 Pro, 2 vCPU / 4 GB RAM), same Hyper-V switch, current IP `172.27.26.223`
- Current UI implementation: Flutter under `flutter/`

### Networking Notes (Hyper-V lab)

- Both VMs sit on Hyper-V's built-in **"Default Switch"** (NAT), not the external Wi-Fi-bridged switch — this avoids DHCP address collisions with the host that occurred on the external switch (`externo`, bridged over Wi-Fi).
- The switch's actual NAT subnet is `172.27.16.1/20` (host side), but Hyper-V's internal DHCP was observed handing a `/24` mask to the Windows guest, causing it to route VM-to-VM traffic via the gateway instead of directly. Fixed by correcting the guest's prefix length to `/20` (`Set-NetIPAddress -PrefixLength 20`) to match the real subnet. If VMs stop reaching each other after a reboot/renumbering, check this first.
- DHCP leases on "Default Switch" are not guaranteed stable across host reboots; consider static IPs if this becomes disruptive.

### Toolchain (verified working, NINA-LAPTOP)

- Rust 1.75.0-x86_64-pc-windows-msvc (client-pinned), rustfmt, VS2022 Build Tools (C++ workload), LLVM, Python 3.12, CMake/Ninja/NASM, Flutter 3.24.5, vcpkg pinned @ `9e593bb18ea69cc5095e012465dcd675a822ed0d`.
- `x64-windows-static` vcpkg triplet (required by the `hwcodec` dependency's `build.rs`) built successfully via `vcpkg install --classic "ffmpeg[amf,core,nvcodec,qsv]:x64-windows-static" ...`. On this 4c/8t + 12 GB RAM laptop the default parallelism OOM-thrashed; use `VCPKG_MAX_CONCURRENCY=1` and `CL=/MP1` under VsDevCmd if it needs to be rebuilt.
- `flutter_rust_bridge_codegen` must be **v1.80.1** (`cargo install flutter_rust_bridge_codegen --version 1.80.1 --features "uuid" --locked`), matching `flutter_rust_bridge = "=1.80"` pinned in `Cargo.toml`. Do not use the fork referenced in `build.py`'s Docker snippet — it targets an incompatible `ffigen` range.
- Baseline validation performed on the untouched upstream code (no admin-presence changes yet):
  - `cargo build --locked --features flutter,hwcodec --lib` (debug) — passes.
  - `cargo build --release --locked --features flutter,hwcodec --lib` — passes.
  - `flutter build windows --release` — passes, produces `flutter/build/windows/x64/runner/Release/rustdesk.exe`.
  - This release build, copied to `rd-endpoint-01` and pointed at `rd-admin-server`'s rendezvous service via `RustDesk2.toml`, successfully registered its ID with `hbbs` (`update_pk` logged) — confirms end-to-end reachability of the lab rendezvous path before any admin-presence code is added. Full interactive connect (target consent/password prompt) was not exercised non-interactively by design, since bypassing that prompt is explicitly out of scope; it will be exercised as part of end-to-end validation once the admin device-list view exists.

  ### Implemented Admin Presence Client

  - Added a desktop-only **Admin online devices** pane directly in the existing peer-tab space, ordered beside Recent Sessions.
  - Added an **Admin Presence** entry under Settings > Network for the admin API server address (`host:port`) and admin token, stored in the local Flutter options store for the lab/admin workflow.
  - The pane calls `POST /admin/v1/auth/login`, then `GET /admin/v1/devices?status=online` using the bearer JWT. Selecting a device calls the existing `connect(context, id)` flow, preserving target password, consent, and permission checks.
  - The right-side admin action opens the embedded pane without adding a draggable left-side tab item. The pane auto-refreshes every 5 seconds, shows whether the admin API server is reachable, filters out the local admin client's own RustDesk ID, and keeps previously seen devices as greyed-out offline/stale entries with an offline duration and an `X` delete action.
  - The device list displays a friendly device name above the RustDesk ID when the API or local peer caches provide one; otherwise it falls back to the ID.
  - Deployment validation copied the release build to `rd-endpoint-01` at `C:\RustDeskAdmin` and launched it in the active `lab` desktop session. The admin API listed device `486567681` online, removed it after the registration timeout when RustDesk was stopped, and listed it again after relaunch.
  - If the admin list works but connection fails with "target device is offline or does not exist", check the admin client's normal RustDesk server settings. This was observed on `NINA-LAPTOP` when its admin API setting pointed to `172.27.17.85:21114` but the RustDesk connection flow still used the public server (`rs-ny.rustdesk.com`). Fix by setting `rendezvous_server = '172.27.17.85:21116'`, `custom-rendezvous-server = '172.27.17.85'`, `relay-server = '172.27.17.85'`, and the lab server key in `RustDesk2.toml`.

## Change Discipline

Update this document when the client/server API contract, UI behavior, authentication model, or test workflow changes. Add every user-visible or compatibility-relevant change to `docs/ADMIN_PRESENCE_CHANGELOG.md` in the same change set.
