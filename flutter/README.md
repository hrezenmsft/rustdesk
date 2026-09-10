# flutter_hbb

## RustDeskAdmin v2.2.1 release build

Release **v2.2.1** was published as **Latest** on **2026-09-10 UTC**, neither draft nor prerelease, with runtime version **2.2.1** and Windows runner resource **2.2.1+0**. The [release notes](https://github.com/hrezenmsft/rustdeskadmin-client/releases/tag/v2.2.1) provide downloads and SHA-256 checksums. The application was built once from `458b4e96281041b40ef4197f1ae48c4f052386af`; tag commit `f326ef46b1bcf19941cafc62723ad8b901a3b41a` adds documentation only, with runtime/build/package source verified unchanged. The display product is **RustDeskAdmin - RustDesk Fork**; retain upstream copyright and add Henrique Rezende. Keep the internal Flutter project name and `rustdesk.exe` for compatibility.

The frozen 91-file payload is reused by `rustdeskadmin-client-2.2.1-install.exe`, `rustdeskadmin-client-2.2.1-portable.zip`, and `rustdeskadmin-client-2.2.1-x64.msi`. MSI version is **2.2.1.0** and SFX version is **2.2.1**.

All three draft-stage and public HTTPS downloads matched the originals and GitHub SHA-256 digests. The three old v2.2.0 assets were then retired; its page, unchanged tag, and automatic source archives remain, with replacement links. Validation did not include installation smoke tests.

Build the Rust library and Flutter Windows runner once, then reuse the completed Release directory for the three unsigned Windows x64 packages. Run client and server builds sequentially. See [the fork development/build guide](../docs/ADMIN_PRESENCE_DEVELOPMENT.md); the generic Flutter introduction below is upstream scaffolding, not the release procedure.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples and guidance on mobile development, and a full API reference.
