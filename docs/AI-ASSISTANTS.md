# AI assistants

SysMedic has two assistants. Both start from the triage scan, follow the same instructions (`/opt/sysmedic/SYSMEDIC-AGENT.md`), and work within the safety layer: they can't unlock disks, enter BitLocker keys, or run repairs that need the engineer.

## Which one starts

At boot, with internet **and** customer consent (`y`), and 4 GB RAM plus an AVX CPU: the **cloud** assistant. Otherwise the **offline** assistant, if the machine has 6 GB+ RAM. Below that: the rescue menu. Either can be started by hand: `opencode` or `sysmedic-ask`.

## Cloud: OpenCode with Big Pickle

- OpenCode (2.0.22 on the caddy, 1.18.34 on the stick; config in `~/.config/opencode/opencode.json`) with `opencode/big-pickle`, on the **free OpenCode Zen tier: no account, no key**. It starts by reading the scan, explaining the findings and proposing a plan, without changing anything.
- **It is SysMedic.** OpenCode runs a dedicated **SysMedic** agent (the default; OpenCode's coding agents are switched off) whose system prompt is SysMedic's own instructions (`/opt/sysmedic/SYSMEDIC-AGENT.md`). That *replaces* OpenCode's "you are a coding assistant" prompt, so it knows what it is and what it's for, and the shorter prompt makes offline use faster.
- **SysMedic look:** the SysMedic logo, a SysMedic theme in the 16 console colours (renders properly on the Linux console), rescue examples in the prompt, rescue tips instead of coding tips. The deploy applies this to OpenCode's binary (`build/opencode-brand.py`; logo and text only, same size, re-applied after any OpenCode update). Auto-update and sharing are off.
- **Permissions:**
  - Read-only diagnostics run without asking (lsblk, smartctl, dmesg, ping, dig, `sysmedic-scan`, `sysmedic-win info/crashes/events/autoruns/malware`, `sysmedic-hwtest report`, …).
  - Everything else asks. File edits ask, and reads outside SysMedic's folders ask.
  - Unlock, blockdev, hdparm, BitLocker, repairs, chntpw, nwipe, mkfs and `dd of=/dev/…` are **denied**.
- **Tests as slash commands:** type `/` for the menu of SysMedic's tests (`/disk-test`, `/cpu-stress`, `/windows-checkup`, `/full-check`…; see [HARDWARE-TESTING](HARDWARE-TESTING.md)). OpenCode's developer commands are out of the `/` menu (still in Ctrl+P).
- **A clean screen:** no sidebar, no "thinking", no timestamps or metadata lines, no animations, no tips or upsells; a scrollbar for long output. These defaults ship in `~/.local/state/opencode/kv.json` (1.18) and `~/.config/opencode/cli.json` (2.0).
- **If OpenCode misbehaves:** `sysmedic-ai-repair` (menu 6, or on console 2) saves the conversation, stops stuck processes, clears OpenCode's state, restores SysMedic's settings and, if needed, the known-good program (kept in `/usr/local/share/sysmedic/opencode`), restarts the offline AI, and runs a self-check (`sysmedic-ai-repair --check` for the check alone). If OpenCode exits with an error straight after starting, the console says so and points to it.
- **Full tool output is shown.** OpenCode normally cuts command output to a few lines behind "Click to expand", which needs a mouse; SysMedic starts every output expanded, so long results are read with **Page Up/Down**. Its history is wiped at each boot, and the visit's conversation is copied into the session for review.
- If it says "Reconnect OpenCode Console": that was caused by a stale paid-plan login, now removed. Free use needs no login.

## Offline: `sysmedic-ask`

- Local models via Ollama, from the drive: **qwen2.5:7b** on machines with 12 GB+ RAM, otherwise **qwen2.5:3b**. A short prompt (rules + scan) is pre-loaded in the background at boot, so the first answer comes in about a minute on CPU.
- **How commands run:**
  - Read-only checks run straight away. Their **full output streams live on the console**, framed, and the model sees up to ~6,000 characters of it.
  - Anything else is shown first: `[Y]es / [n]o / [e]dit` (Enter = yes). Chained commands auto-run only if every part is read-only.
  - Commands the model writes in its text (instead of calling the tool) need an explicit `y`, which stops things like `shutdown` running by accident.
  - There's a 180 s limit per command. Ctrl-C stops just that command; `/quit` at a prompt returns to the question.
  - Commands run without a keyboard, so the model is told to use non-interactive forms (`ping -c 4`, `mtr -rwc 5`, `top -bn1`, `tcpdump -c 50`).
- Its own commands: `/tests` (the test catalogue), `/feedback TEXT` (record something SysMedic should do better, for claude-review.md), `/scan` (re-scan and restart the conversation), `/new`, `/quit`.
- **The engineer is in charge.** A command you decline, a plain "No", or "forget the disks / drop BitLocker" is enforced by SysMedic itself, not left to the model: it won't re-offer those for the rest of the conversation (mentioning the topic yourself brings it back). "No" on its own gets "OK. What would you like to do?" with no new suggestions. A correction ("that doesn't exist", "you're ignoring me", "don't hallucinate") refuses its last suggestions too, and the model stops seeing the earlier conversation, so it can't copy its old plan back; it only ever sees the last few exchanges (the whole conversation is still saved). Suggestions you've refused that reappear in its text are flagged and rewritten.
- **GPU or CPU.** At start-up `sysmedic-ai-device` asks Ollama which GPUs it sees and uses a **discrete** GPU with at least 3.5 GiB through Vulkan (AMD via Mesa RADV; NVIDIA GTX 16/RTX via Mesa NVK, not yet tested on a real NVIDIA laptop; measurements below used NVIDIA's own driver). Built-in graphics are never used: measured slower than the CPU (Intel UHD 630: 2 tok/s against 10). After the model loads, a timed self-test must pass (correct reply, at least 15 tok/s for the 3B, 8 for the 7B) or Ollama is restarted on the CPU. The assistant's header says which it is on; `sysmedic-ai-device status` says why. Turn it off with the kernel option `sysmedic.aigpu=off` or `touch /mnt/persist/ai-gpu-off`. On a USB 2.0 stick the model's load time from the stick (about 4 minutes) doesn't change; answers do (GTX 1650: 10 s instead of 130 s to read SysMedic's instructions, replies 4× faster).
- **Real tools only.** Every command the offline model proposes is checked before you see it: the program must be installed, `sysmedic-tests` test names must be in the catalogue (common guesses like `mem` or `memslot` map to the real `ram` / `ram-modules`), disk tests need `--disk` with a whole disk, and `sysmedic-hwtest` / `sysmedic-win` subcommands must exist. Made-up commands go back to the model with the real list, never to you. Made-up commands in its prose are flagged on screen ("⚠ SysMedic check: … doesn't exist") and the model is made to correct itself. Its instructions list the real tests. For OpenCode (cloud or offline Qwen) the test list is generated into its instructions at deploy, and a command that doesn't exist fails with "does not exist on this rescue system" (logged as NOT FOUND in the audit trail).
- Saying "record / report / flag this …" offers to save it as SysMedic feedback (claude-review.md).
- **Plain test requests skip the model:** "test the GPU", "check the battery", "how's the Wi-Fi" offer the matching SysMedic test straight away (Enter = run), then the model explains the result. The small offline model can fixate on its own plan; this makes sure a direct request is always obeyed. Each message also reminds the model to answer the latest request and drop plans the engineer hasn't agreed to.
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
