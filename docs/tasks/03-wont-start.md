---
title: A PC that will not start
summary: Work out why Windows will not boot, without changing anything.
when: "It shows a black screen, a logo that never ends, or a repair loop."
risk: read-only
time: 10 min
---
## Scan first

```run
sysmedic-scan
```

Read the ✖ and ▲ lines. A failing disk, a full disk or a BitLocker lock explains most boots that stop.

> Why: a repair on a dying disk can make the loss worse. The scan tells you whether it is safe to repair at all.

## Is the disk healthy?

If the scan shows the disk as failing, stop here. Copy the customer's files off first (menu **10**), and tell the customer before you do anything else.

## Is it locked?

A line that says **BitLocker** means Windows is encrypted and SysMedic cannot read it until you unlock it with the customer's recovery key. Menu **7** has the BitLocker steps.

## Look at why Windows stopped

Menu **7**, then crashes, shows what Windows recorded before it stopped. A recent update, a driver or a full disk usually shows up here.

## Choose the fix

Only now decide the repair: the Windows tools in menu **7**, or the AI assistant (menu **5**) for something unusual. Repairs need the disk unlocked for writing first (menu **8**), and SysMedic backs up before it changes anything.

> Why: SysMedic keeps customer disks read-only until you unlock one on purpose, so a mistake while looking cannot do damage.
