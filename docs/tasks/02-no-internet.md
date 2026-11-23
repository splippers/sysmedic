---
title: No internet or Wi-Fi problems
summary: Find out whether the fault is the PC, the router or the connection.
when: "The PC says it is connected, but nothing loads. Or it will not connect at all."
risk: read-only
time: 5 min
---
## See what SysMedic itself has

```run
sysmedic-connect --status
```

One line: how this drive is connected right now, or that it is offline.

> Why: SysMedic boots from your drive, so this tests the customer's network without the customer's Windows getting in the way.

## Try a cable first

Plug in Ethernet if you can. It connects by itself. If the cable works and the Wi-Fi does not, the problem is the PC's Wi-Fi or the Wi-Fi password, not the broadband.

## Try Wi-Fi

Menu **13** (or `wifi`) shows the networks. Pick one, type the password. If no adapter shows up at all, the scan will say why: usually a missing driver, or the adapter switched off with a key or switch on the laptop.

## Read the verdict

If SysMedic is online and the customer's Windows was not, the fault is inside Windows (a driver, a setting or a profile). If SysMedic cannot get online either, the fault is the router, the line or the password.

> Why: this one comparison saves most of the guessing.

## Tell the customer

Say which of the two it was. The customer report (menu **3**) records it for you.
