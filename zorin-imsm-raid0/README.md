# Zorin OS on Intel IMSM RAID 0 (NVMe Stripe)

Installation guide and post-install fix for Zorin OS 18 (Ubuntu 24.04 base) on an Intel Rapid Storage Technology (IMSM / firmware RAID) striped array. Written from a working install on an Alienware m18 R2 with two 4 TB WD SN820 NVMe drives in RAID 0 (8.2 TB total).

## TL;DR

The Ubiquity installer can target an IMSM array but doesn't include the right driver hooks in initramfs. Without a post-install chroot fix, the system installs cleanly, GRUB loads, the kernel starts — and then drops to a `(initramfs)` BusyBox prompt because it can't assemble the RAID container in time to mount root.

The fix is to chroot into the fresh install and reinstall `mdadm` + `dmraid`, then rebuild initramfs and GRUB before the first reboot.

## What's in this repo

| File | Purpose |
|------|---------|
| `INSTALL.md` | Step-by-step procedure from live USB to working install |
| `TROUBLESHOOTING.md` | What can go wrong and how to recover |
| `BACKGROUND.md` | Why the default install fails (the technical explanation) |
| `scripts/01-prep-array.sh` | Pre-installer: wipe array, create partitions, format ESP |
| `scripts/02-post-install-chroot.sh` | Post-installer: chroot fix that prevents BusyBox |
| `scripts/03-recover-busybox.md` | Notes for recovering a system that already drops to BusyBox |

## Hardware tested

- Alienware m18 R2
- 2× WD SN820 NVMe 4 TB
- Intel RST set to RAID mode in BIOS
- Single IMSM container, single RAID 0 volume
- UEFI boot (no CSM)

## Software tested

- Zorin OS 18.1 Pro (Ubuntu 24.04 / Noble base)
- Kernel 6.17.0-22-generic
- mdadm 4.3-1ubuntu2.1
- dmraid 1.0.0.rc16-12ubuntu2

## Important caveats

**RAID 0 has no redundancy.** One drive failure destroys the entire array. Keep backups of anything you can't redownload.

**IMSM ≠ pure mdadm.** If you don't specifically need IMSM (e.g. for dual-boot with Windows), switching BIOS to AHCI and creating a pure mdadm stripe is significantly less fragile. See `BACKGROUND.md` for details.

## License

Personal reference notes. Use at your own risk. No warranty.
