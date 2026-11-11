---
title: BitLocker
summary: Open an encrypted Windows disk read-only with the customer's recovery key.
time: 6 min
level: standard
---
## What you need

BitLocker disks cannot be read without the **48-digit recovery key** (eight groups of six digits; dashes and spaces are optional). The owner can find it at **aka.ms/myrecoverykey** or from their IT admin.

> Why: that is the point of BitLocker. Without the key you can still check the hardware and the scan, but not the files.

## Find the volume

On console 2 (**Alt+F2**) the banner lists every BitLocker volume on the machine with the exact command to type. Or look at the scan:

```run
sysmedic-scan
```

## Unlock it, read-only

```cmd
sysmedic-win bitlocker /dev/nvme0n1p3
```

Use the device from your banner. It then asks for the key at a hidden prompt. The key is never shown, stored, logged or recorded.

> Why: the volume opens **read-only**, so you cannot damage it by looking.

## From a phone

The phone dashboard has a **BitLocker** card: tap **Unlock from this phone** and type the key on the secure page it opens.

## The key is with someone else

Run `sysmedic-win bitlocker-web` (menu **7** then **w**). The customer or their IT admin scans the QR code on the screen with a phone or laptop on the same network and types the key there. It is HTTPS with a secret link and unlocks read-only. It stops by itself after unlocking, after five wrong keys, or after 15 minutes.

> Why: you never see or touch the key.

## If you need to repair

Opening a volume is read-only. To change anything, unlock the partition first (see *Repair and sign off*) and add `--rw` when you run the unlock. Be sure the customer has agreed.

## Remember

Turn Secure Boot back on before Windows starts, if you turned it off to boot SysMedic. Otherwise Windows will ask the customer for the recovery key.
