# Fixing the PAX Header / OCI Layer Problem

## The Root Cause

mkosi uses GNU `tar` with `--xattrs --pax-option=delete=atime,delete=ctime,delete=mtime` to create OCI tar layers. This produces PAX extension headers that composefs-rs's custom Rust tar parser can't handle correctly. composefs-rs has an [open issue (#2)](https://github.com/composefs/composefs-rs/issues/2) acknowledging their "home-brew header handling code" needs PAX cleanup, but no fix is imminent.

## What `podman export | podman import` Actually Loses

The test script workaround sidesteps PAX headers but is **lossy**:

| Metadata | Preserved? |
|----------|-----------|
| SUID/SGID bits | Yes (rootful only) |
| xattrs (all namespaces) | **No** |
| File capabilities (`security.capability`) | **No** |
| SELinux labels | **No** |
| ACLs | **No** |
| Hardlinks | Yes |
| Ownership (uid/gid) | Yes (rootful) |
| OCI labels/annotations | **No** |

This means things like `ping` (needs `cap_net_raw`) break silently in addition to `sudo` (SUID).

## Why PR #83's Containerfile Approach Failed

`buildah copy` (which implements Dockerfile `COPY`) has a **documented, still-open bug** ([buildah #4463](https://github.com/containers/buildah/issues/4463)) — it drops SUID bits during Go tar serialization. This is a separate code path from `buildah commit`. The original bug ([#574](https://github.com/containers/buildah/issues/574)) was "fixed" but the fix is incomplete for certain export paths.

## Options Ranked

### 1. `buildah mount` + `cp -a` + `commit` (Recommended)

Change mkosi output to `Format=directory`, then build the OCI image using buildah's mount workflow which bypasses the buggy `COPY`/`copy` code path entirely:

```bash
container=$(sudo buildah from scratch)
mountpoint=$(sudo buildah mount "$container")
sudo cp -a output/snow/. "$mountpoint/"
sudo buildah umount "$container"
sudo buildah config --label containers.bootc=1 "$container"
sudo buildah commit "$container" "ghcr.io/frostyard/snow:latest"
sudo buildah push "ghcr.io/frostyard/snow:latest"
```

**Why it works:** `cp -a` is a kernel-level copy preserving ALL metadata (SUID, SGID, xattrs, capabilities, ACLs, hardlinks, ownership). Then `buildah commit` creates the OCI tar layer via `containers/storage`'s `pkg/archive`, which reads directly from the overlay filesystem and has explicit `SCHILY.xattr.*` PAX header support and SUID/SGID bit handling. This is a **completely different code path** than `buildah copy`.

- Preserves: Everything
- Works in GH Actions: Yes (`sudo buildah` works, buildah pre-installed on `ubuntu-24.04`)
- Complexity: Low-medium (replace the skopeo push step with ~6 lines of buildah commands)
- Risk: Low — well-tested pattern in the buildah community

### 2. GNU `tar` manual layer + `crane append`

Create the tar layer yourself with GNU tar, then wrap it in OCI metadata:

```bash
sudo tar -C output/snow -cf layer.tar \
  --xattrs --xattrs-include='*' --format=posix \
  --numeric-owner --sort=name .
crane append -f layer.tar --oci-empty-base -t ghcr.io/frostyard/snow:latest
```

**Pros:** Maximum control over tar format. GNU tar's `SCHILY.xattr.*` is the industry standard format.
**Cons:** `crane` copies tar blobs as-is (good), but you need to manage OCI config/labels separately. Also `crane flatten` has a known [invalid tar header bug](https://github.com/google/go-containerregistry/issues/1622). More scripting required.

- Preserves: Everything (if tar runs as root)
- Works in GH Actions: Yes (crane can be installed; tar + sudo available)
- Complexity: Medium-high
- Risk: Medium — more moving parts, OCI config assembly needed

### 3. Fix Upstream (composefs-rs)

File a detailed bug with composefs-rs showing the exact PAX header format GNU tar produces with mkosi's flags. Their custom parser ([issue #2](https://github.com/composefs/composefs-rs/issues/2)) is acknowledged as needing work.

**Pros:** Fixes the root cause for everyone.
**Cons:** Slow timeline, blocked on upstream. No guarantee of priority.

**Recommendation:** File the bug regardless, but don't depend on it. Do option 1 now.

### 4. SUID/SGID Capture + Restore

Keep the Containerfile approach, add a manifest step during mkosi build:

```bash
# In mkosi finalize script:
find / -perm /6000 -type f > /usr/share/suid-sgid-manifest.txt
getcap -r / > /usr/share/capabilities-manifest.txt
```

Then in a post-build step, restore from the manifests.

**Why to avoid this:** It's fundamentally playing whack-a-mole. You'd also need to capture file capabilities (`security.capability` xattrs), any `security.ima` xattrs (integrity measurement), ACLs, and other xattrs from packages. Each new package could introduce new metadata types you're not capturing. Option 1 avoids this entire class of problem.

### 5. `umoci` Unpack/Repack

Use umoci to create an OCI image from the directory output. umoci uses Go's `archive/tar` which handles PAX correctly.

**Cons:** umoci's last release was v0.4.7 in 2021. Development is slow. The Go tar library has had [its own PAX bugs](https://github.com/golang/go/issues/12594). Less battle-tested than buildah for this use case.

## Recommendation

**Go with Option 1** (`buildah mount` + `cp -a` + `commit`). It's the simplest approach that preserves all metadata and works in GitHub Actions. The CI workflow change is minimal — replace the `skopeo copy oci:output/... docker://...` push step with the buildah mount/cp/commit/push sequence.

Also **file a composefs-rs bug** (Option 3) with a minimal reproducer so the root cause gets fixed upstream eventually.
