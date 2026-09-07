# Admin Presence Change Log

All notable changes to this custom administrator-presence feature are recorded here.

## Unreleased

### Added

- Implemented the Windows Flutter admin-presence UI: desktop icon beside Recent Sessions, in-memory token/JWT login, online-device list, refresh/logout, and standard click-to-connect behavior.
- Deployed the release build to `rd-endpoint-01` (`C:\RustDeskAdmin`) and validated online/offline/online presence behavior against the lab admin API.
- Initial development environment and integration contract documentation for the administrator-only online-device view.
- Completed Windows dev toolchain setup on `NINA-LAPTOP`: Rust 1.75.0 (pinned), rustfmt, VS2022 Build Tools/C++, LLVM, Python 3.12, CMake/Ninja/NASM, Flutter 3.24.5, vcpkg @ `9e593bb18ea69cc5095e012465dcd675a822ed0d`.
- Diagnosed and completed the static (`x64-windows-static`) vcpkg FFmpeg build required by the upstream `hwcodec` dependency; root cause was RAM exhaustion from default build parallelism on this laptop, fixed with `VCPKG_MAX_CONCURRENCY=1` / `CL=/MP1`.
- Installed the correct `flutter_rust_bridge_codegen` v1.80.1 and regenerated the gitignored FFI bridge sources; verified the untouched upstream baseline builds cleanly (`cargo build` debug and release, `flutter build windows --release`).
- Stood up both Hyper-V lab VMs on the "Default Switch" (avoiding a DHCP conflict seen on the external Wi-Fi-bridged switch) and corrected a `/24`-vs-`/20` subnet-mask mismatch that blocked VM-to-VM traffic.
- Validated, using the untouched upstream baseline client build, that a Windows endpoint (`rd-endpoint-01`) registers its ID with the lab rendezvous server (`rd-admin-server`) — confirming the environment is ready for admin-presence feature development.

### Changed

- Added the persisted non-secret admin server address option (`admin-presence-server`); credentials are not persisted.
- Updated documented lab IPs to reflect actual Hyper-V "Default Switch" addressing (`rd-admin-server` 172.27.17.85, `rd-endpoint-01` 172.27.26.223) instead of the originally planned external-switch static addresses.
