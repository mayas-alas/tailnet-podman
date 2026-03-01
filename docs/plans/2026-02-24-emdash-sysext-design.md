# Emdash Sysext Design

## Overview

Add emdash (coding agent orchestrator) as a standalone sysext, following the established Bitwarden pattern for Electron apps distributed as GitHub release `.deb` files.

Emdash is a cross-platform Electron desktop app from https://github.com/generalaction/emdash that orchestrates multiple coding agents in parallel.

## Components

### 1. Sysext Configuration — `mkosi.images/emdash/mkosi.conf`

Standard sysext config:
- `Dependencies=base`, `Format=sysext`, `Overlay=yes`
- `Environment=KEYPACKAGE=emdash` for postoutput version extraction
- `Packages=` includes the deb's runtime dependencies: `libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 xdg-utils libatspi2.0-0 libuuid1 libsecret-1-0`
- `PostOutputScripts` points to `shared/sysext/postoutput/sysext-postoutput.sh`

### 2. Post-install Script — `mkosi.images/emdash/mkosi.postinst.chroot`

Follows the Bitwarden relocation pattern:
1. Download via `verified_download "emdash"` from checksums.json
2. `dpkg -i` the .deb
3. Relocate `/opt/Emdash` to `/usr/lib/emdash`
4. Create symlink `/usr/bin/emdash` -> `/usr/lib/emdash/emdash`
5. Set SUID on chrome-sandbox: `chmod 4755 /usr/lib/emdash/chrome-sandbox`
6. Fix `.desktop` file `Exec=` path from `/opt/Emdash` to `/usr/bin`

### 3. Finalize Script — `mkosi.images/emdash/mkosi.finalize`

Check whether the deb installs anything to `/etc/`. If so, capture to `/usr/share/factory/etc/` for tmpfiles restoration. If not (likely — emdash stores config in `~/.config/emdash/`), this script may be unnecessary.

### 4. Verified Download Entry — `shared/download/checksums.json`

Pin to v0.4.16:
```json
"emdash": {
  "url": "https://github.com/generalaction/emdash/releases/download/v0.4.16/emdash-amd64.deb",
  "sha256": "<computed at implementation time>",
  "version": "0.4.16"
}
```

### 5. Sysupdate Files — `mkosi.images/base/mkosi.extra/usr/lib/sysupdate.d/`

**`emdash.transfer`**: Download from Frostyard repo with standard version/arch match patterns and zst/xz/gz/raw compression fallbacks. Target: `/var/lib/extensions.d/`, symlink: `emdash.raw`.

**`emdash.feature`**: Description="Emdash coding agent orchestrator", Enabled=false.

### 6. Root Config — `mkosi.conf`

Add `emdash` to the Dependencies list so it builds with `just sysexts`.

## Design Decisions

- **Verified download over APT repo**: Emdash has no APT repo; GitHub releases only. The verified download pattern (checksums.json + verified-download.sh) pins the exact version with SHA256 verification.
- **Standalone sysext over shared package**: User-optional via sysupdate, not baked into every desktop image.
- **Relocation to `/usr/lib/emdash`**: Required by immutable filesystem constraints — `/opt` is shadowed by sysext overlays. Follows Bitwarden naming convention (lowercase).
