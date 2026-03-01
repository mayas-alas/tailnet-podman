#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Boot a rootfs directory or registry image in a QEMU graphical window.
# Loads an image, installs it to a virtual disk via bootc, and boots a
# QEMU VM with a GTK display. The disk image is preserved between runs so
# subsequent invocations skip the install step entirely.
#
# Usage: ./test/run-qemu.sh <rootfs-directory-or-registry-ref>
#
# Examples:
#   ./test/run-qemu.sh output/snow              # rootfs directory from mkosi
#   ./test/run-qemu.sh ghcr.io/frostyard/snow:latest  # registry ref
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper libraries
# shellcheck source=test/lib/vm.sh
source "$SCRIPT_DIR/lib/vm.sh"

# Environment variable defaults
: "${DISK_SIZE:=10G}"
: "${VM_MEMORY:=4096}"
: "${VM_CPUS:=2}"
: "${SSH_PORT:=2222}"

# Internal state
WORK_DIR=""

usage() {
    echo "Usage: $0 <rootfs-directory-or-registry-ref>" >&2
    echo "" >&2
    echo "  rootfs-directory  Local rootfs directory from mkosi (e.g. output/snow)" >&2
    echo "  registry-ref      Container registry reference (e.g. ghcr.io/frostyard/snow:latest)" >&2
    echo "" >&2
    echo "Environment variables:" >&2
    echo "  DISK_SIZE    Disk image size (default: 10G)" >&2
    echo "  VM_MEMORY    VM memory in MiB (default: 4096)" >&2
    echo "  VM_CPUS      Number of CPUs (default: 2)" >&2
    echo "  SSH_PORT     Host port forwarded to VM port 22 (default: 2222)" >&2
    exit 1
}

cleanup() {
    echo ""
    echo "=== Cleanup ==="

    # Remove temp directory (OVMF copies, etc.) but NOT the disk image
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
        echo "Removed temp directory: $WORK_DIR"
    fi

    # Intentionally NOT removing the disk image or container image —
    # both are preserved for reuse.
}

# Derive the persistent disk image path from the input argument.
# e.g. "output/snow" -> "<project>/output/snow-disk.raw"
#      "ghcr.io/frostyard/snow:latest" -> "<project>/output/snow-disk.raw"
disk_path_for() {
    local input="$1"
    local name

    if is_registry_ref "$input"; then
        # Extract image name from registry ref: ghcr.io/frostyard/snow:latest -> snow
        name="${input##*/}"
        name="${name%%:*}"
    else
        # Local path: output/snow -> snow
        name="$(basename "$input")"
    fi

    echo "$PROJECT_ROOT/output/${name}-disk.raw"
}

# --- Argument parsing ---
[[ $# -eq 1 ]] || usage
INPUT="$1"

DISK_PATH="$(disk_path_for "$INPUT")"

trap cleanup EXIT

# ---------------------------------------------------------------
# Check for existing disk image
# ---------------------------------------------------------------
if [[ -f "$DISK_PATH" ]]; then
    echo "=== Reusing existing disk image: $DISK_PATH ==="
    echo "    (delete it manually to force a fresh install)"
else
    echo "=== No existing disk image found, performing install ==="

    # Create a working temp directory
    WORK_DIR=$(mktemp -d)
    echo "Temp directory: $WORK_DIR"

    # -----------------------------------------------------------
    # Step 1 - LOAD: Get the image into podman storage
    # -----------------------------------------------------------
    echo ""
    echo "=== Step 1: Load image ==="
    load_image "$INPUT" "localhost/snosi-qemu:latest"

    # -----------------------------------------------------------
    # Step 2 - Create sparse disk image
    # -----------------------------------------------------------
    echo ""
    echo "=== Step 2: Create disk image ==="
    mkdir -p "$(dirname "$DISK_PATH")"
    create_disk "$DISK_PATH"

    # -----------------------------------------------------------
    # Step 3 - Install image to disk
    # -----------------------------------------------------------
    echo ""
    echo "=== Step 3: Install image to disk ==="
    install_to_disk "$DISK_PATH"

    echo "Disk image saved: $DISK_PATH"
fi

# ---------------------------------------------------------------
# Boot VM with graphical display
# ---------------------------------------------------------------
echo ""
echo "=== Booting VM (GTK window) ==="
echo "    Close the QEMU window or press Ctrl-C to stop."
echo "    SSH available at: ssh -p $SSH_PORT root@localhost"
echo ""

# We need OVMF firmware copies in a writable temp location
# (VARS file must be writable for UEFI variable storage)
if [[ -z "$WORK_DIR" ]]; then
    WORK_DIR=$(mktemp -d)
fi

ovmf_pair=$(find_ovmf)
ovmf_code_src="${ovmf_pair%% *}"
ovmf_vars_src="${ovmf_pair##* }"

ovmf_code="$WORK_DIR/OVMF_CODE.fd"
ovmf_vars="$WORK_DIR/OVMF_VARS.fd"
cp "$ovmf_code_src" "$ovmf_code"
cp "$ovmf_vars_src" "$ovmf_vars"

qemu-system-x86_64 \
    -machine q35 \
    -enable-kvm -cpu host \
    -m "$VM_MEMORY" -smp "$VM_CPUS" \
    -drive "if=pflash,format=raw,unit=0,file=$ovmf_code,readonly=on" \
    -drive "if=pflash,format=raw,unit=1,file=$ovmf_vars" \
    -drive "file=$DISK_PATH,format=raw,if=virtio" \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" \
    -device virtio-net-pci,netdev=net0 \
    -display gtk \
    -serial stdio

echo ""
echo "VM stopped. Disk image preserved at: $DISK_PATH"
