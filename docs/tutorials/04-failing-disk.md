---
title: A failing disk
summary: Copy what you can before anything else touches the drive.
time: 8 min
level: standard
---
## The rule

When a disk is failing, every extra read stresses it and every write can destroy data. Do the least possible and **copy it first**. You then work on the copy, not the customer's drive.

> Why: SysMedic keeps customer disks write-protected, which already keeps you safe. Copying first protects against the drive simply dying while you diagnose.

## Check how bad it is

Read-only health summary: temperatures, battery, SMART, hardware errors.

```run
sysmedic-hwtest report
```

Look at the SMART section for reallocated or pending sectors and read errors. A few reallocated sectors that are not growing is a warning, not a crisis. Many, or growing between two runs: copy now.

## See the disks

```run
lsblk
```

Find the failing disk (by size and model). It is the **source**. You need a second, healthy disk with enough space as the **destination**: a USB drive with at least as much free space.

## Make the copy

Use ddrescue. It copies the good parts first, then goes back for the bad ones, and can be stopped and resumed.

```cmd
ddrescue /dev/SOURCE /path/on/external/disk.img /path/on/external/disk.map
```

Replace `SOURCE` with the failing disk and the paths with the destination. Triple-check which is which: swapping them writes the empty disk over the customer's data.

> Why: the `.map` file records progress, so if the drive disconnects you run the same command again and it carries on.

## Never run these on the failing disk

A filesystem check, a repair, a defragment or "fix the boot". They all write to the drive. Wait until you have the image, then work on the image or on a new disk.

## Tell the customer

Add a note so it is in the report:

```cmd
sysmedic-note "Disk failing: imaged to external drive before any repair"
```
