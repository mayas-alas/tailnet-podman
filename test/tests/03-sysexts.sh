#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Tier 3: Sysext machinery validation tests for bootc-deployed snosi images.
# This script runs INSIDE the booted VM via SSH and is fully self-contained.
# Validates that systemd-sysext and sysupdate infrastructure is present.
# Sysexts may not be active on a fresh install; this checks the machinery, not content.
# Output format: TAP-like (ok / not ok), exit code = number of failures.
set -euo pipefail

PASS=0
FAIL=0

# check - Run a test and record the result.
# Usage: check "description" command [args...]
check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "ok - $desc"
        (( PASS++ )) || true
    else
        echo "not ok - $desc"
        (( FAIL++ )) || true
    fi
}

echo "# Tier 3: Sysext machinery validation"

check "systemd-sysext binary exists" \
    command -v systemd-sysext

check "systemd-sysext list succeeds" \
    systemd-sysext list

check "sysupdate transfer configs exist" \
    test -d /usr/lib/sysupdate.d

echo ""
echo "# Informational: sysupdate transfer configs"
if [[ -d /usr/lib/sysupdate.d ]]; then
    ls -1 /usr/lib/sysupdate.d/ 2>/dev/null || echo "(empty)"
else
    echo "(directory not found)"
fi

echo ""
echo "# Informational: active extensions"
systemd-sysext list 2>/dev/null || echo "(none or command failed)"

echo ""
echo "# Results: $PASS passed, $FAIL failed, $(( PASS + FAIL )) total"
exit "$FAIL"
