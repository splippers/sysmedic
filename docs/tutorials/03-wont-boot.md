---
title: A PC that will not boot
summary: Get SysMedic running on a stubborn machine, then find out why the machine's own system will not start.
time: 8 min
level: beginner
---
## Two different problems

1. **SysMedic itself will not start** on the machine (no boot-menu entry, black screen, error about Secure Boot).
2. **SysMedic starts**, but the customer's own system will not. This is the usual job.

This lesson takes them in that order.

## SysMedic is not in the boot menu

Try the boot-menu key again (F12, F9, Esc, F8 or Option, depending on make). If the drive is still missing:

- Check it is in a **USB 3 port** and the machine was fully off, not hibernating.
- **Dell XPS** (and some other Dells) do not list the drive by themselves. In BIOS setup go to **Boot Configuration → Add Boot Option**, name it "SysMedic", and pick `\EFI\BOOT\BOOTX64.EFI` on the drive's EFI partition. You only need to do this once per machine.

> Why: the firmware only lists drives it trusts. Adding the entry by hand does not change Secure Boot, so BitLocker is left alone.

## Secure Boot blocks it

On newer business laptops, only Windows is trusted. In BIOS setup, enable **"Microsoft UEFI CA"** (on Lenovo: "Allow Microsoft 3rd Party UEFI CA"), or turn Secure Boot off for the visit.

> Why: with BitLocker on the machine, have the recovery key ready, and turn Secure Boot **back on before Windows starts**. Otherwise Windows will ask for the key.

## Black or garbled screen

At the SysMedic boot menu choose **safe graphics**. It starts with simple video drivers.

## It hangs while starting

Choose **verbose boot** to see the kernel messages and note where it stops. On the caddy, *Advanced options* also has an older kernel for machines that misbehave on the newest one.

## SysMedic is running. Why will the customer's system not start?

Read the scan first. Then ask the assistant on console 1, for example "why won't this boot?". It reads the disks without writing to them.

```run
sysmedic-scan
```

## Common causes

| Finding | Usually | Go to |
|---|---|---|
| Disk failing or missing | Dying drive or loose cable | Lesson *A failing disk* |
| Windows volume read-only | Hibernated or half-updated | Lesson *Repair and sign off* |
| BitLocker volume | Locked, cannot be read without the key | Lesson *BitLocker* |
| Linux bootloader / initramfs / fstab | Needs a Linux boot repair | Menu **11** (unlock the partition first) |

## Linux boot repair

Menu **11** offers GRUB, initramfs, fstab and an over-full /boot. These **write** to the customer's disk. Unlock only the partition you are going to change, on console 2 (see *Repair and sign off*).

```cmd
sysmedic-unlock /dev/sdXN
```

Replace `/dev/sdXN` with the partition from the scan. Then choose the repair in menu 11.
