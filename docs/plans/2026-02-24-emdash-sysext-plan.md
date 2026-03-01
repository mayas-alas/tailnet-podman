# Emdash Sysext Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add emdash as a standalone sysext with verified download, /opt relocation, and sysupdate integration.

**Architecture:** Download the emdash .deb via the project's verified download system (checksums.json), install it in the mkosi chroot, relocate /opt/Emdash to /usr/lib/emdash, and wire up sysupdate .transfer/.feature files so users can enable it independently.

**Tech Stack:** mkosi sysext, bash scripts, systemd-sysupdate

---

### Task 1: Add emdash to checksums.json

**Files:**
- Modify: `shared/download/checksums.json`

**Step 1: Download the .deb and compute SHA256**

```bash
curl -L -o /tmp/emdash.deb https://github.com/generalaction/emdash/releases/download/v0.4.16/emdash-amd64.deb
sha256sum /tmp/emdash.deb
rm /tmp/emdash.deb
```

**Step 2: Add entry to checksums.json**

Add after the last entry (before closing `}`):

```json
"emdash": {
  "url": "https://github.com/generalaction/emdash/releases/download/v0.4.16/emdash-amd64.deb",
  "sha256": "<sha256 from step 1>",
  "version": "0.4.16"
}
```

**Step 3: Commit**

```bash
git add shared/download/checksums.json
git commit -m "feat(emdash): add verified download entry for emdash v0.4.16"
```

---

### Task 2: Create emdash sysext mkosi.conf

**Files:**
- Create: `mkosi.images/emdash/mkosi.conf`

**Step 1: Create the directory and config**

Model after `mkosi.images/tailscale/mkosi.conf` (lines 1-18) and `mkosi.images/1password-cli/mkosi.conf` (lines 1-18). The key difference: no `Packages=` line since emdash is installed via verified download, not APT. Instead, list the runtime dependencies the .deb needs.

```ini
[Config]
Dependencies=base

[Output]
ImageId=emdash
Output=emdash
Overlay=yes
ManifestFormat=json
Format=sysext

[Content]
Bootable=no
BaseTrees=%O/base
PostOutputScripts=%D/shared/sysext/postoutput/sysext-postoutput.sh
Environment=KEYPACKAGE=emdash

Packages=libgtk-3-0
         libnotify4
         libnss3
         libxss1
         libxtst6
         xdg-utils
         libatspi2.0-0
         libuuid1
         libsecret-1-0
```

**Step 2: Commit**

```bash
git add mkosi.images/emdash/mkosi.conf
git commit -m "feat(emdash): add sysext mkosi configuration"
```

---

### Task 3: Create emdash post-install script

**Files:**
- Create: `mkosi.images/emdash/mkosi.postinst.chroot`

**Step 1: Create the post-install script**

Model after `shared/packages/bitwarden/mkosi.postinst.d/bitwarden.chroot` (lines 1-29). Adapting for emdash paths: the deb installs to `/opt/Emdash/` with a main binary `emdash`, chrome-sandbox, and a desktop file at `/usr/share/applications/emdash.desktop` with `Exec=/opt/Emdash/emdash %U`.

```bash
#!/bin/bash
set -euo pipefail

if [[ "${DEBUG_BUILD:-0}" == "1" ]]; then
    set -x
fi
if [[ "${UID}" == "0" ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

source "$SRCDIR/shared/download/verified-download.sh"
mkdir -p debs
verified_download "emdash" "debs/emdash.deb"

dpkg -i debs/emdash.deb
rm -rf debs

${SUDO} mv /opt/Emdash /usr/lib/emdash
${SUDO} rm -rf /opt/Emdash
${SUDO} mkdir -p /usr/bin
${SUDO} ln -sf /usr/lib/emdash/emdash /usr/bin/emdash
${SUDO} chmod 4755 /usr/lib/emdash/chrome-sandbox
${SUDO} sed -i 's|/opt/Emdash/emdash|/usr/bin/emdash|g' /usr/share/applications/emdash.desktop
```

**Step 2: Make it executable**

```bash
chmod +x mkosi.images/emdash/mkosi.postinst.chroot
```

**Step 3: Commit**

```bash
git add mkosi.images/emdash/mkosi.postinst.chroot
git commit -m "feat(emdash): add post-install script with /opt relocation"
```

---

### Task 4: Create sysupdate transfer and feature files

**Files:**
- Create: `mkosi.images/base/mkosi.extra/usr/lib/sysupdate.d/emdash.transfer`
- Create: `mkosi.images/base/mkosi.extra/usr/lib/sysupdate.d/emdash.feature`

**Step 1: Create emdash.transfer**

Model after `mkosi.images/base/mkosi.extra/usr/lib/sysupdate.d/tailscale.transfer` (lines 1-20). Replace `tailscale` with `emdash` everywhere.

```ini
[Transfer]
Features=emdash
Verify=false

[Source]
Type=url-file
Path=https://repository.frostyard.org/ext/emdash/
MatchPattern=emdash_@v_@a.raw.zst \
             emdash_@v_@a.raw.xz \
             emdash_@v_@a.raw.gz \
             emdash_@v_@a.raw

[Target]
Type=regular-file
Path=/var/lib/extensions.d/
MatchPattern=emdash_@v_@a.raw.zst \
             emdash_@v_@a.raw.xz \
             emdash_@v_@a.raw.gz \
             emdash_@v_@a.raw
CurrentSymlink=emdash.raw
```

**Step 2: Create emdash.feature**

Model after `mkosi.images/base/mkosi.extra/usr/lib/sysupdate.d/tailscale.feature` (lines 1-4).

```ini
[Feature]
Description=Emdash coding agent orchestrator
Documentation=https://frostyard.org
Enabled=false
```

**Step 3: Commit**

```bash
git add mkosi.images/base/mkosi.extra/usr/lib/sysupdate.d/emdash.transfer \
        mkosi.images/base/mkosi.extra/usr/lib/sysupdate.d/emdash.feature
git commit -m "feat(emdash): add sysupdate transfer and feature files"
```

---

### Task 5: Add emdash to root mkosi.conf Dependencies

**Files:**
- Modify: `mkosi.conf:3-10`

**Step 1: Add emdash to the Dependencies list**

In `mkosi.conf`, add `emdash` to the `[Config]` Dependencies list. Current list (lines 3-10):

```ini
Dependencies=base
             1password-cli
             debdev
             dev
             docker
             incus
             podman
             tailscale
```

Add `emdash` in alphabetical order (after `docker`):

```ini
Dependencies=base
             1password-cli
             debdev
             dev
             docker
             emdash
             incus
             podman
             tailscale
```

**Step 2: Commit**

```bash
git add mkosi.conf
git commit -m "feat(emdash): add emdash sysext to default build dependencies"
```

---

### Task 6: Verify the build

**Step 1: Run `just sysexts` and confirm emdash builds**

```bash
just sysexts
```

Expected: Build completes with emdash sysext in `output/`. Look for:
- `output/emdash_0.4.16_amd64.raw.zst` (versioned output)
- `output/emdash` symlink pointing to the versioned file
- `output/emdash.0.4.16.manifest.json` (versioned manifest)

**Step 2: If build fails, diagnose and fix**

Common issues:
- Missing dependency packages: add to `Packages=` in mkosi.conf
- KEYPACKAGE version extraction fails: check the manifest for the actual package name (`dpkg -l` inside chroot may show a different name)
- Script permission issues: ensure `chmod +x` on postinst script

**Step 3: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix(emdash): address build issues"
```
