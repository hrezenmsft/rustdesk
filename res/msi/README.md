# RustDesk msi project

## RustDeskAdmin patch packaging

**v2.2.1 is PREPARING, not published**; GitHub Latest remains v2.2.0. Produce `rustdeskadmin-client-2.2.1-x64.msi` from the same already-built Windows x64 application payload used for the SFX installer and portable ZIP. Set source/MSI versions to `2.2.1`, matching tag `v2.2.1`; use product name **RustDeskAdmin - RustDesk Fork**, retain upstream copyright, and add Henrique Rezende's attribution.

Keep `rustdesk.exe` and internal compatibility names. The MSI and its payload are unsigned; product/manufacturer metadata is not a trusted signer. Do not bypass Smart App Control. Do not package a `RustDeskDeploy.exe` wrapper.

Run preprocessing once in a fresh packaging staging tree containing the approved fork changes, not over an already-generated tree. Do not reset the source `res/msi` tree and discard pending branding edits. See [the fork packaging guide](../../docs/ADMIN_PRESENCE_DEVELOPMENT.md#how-to-package-a-windows-installer) for the complete sequence.

Use Visual Studio 2022 to compile this project.

This project is mainly derived from <https://github.com/MediaPortal/MediaPortal-2.git> .

## Steps

1. `python preprocess.py`, see `python preprocess.py -h` for help.
2. Build the .sln solution.

Run `msiexec /i package.msi /l*v install.log` to record the log.

## Usage

1. Put the custom dialog bitmaps in "Resources" directory. The supported bitmaps are `['WixUIBannerBmp', 'WixUIDialogBmp', 'WixUIExclamationIco', 'WixUIInfoIco', 'WixUINewIco', 'WixUIUpIco']`.

## Knowledge

### properties

[wix-toolset-set-custom-action-run-only-on-uninstall](https://www.advancedinstaller.com/versus/wix-toolset/wix-toolset-set-custom-action-run-only-on-uninstall.html)

| Property Name | Install | Uninstall | Change | Repair | Upgrade |
| ------ | ------ | ------ | ------ | ------ | ------ |
| Installed | False | True | True | True | True |
| REINSTALL | False | False | False | True | False |
| UPGRADINGPRODUCTCODE | False | False | False | False | True |
| REMOVE | False | True | False | False | True |

## TODOs

1. Start menu. Uninstall
1. custom options
1. Custom client.
    1. firewall and tcp allow. Outgoing
    1. Show license ?
    1. Do create service. Outgoing.

## Refs

1. [windows-installer-portal](https://learn.microsoft.com/en-us/windows/win32/Msi/windows-installer-portal)
1. [wxs](https://wixtoolset.org/docs/schema/wxs/)
1. [wxs github](https://github.com/wixtoolset/wix)
