# OkraLinux

OkraLinux is the distribution build project for the OkraLinux LiveCD.
It assembles the Linux kernel, initramfs, root filesystem, SquashFS image,
and Limine BIOS/UEFI ISO.

## Repository layout

```text
live-build/
├── initramfs/       initramfs staging tree
├── iso-root/        ISO staging tree and Limine configuration
└── scripts/         reproducible build and test stages
```

The kernel source and the working root filesystem are external inputs by
default:

```text
../linux-7.2/
../rootfs/
../limine/bin/limine
```

Override these locations with `KERNEL_TREE`, `ROOTFS`, `LIMINE_BIN`, and
`PROJECT_ROOT` when building elsewhere.

## Build the LiveCD

From this repository:

```bash
SKIP_QEMU=1 live-build/scripts/build-livecd
```

The pipeline runs these stages in order:

```text
build-kernel
build-rootfs
build-initramfs
build-squashfs
build-iso
```

The ISO is written to `okra-linux-livecd.iso`. To build and immediately boot
it in QEMU:

```bash
live-build/scripts/build-livecd
```

To run individual stages:

```bash
live-build/scripts/build-kernel
live-build/scripts/build-rootfs
live-build/scripts/build-initramfs
live-build/scripts/build-squashfs
live-build/scripts/build-iso
live-build/scripts/test-qemu
```

Useful overrides:

```bash
JOBS=4 SKIP_QEMU=1 live-build/scripts/build-livecd
QEMU_MEMORY=4G QEMU_SMP=4 live-build/scripts/test-qemu
```

The generated LiveCD uses SquashFS with an OverlayFS upper layer and boots
systemd as PID 1. The Limine command line includes VGA output and VMware-safe
settings:

```text
console=tty0 nomodeset audit=0 systemd.show_status=false rd.live.image
```

## GitHub Actions Fedora build

GitHub Actions builds the LiveCD inside a Fedora container using
`.github/workflows/build-livecd-fedora.yml`. It creates a Fedora-based rootfs,
produces the BIOS/UEFI ISO, validates the ISO, and uploads it as a workflow
artifact.

Run it automatically by pushing to `main` or opening a pull request. It can
also be started manually from the Actions tab with `workflow_dispatch`.

The local equivalent is:

```bash
FEDORA_ROOTFS=1 FEDORA_RELEASE=41 SKIP_QEMU=1 \
  live-build/scripts/build-livecd
```

The workflow intentionally skips QEMU because GitHub-hosted container jobs do
not provide reliable nested virtualization. QEMU boot testing should run on a
self-hosted runner or locally after downloading the artifact.

## Development rules

Keep generated ISO files, SquashFS images, initramfs archives, kernel images,
and QEMU logs out of Git. Changes to the build pipeline should be tested with
`bash -n` and a complete `SKIP_QEMU=1` build before submission.
