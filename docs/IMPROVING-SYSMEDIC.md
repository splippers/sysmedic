# Improving SysMedic from the field

Every visit leaves a record designed to be read later, by you or in a Claude session, to find out what to fix next.

## What's recorded

- **Console transcripts:** tty1 and tty2 are recorded with `script` to `/mnt/persist/transcripts/<time>-tty1.log`. **Output only:** keystrokes aren't logged, so hidden entries like BitLocker keys are never captured.
- **AI conversations:** the offline assistant's full conversation, including tool calls and output (`session/ai/ask-*.jsonl`), and the cloud assistant's session data, copied when OpenCode exits (`session/ai/opencode-*`).
- **Audit trail, scans (first to last), job notes, hardware test results:** all in the session folder.
- **Feedback:** `sysmedic-note --feedback "Qwen suggested fsck on a mounted volume"`. The AI is told to record its own mistakes the same way. Feedback goes into the review bundle, not the customer's report.

## The review bundle: `claude-review.md`

`sysmedic-transcript` (run automatically at shutdown and by `sysmedic-report`) writes one Markdown file per visit, in the session folder and in `/mnt/persist/claude-review/` (caddy: `/srv/sysmedic/claude-review/`). It contains:
- what to look for
- the SysMedic edition and version
- the machine and job
- **engineer feedback**
- findings in the first and latest scan
- **tools the AI wanted but weren't installed**
- the audit trail
- both AI conversations
- the console transcripts, with control codes stripped and the most recent 150 KB kept

`sysmedic-transcript --list` shows which sessions have a bundle.

These files contain customer data. Review them before sharing.

## Getting all the feedback in one place

Plug the stick into a running caddy and its sessions and bundles are collected into `/srv/sysmedic` automatically ([EDITIONS-AND-DEPLOY](EDITIONS-AND-DEPLOY.md)).

## In a Claude session

Plug in the caddy, then ask Claude to read `/srv/sysmedic/claude-review/*.md` (mount the caddy read-only first) and propose changes. Make them in this repo's `build/staging`, then run `build/sysmedic-deploy --caddy` and `--stick`.
