---
title: Check a PC over and report
summary: A full read-only health check, then a plain-English report for the customer.
when: "Someone hands you a PC and says: have a look at it."
risk: read-only
time: 10 min
---
## Scan the machine

```run
sysmedic-scan
```

This looks at the disks, memory, temperatures, battery and Windows, and changes nothing. It is the same as menu **1**.

> Why: the scan comes first so every later step is based on what is actually wrong, not on what the customer thinks is wrong.

## Read what it found

Each line has a mark: **✖** needs attention now, **▲** worth a look, **●** for your information, **✔** fine. Read the ✖ and ▲ lines first. The line under each one says what to do next.

> Why: most visits are decided by one or two findings. The rest is reassurance for the customer.

## Check the hardware properly

Menu **2** runs the hardware tests (memory, disk surface, fans). They take a few minutes and only read. When they finish you can see the result again here:

```run
sysmedic-hwtest report
```

## Make the customer report

Menu **3** builds the report: what was checked, what was found, what you did. It is written in plain language so you can hand it over as it is.

> Why: customers remember the report longer than the visit. It is also your record if they come back.

## Sign off

Tick back through the ✖ and ▲ lines. Anything left is something to tell the customer, not something to hide. Write a short note for the job with `sysmedic-note "what you told them"`.
