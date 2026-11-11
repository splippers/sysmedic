---
title: Repair and sign off
summary: Unlock only what you will change, fix it, lock again, and hand over a report.
time: 8 min
level: standard
---
## The pattern

Every repair follows the same six steps. The order keeps the customer's data safe.

1. Read the scan.
2. Diagnose.
3. **Unlock** only what you will change.
4. Repair.
5. **Lock** again.
6. Scan again, then write it up.

## 1 and 2: read, then diagnose

```run
sysmedic-scan
```

For hardware, use `sysmedic-hwtest report`. For Windows, use `sysmedic-win …` (menu **7**). Ask the assistant on console 1 if you are unsure. If a disk is failing, copy it first (lesson *A failing disk*).

## 3: unlock one partition

On console 2 (**Alt+F2**):

```cmd
sysmedic-unlock /dev/nvme0n1p3
```

It asks why, then for the device name, and backs up first.

> Why: disks start write-protected. Unlocking one partition on purpose, with a reason, keeps the record clear and the rest of the machine safe. Do not unlock a whole disk when one partition will do.

## 4: repair

For example, a Windows volume that only mounts read-only because it is hibernated:

```cmd
sysmedic-win fix-hibernation /dev/nvme0n1p3
```

Or Windows Update stuck: `sysmedic-win fix-update …`. For Linux boot problems use menu **11**.

## 5: lock again

```cmd
sysmedic-lock
```

> Why: it takes only a second and means nothing can write to the disk by accident afterwards.

## 6a: confirm

```run
sysmedic-scan
```

The findings you fixed should be gone. If not, say so in the notes.

## 6b: notes

```cmd
sysmedic-note --job customer="Acme Ltd" job_ref=J-1042 engineer=Sam complaint="Won't finish updating"
sysmedic-note "Fixed hibernation flag; updates now complete"
```

## 6c: the report

Menu **3** (or `sysmedic-report`) re-scans and writes `report.html` and `report.txt`. Open it on the phone dashboard, or print it to PDF from a browser.

## Shut down cleanly

Menu **0**. The visit is bundled for review. Do not pull the plug: the encrypted vault and the session need a clean shutdown.
