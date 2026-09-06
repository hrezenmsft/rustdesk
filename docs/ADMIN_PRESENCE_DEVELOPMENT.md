# Admin Presence Client Development

## Purpose

This fork adds an administrator-only Windows client view for devices currently online with the paired RustDesk rendezvous server. Selecting a listed device must start the existing RustDesk connection flow; it does not bypass target-side approval, password, or permission controls.

## Server Contract

The client consumes a versioned authenticated endpoint: `GET /admin/v1/devices?status=online`. The server owns presence truth, authorization, expiry, and response filtering. The client must never read a shared file or database directly.

## Development Environment

- Development/admin client: `NINA-LAPTOP`
- Test rendezvous server: `rd-admin-server` at `192.168.0.119`
- Test endpoint: `rd-endpoint-01` at `192.168.0.120`
- Current UI implementation: Flutter under `flutter/`

## Change Discipline

Update this document when the client/server API contract, UI behavior, authentication model, or test workflow changes. Add every user-visible or compatibility-relevant change to `docs/ADMIN_PRESENCE_CHANGELOG.md` in the same change set.
