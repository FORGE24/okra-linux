#!/bin/bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
KERNEL_TREE="${KERNEL_TREE:-$PROJECT_ROOT/../linux-7.2}"
ROOTFS="${ROOTFS:-$PROJECT_ROOT/../rootfs}"
LIVE_BUILD="${LIVE_BUILD:-$PROJECT_ROOT/live-build}"
ISO_ROOT="$LIVE_BUILD/iso-root"
INITRAMFS_TREE="$LIVE_BUILD/initramfs"
KERNEL_IMAGE="$KERNEL_TREE/arch/x86/boot/bzImage"
ISO_IMAGE="${ISO_IMAGE:-$PROJECT_ROOT/okra-linux-livecd.iso}"
LIMINE_BIN="${LIMINE_BIN:-$PROJECT_ROOT/../limine/bin/limine}"
JOBS="${JOBS:-$(nproc)}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

require_rootfs() {
    [ -d "$ROOTFS" ] || die "rootfs does not exist: $ROOTFS"
    [ -x "$ROOTFS/usr/lib/systemd/systemd" ] || die "systemd missing from rootfs"
}

require_initramfs() {
    [ -x "$INITRAMFS_TREE/init" ] || die "initramfs init missing or not executable"
    [ -x "$INITRAMFS_TREE/bin/switch_root" ] || die "initramfs switch_root missing or not executable"
}
