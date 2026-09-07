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

  - Added a desktop-only administrator icon immediately beside the existing Recent Sessions tab bar.
  - Added a login/device-list dialog that persists only the non-secret server address (`host:port`) in the local Flutter options store. The shared admin token and issued JWT remain in memory only.
  - The dialog calls `POST /admin/v1/auth/login`, then `GET /admin/v1/devices?status=online` using the bearer JWT. Selecting a device calls the existing `connect(context, id)` flow, preserving target password, consent, and permission checks.

## Change Discipline

Update this document when the client/server API contract, UI behavior, authentication model, or test workflow changes. Add every user-visible or compatibility-relevant change to `docs/ADMIN_PRESENCE_CHANGELOG.md` in the same change set.
