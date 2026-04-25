# Recovering from an Existing BusyBox Drop

If you already rebooted before running the chroot fix and you're staring at an `(initramfs)` prompt right now, you have two paths.

## Path A — Recover from BusyBox directly (sometimes works)

At the `(initramfs)` prompt, see what the kernel found:

```
ls /dev/md*
```

If you see `/dev/md126` and `/dev/md126p2`, the array is assembled and you can manually mount and exit-to-continue:

```
mdadm --assemble --scan
mount /dev/md126p2 /root
exit
```

The `exit` tells initramfs to continue boot using `/root` as the new root. If it pivots and you get a login prompt, you can then run the chroot-equivalent fix from the running system:

```bash
sudo apt install --reinstall mdadm dmraid
sudo update-initramfs -u -k all
sudo update-grub
sudo reboot
```

This is the no-USB recovery path. It works often enough to try, but if `ls /dev/md*` shows nothing, skip to Path B.

## Path B — Recover from a live USB (always works)

This is the same procedure as the post-install chroot fix, just done after a botched first boot instead of as part of the install.

1. Boot the Zorin live USB → "Try Zorin"
2. Open a terminal
3. Run:

```bash
sudo mount /dev/md126p2 /mnt
sudo mount /dev/md126p1 /mnt/boot/efi
for i in dev dev/pts proc sys run; do sudo mount --bind /$i /mnt/$i; done
sudo chroot /mnt
```

Inside the chroot:

```bash
apt install --reinstall mdadm dmraid
update-initramfs -u -k all
update-grub
exit
```

Outside:

```bash
for i in run sys proc dev/pts dev; do sudo umount /mnt/$i; done
sudo umount /mnt/boot/efi
sudo umount /mnt
sudo reboot
```

Pull the USB during POST. Should boot cleanly.

## If it still drops to BusyBox after the chroot fix

This is rare. The fix above resolved it for me. If it doesn't work for you, the next step is to force the IMSM modules into initramfs explicitly. From inside a chroot:

```bash
cat >> /etc/initramfs-tools/modules <<EOF
dm-mod
dm-raid
md-mod
raid0
EOF

update-initramfs -u -k all
```

Reboot and try again.

If even that fails, the issue is likely that the IMSM container metadata on the drives is corrupted or the BIOS is presenting the array oddly. Boot to BIOS, check Intel RST status — both members should be "Member Disk(0)" of a "Volume" with status "Normal". If anything's off (Failed, Missing, Rebuild), the problem is below the OS layer and the install will keep failing until the array is healthy at the firmware level.
