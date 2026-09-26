#!/bin/bash
# Whole-disk installer test.
# The host user is not root, so stage 1 runs inside QEMU (where it is PID 1's
# root) against a blank virtio disk. The Base-OS tree is shared over 9p.
set -euo pipefail

WS=$(cd "$(dirname "$0")/../../.." && pwd)
TD=$WS/okra-linux/testdisk
IMG=$TD/whole-disk.img
INITRD=$TD/install-initrd.img
LOG=$TD/stage1.log
BOOTLOG=$TD/stage2.log
KERNEL=$WS/linux-7.2/arch/x86/boot/bzImage
KSRC=$WS/linux-7.2
SIZE=${SIZE:-16G}

mkdir -p "$TD"
rm -f "$IMG" "$LOG" "$BOOTLOG"
truncate -s "$SIZE" "$IMG"

STAGING=$(mktemp -d)
cleanup_staging() { rm -rf "$STAGING"; }
trap cleanup_staging EXIT

copy_with_libs() {
    local src=$1
    src=$(readlink -f "$src")
    [ -f "$src" ] || return 0
    local dest=$STAGING/bin/$(basename "$src")
    mkdir -p "$STAGING/bin" "$STAGING/lib64"
    cp -a "$src" "$dest"
    chmod 0755 "$dest"
    local lib real soname
    while read -r lib; do
        [ -n "$lib" ] && [ -e "$lib" ] || continue
        real=$(readlink -f "$lib")
        soname=$(basename "$lib")
        cp -a "$real" "$STAGING/lib64/$(basename "$real")"
        if [ "$soname" != "$(basename "$real")" ]; then
            ln -sfn "$(basename "$real")" "$STAGING/lib64/$soname"
        fi
    done < <(ldd "$src" 2>/dev/null | awk '/=> \// { print $3 } /^\t\// { print $1 }')
}

echo "==> building install initramfs"
mkdir -p "$STAGING/bin" "$STAGING/modules" "$STAGING/proc" "$STAGING/sys" "$STAGING/dev" "$STAGING/mnt/ws"
install_bin() {
    local name=$1 src base
    src=$(command -v "$name") || { echo "missing host tool: $name" >&2; exit 1; }
    copy_with_libs "$src"
    base=$(basename "$(readlink -f "$src")")
    [ "$base" = "$name" ] || ln -sfn "$base" "$STAGING/bin/$name"
}
for bin in bash rsync sfdisk blkid mount umount cp mkdir ln sed grep cat sync date sleep insmod id mktemp rm; do
    install_bin "$bin"
done
real=$(readlink -f "$(command -v mkfs.ext4)")
copy_with_libs "$real"
[ "$(basename "$real")" = mkfs.ext4 ] || ln -sfn "$(basename "$real")" "$STAGING/bin/mkfs.ext4"
real=$(readlink -f "$(command -v mkfs.vfat)")
copy_with_libs "$real"
[ "$(basename "$real")" = mkfs.vfat ] || ln -sfn "$(basename "$real")" "$STAGING/bin/mkfs.vfat"
copy_with_libs /usr/bin/install
ln -sfn bash "$STAGING/bin/sh"
for ko in \
    "$KSRC/fs/netfs/netfs.ko" \
    "$KSRC/net/9p/9pnet.ko" \
    "$KSRC/net/9p/9pnet_virtio.ko" \
    "$KSRC/fs/9p/9p.ko" \
    "$KSRC/fs/nls/nls_iso8859-1.ko" \
    "$KSRC/fs/fat/fat.ko" \
    "$KSRC/fs/fat/vfat.ko"
do
    [ -f "$ko" ] || { echo "missing module $ko" >&2; exit 1; }
    cp -a "$ko" "$STAGING/modules/"
done

cat >"$STAGING/init" <<'EOF'
#!/bin/bash
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
echo "install-init: start" >/dev/kmsg
insmod /modules/netfs.ko
insmod /modules/9pnet.ko
insmod /modules/9pnet_virtio.ko
insmod /modules/9p.ko
insmod /modules/nls_iso8859-1.ko
insmod /modules/fat.ko
insmod /modules/vfat.ko
mkdir -p /mnt/ws
mount -t 9p -o trans=virtio,version=9p2000.L,msize=1048576 hostshare /mnt/ws \
    || { echo "install-init: 9p mount failed" >/dev/kmsg; exec /bin/sh; }
echo "install-init: 9p mounted" >/dev/kmsg
i=0
while [ ! -b /dev/vda ] && [ "$i" -lt 50 ]; do
    i=$((i + 1))
    sleep 0.1
