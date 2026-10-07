#!/bin/bash
# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Creates or resizes the swap file /var/swapfile and turns it on at every boot.
# Usage: configure-swap <size in MiB>
set -euo pipefail
SWAP_FILE=/var/swapfile
SIZE_MB=$1

current_mb=0
if [ -f "$SWAP_FILE" ]; then
  current_mb=$(( $(stat --format=%s "$SWAP_FILE") / 1048576 ))
fi
if [ "$current_mb" -ne "$SIZE_MB" ]; then
  echo "Creating a $SIZE_MB MiB swap file at $SWAP_FILE"
  swapoff "$SWAP_FILE" 2>/dev/null || true
  rm -f "$SWAP_FILE"
  dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SIZE_MB" status=none
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE"
fi
grep -q "^$SWAP_FILE " /etc/fstab || echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
swapon --show=NAME --noheadings | grep -qx "$SWAP_FILE" || swapon "$SWAP_FILE"
