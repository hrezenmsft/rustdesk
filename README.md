## 🛠️ RustDeskAdmin — Custom Admin-Presence Fork

This repository is a **custom fork of the official [rustdesk/rustdesk](https://github.com/rustdesk/rustdesk) client**, part of the `RustDeskAdmin` project (paired with [`rustdeskadmin-server`](https://github.com/hrezenmsft/rustdeskadmin-server)). This README describes only what is different in this fork.

### What this fork adds

- A Windows desktop-only **Admin online devices** pane embedded directly in the existing peer-tab space, opened by a dedicated icon in the **first left-side position** of the tab bar.
- The pane lists devices currently online with your self-hosted RustDesk rendezvous deployment through the paired `rustdeskadmin-server` admin API, showing:
  - A friendly device name above the RustDesk ID, with an inline **rename** action for a client-local label.
  - A live indicator showing whether the admin API is reachable.
  - Online/offline state, with missing devices retained as greyed-out stale entries that show offline duration.
  - An **X** action to remove stale/offline rows you no longer want tracked locally.
  - The same list/tile/grid visualization switch used by the standard peer tabs.
  - An **Auto refresh** toggle (refresh icon + checkbox) next to the online-device count; enabled by default and remembered locally when turned off.
  - A padlock icon next to the online-device count showing the transport actually in use: locked/green for HTTPS, open/orange when it fell back to plain HTTP. The client always tries HTTPS first automatically and only falls back on a transport-level failure — see [server docs](https://github.com/hrezenmsft/rustdeskadmin-server/blob/master/docs/DEPLOYMENT.md#admin-api-transport-security) for fronting the admin API with TLS.
- Selecting an **online** device runs RustDesk's normal, unmodified connection flow for that device ID. Target-side password, consent, and permission checks are never bypassed.
- **As of v2.0.0, authentication is per-device ed25519 key enrollment only.** On the server, run `rustdesk-utils genadminkey <label>` once for each admin client, then paste the printed private key into **Settings > Network > Admin Presence** and click **Enroll key**. The key fingerprint shown in the client matches `rustdesk-utils listadminkeys` for verification.
- **As of v2.0.0, there is no separate admin server address field.** The client reuses the host already configured for the RustDesk **ID Server** (`custom-rendezvous-server`) and always targets the admin API on fixed port `21114`. The Admin Presence dialog shows that resolved address read-only.
- **Compatibility note:** v2.0.0 clients are compatible only with v2.0.0+ `rustdeskadmin-server` deployments.
- This client never talks to a database or log file directly. It calls the versioned authenticated admin API exposed by the paired server fork and then launches the normal RustDesk connection flow.

### Documentation

- **[docs/ADMIN_PRESENCE_DEVELOPMENT.md](docs/ADMIN_PRESENCE_DEVELOPMENT.md)** — full development-environment setup, build, and deployment instructions for this fork (Windows/Flutter toolchain, vcpkg static-FFmpeg workaround, etc.).
- **[docs/ADMIN_PRESENCE_CHANGELOG.md](docs/ADMIN_PRESENCE_CHANGELOG.md)** — dated changelog of every change made in this fork, newest first.
- **[docs/ADMIN_PRESENCE_AI_HANDOFF.md](docs/ADMIN_PRESENCE_AI_HANDOFF.md)** — a public-safe context primer for AI coding agents picking up this fork with no prior history.

### Quick start (see the development doc for full detail)

**Recommended: install from the prebuilt Windows installer — no build required.** Download `rustdeskadmin-client-<version>-install.exe` from the **[Releases page](https://github.com/hrezenmsft/rustdeskadmin-client/releases)**, run it on the target machine, then configure:

1. **Settings > Network > ID/Relay Server** to point at your `rustdeskadmin-server` deployment.
2. **Settings > Network > Admin Presence** to confirm the resolved admin API address (`<your-id-server-host>:21114`) and enroll the private key printed by `rustdesk-utils genadminkey <label>`.

A native MSI installer (`rustdeskadmin-client-<version>-x64.msi`) is also attached to every release, suited for silent/unattended installs (`msiexec /i rustdeskadmin-client-<version>-x64.msi /qn`) and Group Policy/SCCM distribution. A portable, no-install package (`rustdeskadmin-client-<version>-portable.zip`) is attached too — extract it anywhere and run `rustdesk.exe` directly.

See **[docs/ADMIN_PRESENCE_DEVELOPMENT.md § Production release package](docs/ADMIN_PRESENCE_DEVELOPMENT.md#production-release-package-recommended--no-local-build-required)** for the full walkthrough, including upgrading and uninstalling.

Building from source instead:

```powershell
git clone https://github.com/hrezenmsft/rustdeskadmin-client.git
cd rustdeskadmin-client
git remote add upstream https://github.com/rustdesk/rustdesk.git
git remote set-url --push upstream DISABLED
# Follow docs/ADMIN_PRESENCE_DEVELOPMENT.md for full toolchain + vcpkg setup, then:
cargo build --release --locked --features flutter,hwcodec --lib
cd flutter && flutter build windows --release
```

Upstream project: **[rustdesk/rustdesk](https://github.com/rustdesk/rustdesk)** — this fork tracks it read-only via the `upstream` remote (push disabled) and only adds the administrator presence feature described above; it does not otherwise change RustDesk's protocol, security model, or behavior.

---

This project is a fork of [rustdesk/rustdesk](https://github.com/rustdesk/rustdesk), the official RustDesk remote desktop client. See the upstream project for the full RustDesk feature set, licensing, screenshots, and general documentation.
