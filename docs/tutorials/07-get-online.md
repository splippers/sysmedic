---
title: Get online and use your phone
summary: Wi-Fi, tethering, the private hotspot and the phone dashboard.
time: 5 min
level: beginner
---
## Check where you are

```run
sysmedic-connect --status
```

It prints one line: how SysMedic is connected right now, or that it is offline.

## Wired first

Plug in Ethernet. It connects by itself. Nothing else to do.

## Wi-Fi

The first screen at boot offers it. Later, menu **13** (or `wifi`) opens the picker: arrow keys to choose, Enter, type the password, Esc to leave.

> Why: networks and passwords are forgotten at shutdown, unless you answer **y** to "Remember Wi-Fi on this drive?". Then it is stored encrypted in the vault.

## No Wi-Fi adapter shows

The scan says why (usually a missing driver or firmware). Use Ethernet, or turn on **USB tethering** on your phone.

## The private hotspot

Menu **H** makes a Wi-Fi network of its own from this computer, always at `10.42.0.1`. Your phone or laptop joins that, so it never has to join the customer's network.

> Why: you do not need the customer's Wi-Fi password, and your devices never touch their network.

## The phone dashboard

Scan the QR code on console 2 (or run `sysmedic-dash`). The phone must be on the same network: the same Wi-Fi, USB tethering or the hotspot. It shows live findings, which disks are locked, the job form, notes and the report. It can run tests, but it cannot repair or unlock anything.

> Why: anyone with the link can see the visit, so do not share it. A laptop that cannot scan the QR code can use a remote access code instead: menu **K**.

## Offline is fine

Without internet you lose the cloud AI and signature updates. The scan, the tests, the offline AI and the report all still work.
