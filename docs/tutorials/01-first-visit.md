---
title: Your first visit
summary: From plugging SysMedic in to the first scan, in the order things happen.
time: 10 min
level: beginner
---
## Before you plug in

Power the customer's machine **off** first. Then plug SysMedic in. A caddy goes in a **USB 3 port** (often blue, or marked SS) with a USB 3 cable.

> Why: on a USB 2.0 port everything runs about ten times slower, and the scan will warn you.

Never unplug or move SysMedic while it is running. On the caddy the whole system runs from that drive.

## Boot from it

Switch the machine on and press its boot-menu key straight away: usually **F12** (Dell, Lenovo), **F9** (HP), **Esc** or **F8** (ASUS), or hold **Option** on a Mac. Pick the SysMedic drive and choose **SysMedic Rescue**.

> Why: the other entries are for trouble. *Safe graphics* is for a black or garbled screen, *verbose boot* shows kernel messages if it hangs.

## Unlock the vault

The first screen asks for the drive's passphrase (nothing shows as you type). Pressing Enter instead skips it: SysMedic still works, but this visit lives in memory and is lost at shutdown.

> Why: the vault keeps the visit, notes and transcripts encrypted on the drive, so customer details are not readable if the drive is lost. The first time, it offers to set itself up: choose a passphrase and **write the recovery key down**.

## Get online

Wired networks connect by themselves. Otherwise you get a list of Wi-Fi networks: press **Enter** to pick one and type its password, or **s** to carry on without internet. Nothing happens for 60 seconds and it carries on offline.

> Why: internet is only needed for the cloud AI and for updating the malware signatures. Everything else, including the scan, works offline.

When it asks whether to remember the network on this drive, answer **n** for a customer's network you will not be back on.

## The scan

SysMedic now scans the machine. It is **read-only** and takes under a minute. Findings come out ordered from most to least serious, each with a next step. Lesson 2, *Reading the scan*, goes through them.

```run
sysmedic-scan
```

## Consent for the cloud AI

If there is internet, you are asked whether the customer consents to the cloud AI. Only **y** turns it on. Anything else, or no answer in 60 seconds, keeps it offline.

> Why: the cloud AI sends questions out of the machine. The customer decides, not you, and the default is no.

## Two consoles

- **Alt+F1** is the assistant. Ask it things like "why won't this boot?" and read the answers.
- **Alt+F2** is you. Unlocking, BitLocker, repairs and notes happen here.

Both are recorded for the review afterwards (what was shown, never your keystrokes). Press **Enter** on console 1 to start the assistant, or **m** for the rescue menu.

## Done

That is the whole start-up. Next: *Reading the scan*.
