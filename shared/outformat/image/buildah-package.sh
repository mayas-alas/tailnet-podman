#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Package a rootfs directory into an OCI container image using buildah.
#
# Uses buildah mount + cp -a + commit to preserve ALL file metadata:
# SUID/SGID bits, xattrs, file capabilities, ACLs, hardlinks, ownership.
# This bypasses buildah copy/COPY which has a known SUID-dropping bug.
#
# Usage: buildah-package.sh <rootfs-dir> <image-ref> [label=value ...]
#
# Examples:
#   buildah-package.sh output/snow localhost/snow:latest
#   buildah-package.sh output/snow ghcr.io/frostyard/snow:v1 \
#       org.opencontainers.image.version=v1 \
#       org.opencontainers.image.description="Snow Linux OS Image"
set -euo pipefail

ROOTFS_DIR="$1"
IMAGE_REF="$2"
shift 2

[[ -d "$ROOTFS_DIR" ]] || { echo "Error: rootfs directory does not exist: $ROOTFS_DIR" >&2; exit 1; }

echo "=== Packaging rootfs into OCI image ==="
echo "  rootfs: $ROOTFS_DIR"
echo "  image:  $IMAGE_REF"

# Create empty container
container=$(buildah from scratch)

# Mount and copy rootfs preserving all metadata
mountpoint=$(buildah mount "$container")
cp -a "$ROOTFS_DIR"/. "$mountpoint"/
buildah umount "$container"

# Apply standard bootc labels
buildah config \
    --label "containers.bootc=1" \
    --label "org.opencontainers.image.vendor=frostyard" \
    "$container"

# Apply additional labels passed as arguments
for label in "$@"; do
    buildah config --label "$label" "$container"
done

# Commit to image
buildah commit "$container" "$IMAGE_REF"
buildah rm "$container"

echo "=== Image packaged: $IMAGE_REF ==="
