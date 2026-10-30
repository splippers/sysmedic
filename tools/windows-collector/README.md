# SysMedic Windows evidence collector

Read-only evidence collection from a running Windows installation, for deliberate use by an engineer.
Design, privacy rules and the snapshot format: [docs/EXCHANGE.md](../../docs/EXCHANGE.md).

| File | |
|---|---|
| `SysMedic-Collect.ps1` | the collector (Windows PowerShell 5.1+, no install needed) |
| `Run-SysMedic-Collector.cmd` | double-click launcher |
| `fetch-age.sh` | build step: fetches the pinned `age.exe` (needed to encrypt; not stored in git) |
| `age-LICENSE.txt` | age's licence (copied with `age.exe`) |

These are copied onto the exchange partition's `collector/` folder by `build/xchg_layout.py populate` (stick and caddy builds).
Use `-ListOnly` to see what it would collect without collecting.

It is not a repair tool and never writes to the Windows installation.