done
[ -b /dev/vda ] || { echo "install-init: no /dev/vda" >/dev/kmsg; exec /bin/sh; }
mkdir -p /tmp
export OKRAINSTALL_LIVE_ROOT=/mnt/ws/OKRALINUX
export OKRAINSTALL_KERNEL=/mnt/ws/linux-7.2/arch/x86/boot/bzImage
export OKRAINSTALL_PAYLOAD=/mnt/ws/okra-linux/OKRAINSTALL
/bin/bash /mnt/ws/okra-linux/OKRAINSTALL/libexec/okrainstall-stage1 --whole-disk /dev/vda
rc=$?
echo "STAGE1_RC:$rc" >/dev/kmsg
sync
if command -v poweroff >/dev/null 2>&1; then
    poweroff -f
fi
echo o >/proc/sysrq-trigger
sleep 1
EOF
chmod 0755 "$STAGING/init"
loader=$STAGING/lib64/ld-linux-x86-64.so.2
for check in bash rsync sfdisk mkfs.ext4 mount insmod; do
    if ! "$loader" --library-path "$STAGING/lib64" --list "$STAGING/bin/$check" >/dev/null; then
        echo "initramfs tool failed to load: $check" >&2
        "$loader" --library-path "$STAGING/lib64" --list "$STAGING/bin/$check" >&2 || true
        exit 1
    fi
done
( cd "$STAGING" && find . -print0 | cpio --null -o -H newc | gzip -9 ) >"$INITRD"
rm -rf "$STAGING"
trap - EXIT

echo "==> running stage 1 in QEMU (whole disk)"
accel=()
smp=1
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    accel=(-enable-kvm -cpu host)
    smp=2
    echo "==> KVM"
fi
timeout 3600 qemu-system-x86_64 \
    "${accel[@]}" \
    -machine q35 \
    -m 2G \
    -smp "$smp" \
    -kernel "$KERNEL" \
    -initrd "$INITRD" \
    -append "console=ttyS0,115200n8 loglevel=6" \
    -drive "file=$IMG,format=raw,if=virtio" \
    -fsdev "local,id=fs0,path=$WS,security_model=passthrough,readonly=on" \
    -device virtio-9p-pci,fsdev=fs0,mount_tag=hostshare \
    -serial "file:$LOG" \
    -display none \
    -no-reboot || true

echo "==> stage1 serial tail"
tail -n 40 "$LOG" || true
grep -q 'STAGE1_RC:0' "$LOG" || { echo 'FAIL: stage 1 did not succeed' >&2; exit 1; }

echo "==> reading installed phase marker"
MNT=$(mktemp -d)
start_sector=$(sfdisk -d "$IMG" | sed -n 's/.*start=[[:space:]]*\([0-9][0-9]*\).*type=0FC63DAF.*/\1/p' | head -n 1)
[ -n "$start_sector" ] || { echo "cannot find root partition start" >&2; exit 1; }
OFFSET=$((start_sector * 512))
fuse2fs -o "ro,offset=$OFFSET" "$IMG" "$MNT"
phase=$(tr -d '[:space:]' <"$MNT/var/lib/okrainstall/phase")
echo "phase=$phase"
test "$phase" = 2
test -x "$MNT/usr/bin/okrainstall"
test -f "$MNT/boot/vmlinuz"
test -f "$MNT/boot/grub2/grub.cfg"
test -f "$MNT/boot/grub2/themes/tachibana-sherry/theme.txt"
cp -a "$MNT/boot/vmlinuz" "$TD/vmlinuz"
uuid=$(blkid -s UUID -o value -p -O "$OFFSET" "$IMG" || true)
if [ -z "$uuid" ]; then
    uuid=$(grep '^UUID=' "$MNT/etc/fstab" | awk '{print $1}' | cut -d= -f2)
fi
echo "root uuid=$uuid"
fusermount3 -u "$MNT"
rmdir "$MNT"

echo "==> booting installed disk into stage 2"
timeout 180 qemu-system-x86_64 \
    "${accel[@]}" \
    -machine q35 \
    -m 2G \
    -smp "$smp" \
    -kernel "$TD/vmlinuz" \
    -append "root=UUID=$uuid rw init=/sbin/okra-init console=ttyS0,115200n8 console=tty0 nomodeset systemd.show_status=yes" \
    -drive "file=$IMG,format=raw,if=virtio" \
    -serial "file:$BOOTLOG" \
    -display none \
    -no-reboot || true

echo "==> stage2 serial tail"
tail -n 60 "$BOOTLOG" || true
if grep -q 'OKRAINSTALL stage2' "$BOOTLOG"; then
    echo 'PASS: whole-disk install reached stage 2'
    exit 0
fi
echo 'FAIL: stage 2 marker not seen' >&2
exit 1
