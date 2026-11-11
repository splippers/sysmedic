---
title: Reading the scan
summary: What each finding means, how worried to be, and what to do next.
time: 5 min
level: beginner
---
## What the scan is

The triage scan looks at the machine and never writes to it. Run it again any time, from the menu (**1**) or here:

```run
sysmedic-scan
```

> Why: it is safe to run as often as you like, so run it before and after you change anything. That gives you a before and after for the report.

## The four marks

| Mark | Meaning |
|---|---|
| ✖ critical | Something is broken or about to be. Deal with it first. |
| ▲ warning | Worth fixing or telling the customer. |
| ● note | Information. Often explains a symptom. |
| ✔ OK | Checked and fine. |

The line of counts at the top (`✖ 0 critical  ▲ 1 warning …`) tells you in a glance how the visit will go.

## Read from the top

Findings are ordered, most serious first. Each has a dim line of detail under it and a **→** line with the next step. Do the **→** step before anything else: it is written for exactly this finding.

> Why: a failing disk found at the top matters more than a slow boot found at the bottom, and fixing things in the wrong order can lose data.

## Failing disk? Stop writing to it

If a finding says a disk is failing, do not repair, scan or defragment it. Make a copy first. The lesson *A failing disk* shows how.

## Slow everything?

A warning about **USB 2.0** means SysMedic is in a slow port or cable. Power off, move it to a USB 3 port, and run the scan again.

## Disk locked, "read-only" errors

Customer disks start write-protected. If something says "permission denied" or "read-only" when writing to a disk, that is working as intended. Lesson *Repair and sign off* shows how to unlock one partition deliberately.

## Keep the evidence

Add a note to anything you decide or tell the customer:

```cmd
sysmedic-note "Advised RAM check: two crashes this week"
```

It appears in the job report.
