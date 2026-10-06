# Vendored libraries (pure Python, read-only analysis)

Shipped inside SysMedic so the rescue system never downloads and runs code from the internet during a visit.

| Library | Version | Source | Licence | Used by |
|---|---|---|---|---|
| etl-parser | commit e9ad559 (2026-05-20), v1.0.1 | https://github.com/airbus-cert/etl-parser | Apache-2.0 | `sysmedic-win etl` (via `etl_dump.py`) |
| construct | 2.10.70 | https://pypi.org/project/construct/ | MIT | etl-parser |

Proposed and validated in the field by SysMedic's AI on a Windows 11 25H2 machine (33/34 traces decoded).
To update: replace the folders, keep the licences, test `sysmedic-win etl` on the samples in etl-parser's tests/example.
