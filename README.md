tiny-linux-bootloader
=====================

An x86 single sector Linux bootloader that can load initrd or initramfs. This bootloader expects to find the kernel immediately after it at sector 1, followed immediately by the initrd. Any partitions must start after this.

## Features/Purpose

* No partition table needed
* Easy to convert to an obfuscated loader (think anti-forensics for crypted disks)
* Easy to modify for a custom experience
* Useful in embedded devices

## Building

To build:

1. Edit build.sh and set paths to your kernel + initrd, if necessary.
2. Edit config.inc to set your kernel cmdline.
3. Run ./build.sh.
4. Now you can `dd` this onto your disk. If you want to partition the disk image, do not overwrite bytes 446-510 on the first sector.

Your system should now boot with the given kernel and initrd.

# Troubleshooting

You can use qemu to boot the image by running:

    qemu-system-x86 disk

and you can also connect the VM to gdb for actual debugging. There is an included gdb script to get you started.
