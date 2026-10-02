# AI assistants

SysMedic has two assistants. Both start from the triage scan, follow the same instructions (`/opt/sysmedic/SYSMEDIC-AGENT.md`), and work within the safety layer: they can't unlock disks, enter BitLocker keys, or run repairs that need the engineer.

## Which one starts

At boot, with internet **and** customer consent (`y`), and 4 GB RAM plus an AVX CPU: the **cloud** assistant. Otherwise the **offline** assistant, if the machine has 6 GB+ RAM. Below that: the rescue menu. Either can be started by hand: `opencode` or `sysmedic-ask`.

## Cloud: OpenCode with Big Pickle

- OpenCode (v2.0.22 on the caddy) with `opencode/big-pickle`, on the **free OpenCode Zen tier: no account, no key**. It starts by reading the scan, explaining the findings and proposing a plan, without changing anything.
- **Permissions:**
  - Read-only diagnostics run without asking (lsblk, smartctl, dmesg, ping, dig, `sysmedic-scan`, `sysmedic-win info/crashes/events/autoruns/malware`, `sysmedic-hwtest report`, …).
  - Everything else asks. File edits ask, and reads outside SysMedic's folders ask.
  - Unlock, blockdev, hdparm, BitLocker, repairs, chntpw, nwipe, mkfs and `dd of=/dev/…` are **denied**.
- Full tool output is shown (not collapsed). Its history is wiped at each boot, and the visit's conversation is copied into the session for review.
- If it says "Reconnect OpenCode Console": that was caused by a stale paid-plan login, now removed. Free use needs no login.

## Offline: `sysmedic-ask`

- Local models via Ollama, from the drive: **qwen2.5:7b** on machines with 12 GB+ RAM, otherwise **qwen2.5:3b**. A short prompt (rules + scan) is pre-loaded in the background at boot, so the first answer comes in about a minute on CPU.
- **How commands run:**
  - Read-only checks run straight away. Their **full output streams live on the console**, framed, and the model sees up to ~6,000 characters of it.
  - Anything else is shown first: `[Y]es / [n]o / [e]dit` (Enter = yes). Chained commands auto-run only if every part is read-only.
  - Commands the model writes in its text (instead of calling the tool) need an explicit `y`, which stops things like `shutdown` running by accident.
  - There's a 180 s limit per command. Ctrl-C stops just that command; `/quit` at a prompt returns to the question.
  - Commands run without a keyboard, so the model is told to use non-interactive forms (`ping -c 4`, `mtr -rwc 5`, `top -bn1`, `tcpdump -c 50`).
- Its own commands: `/scan` (re-scan and restart the conversation), `/new`, `/quit`.
- **Limits:** the 3B model sometimes misreads facts (dates, which partition). Tool output on screen is the truth; check it against the summary. The 7B and cloud models are much better.
- Conversations are saved to the session (`ai/ask-*.jsonl`).

## Things both are told

- The scan and real command output are the facts: never invent devices or results.
- Image a failing disk before repairing it. Mount customer filesystems read-only to inspect.
- SysMedic may be running from a USB drive: never suggest unplugging or moving it while running.
- Check `systemd-detect-virt` before calling a machine virtual.
- Through USB-NVMe bridges, SMART error logs are truncated, so don't chase them.
- Which edition they're on. On the stick, jobs needing imaging, burn-in suites, macOS repair or carving are handed to the caddy.
- Record SysMedic's own limitations: `sysmedic-note --feedback "…"`.
