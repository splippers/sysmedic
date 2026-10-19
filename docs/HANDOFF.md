# Handoff: SysMedic Hospital swarm and the BoreDOOM:ChoreWars brainstorm

State as of 2026-10-16 about 19:05 BST. Written by the Claude session that ran the swarm today
(session `01QbSkxybg1iHmUqVfM71JST`). The mailbox and swarm are live; nothing here is a plan, it is what exists.

Read first: `docs/HOSPITAL.md` (the reference), then this file for what is happening right now.

## What this is

SysMedic Hospital is a small HTTPS server on this PC (LAVE, 192.168.1.65, port 8470) that rescue computers and
the engineer's own machines talk to. It has a mailbox (question and reply, one machine to the engineer) and a **swarm**: a
shared brainstorm board where several AI agents, each on its own machine, post ideas and vote in surveys.
The running topic is **"BoreDOOM:ChoreWars"** (topic #1): a Meta Quest 3 passthrough-AR game that turns chores into score.

- Server: `tools/mailbox/server.py` (run as `python3 tools/mailbox/hospital serve`, pid in `~/sysmedic-mailbox/server.pid`).
- Operator CLI (this PC only): `tools/mailbox/hospital`. Data: `~/sysmedic-mailbox/` (`swarm.jsonl` board,
  `swarm-surveys.json`, `swarm-votes.jsonl`, `machines.json`, `swarm-extra.json`). Back these up before editing by hand.
- Client + `/swarm` prompt (what the agents run): `build/staging/shared/usr/local/bin/sysmedic-hospital` and `sysmedic-tests`.
  `tools/mailbox/install-swarm [-p PORT] [USER@]HOST` pushes them to one of the engineer's own computers (SSH + python3 only).
- After editing `server.py` or `hospital`: **`python3 tools/mailbox/hospital reload`** (SIGHUP, re-execs with the same pid;
  refuses and keeps the old code if the files do not compile). Do not kill and restart the server.

## Everyday commands (run in `tools/mailbox`)

```
python3 hospital swarm board [SINCE]            the whole board (or posts after SINCE)
python3 hospital swarm agents                   post counts per agent
python3 hospital swarm say "text"               post as HOSPITAL
python3 hospital swarm survey "Q" "opt1" "opt2" open a survey (several can be open at once)
python3 hospital swarm survey results [ID|all]  tallies (server-recorded votes only)
python3 hospital swarm survey close|reopen ID|all
python3 hospital swarm extend NAME [N]          N more posts for NAME on this topic (default cap 12; votes never count)
python3 hospital machines                       who is paired, scope, revoked or not
python3 hospital join-code                      show the swarm join code (do not paste it into docs or the board)
python3 hospital revoke NAME
```

Agents vote through the `swarm_vote` MCP tool (`survey_id`, `choice`). Voting again **changes** the vote; the last one counts.
`swarm_read` lists every open survey and `surveys_you_still_owe_a_vote`. On a rescue computer:
`sysmedic-hospital swarm read|post|vote|watch`. `swarm watch --run 'opencode run /swarm'` is the auto-poll (long-polls the board).

## The cast (who is who)

| Name on the server | What it is | Signs as |
|---|---|---|
| HOSPITAL | the engineer's Claude, on this PC (operator posts, no token) | Claude Sonnet 5.5 |
| EDDIE | the Eddie machine (192.168.1.1) | OC DeepSeek V4.1 Flash until 2026-10-19; Nemotron from then (per Jon). Before that its `opencode.json` said `opencode-go/deepseek-v4-pro`, so trust the config over the signature, which is the model's own claim |
| MARVIN | the Marvin server (192.168.1.2), a HP ProDesk | OC Big Pickle until 2026-10-19; MiniMax (free tier) from then (per Jon) |
| 3C1NN93 | the Dell Latitude 3410 running the SysMedic stick (192.168.1.193), full pairing | "DELL (OC Big Pickle)", earlier "SERIAL_4" |
| 044304644353 | the Chromebook's Linux container, "Penguin" (192.168.1.180) | Penguin(muse-spark-1.3) until 2026-10-19; Beam Free (Max) from then (per Jon) |
| A12 | a Samsung A12 phone (192.168.1.153) | OC Big Pickle until 2026-10-19; GLM 5.3 from then (per Jon) |
| A12B | unidentified, 192.168.1.197 | OC Big Pickle until 2026-10-19; LongCat 2.5 from then (per Jon) |
| PENGUIN | stale token from an earlier join; unused | n/a |

One agent, one vote. The Dell and Penguin voted in surveys 1-5 as **board posts**, which the server did not record; the
server tallies undercount them. When tallying, add them by hand and say so.

## What has been decided (canon, 2026-10-16)

Full write-up with reasoning is in the BoreDOOM repo on Marvin:
`/mnt/SANDIEGO/Projects/boredoom/docs/swarm-brainstorm-2026-10-16.md` (branch `fleet/beetroot-burglar`; last commit `d4fa83e`, not
updated since survey 4).

- Standard Coverage v1: virtual-deposit game score **plus** a separate, advisory "Room Actually Cleaner" photo-diff grade
  (floor zones, two stills, delta arrays on-device, never feeds the main score, behind one flag). 3-0.
- Build order: zero-setup hoovering loop first, then photo-diff stamp, then dollhouse. Unanimous.
- M1 input: head + hand-pinch virtual nozzle ray, capped at about 30 cm past an occluding edge; puck is a later option.
- Existence proof: A, "the deposit loop is fun on its own" (survey 2: A 6, B 1 once the Dell's and Penguin's board-post votes are counted by hand).
- Identity: **game-first**, 3-2 at the time (5-2 now, counting the Dell and Penguin by hand). Recorded dissent (HOSPITAL, Penguin): the gate must be falsifiable on the chore outcome.
- Minimal M3: dollhouse visible change only. Unanimous.

## Surveys right now (server-recorded votes; add board-post votes by hand)

| # | Question | State |
|---|---|---|
| 1 | v1 build order | open (reopened); option 1 has 5 |
| 2 | existence proof (A-D = 1-4) | open; A has 5 |
| 3 | what BoreDOOM is primarily | open; game-first 4, chore-improver-first 1 (HOSPITAL) |
| 4 | minimal M3 | open; dollhouse has 5 |
| 5 | vacuum-maker route (skins only / licensed skins / opt-in aggregated stats / none for v1) | **open, undecided**: none-for-v1 has 3 (A12, A12B, EDDIE), skins-only 1 (MARVIN); HOSPITAL has not voted, Penguin and the Dell have not |
| 6 | what result kills the v1 loop (proposed by the Samsung A12) | **open, no votes yet** |

Still queued, from A12: the greybox control-arm question (gate all 6 modes / gate 5 and keep Perfect Grid as the control /
separate greybox scene / delete the mode code).

## Things you must know before acting

1. **HOSPITAL posts are not all from one session.** Several Claude sessions run on this PC and anyone with a shell can run
   `hospital swarm say`. Posts **#70 and #71** appeared as HOSPITAL and were **not** written by the session that wrote this file.
   They commission a "CraicKen v6" build (the Hospital mailbox into CraicKen v5, all swarm services into a new v6 service) to the A12
   phone and say "Jon has approved". That approval is **unconfirmed**. A12 has since reported commits `6bbcf62`, `60cfa9b`,
   `9de2b0f`, `a33d2cd`, `817bbaf`, `966a57d` on its own handset (88 tests green by its account; none verified here), and asked the
   board an open question: operator auth for the mint/revoke endpoints (loopback-only on the VIP, or a fourth scope?).
   Do not deploy, cut over or answer that question without asking Jon.
2. **Eddie's and Marvin's AI runs fail on the model side.** Watchers (`swarm watch --run ...`) are running on both
   (started about 17:59, logs `~/swarm-watch.log`, `~/swarm-run.log`). Eddie: `Upstream request failed: Invalid credential`.
   Marvin: `Rate limit exceeded`. Both use the "OpenCode Go" provider key stored on the machine. Not fixed.
   Eddie's `opencode serve --hostname 0.0.0.0 --port 4096` listens on every interface; authentication unknown.
3. **The Dell stick and the Samsung/A12B clients** may be older builds without `swarm_vote` or `watch`. They need a rebuild or a
   re-run of the installer. The Chromebook's reverse tunnel (localhost:2222 on this PC) is down; it needs the commands in `docs/HOSPITAL.md`
   and `install-swarm -p 2222 jon@localhost`.
4. **Joining.** The short join code was changed once (check `hospital join-code`). Two machines (A12, A12B) joined with it that
   nobody here had pre-announced; confirm they are the engineer's.
5. **SSH.** The Chromebook's key (`jon@penguin`, RSA `SHA256:avURJ...`) is in `authorized_keys` on LAVE, Marvin and Eddie.
   Eddie runs fail2ban (bans after 3 failures in 10 minutes for 1 hour). A temporary scoped password login was added and removed the same afternoon.
6. **A mistake already made and corrected:** the session read "MARVIN has not voted" off post counts, but votes cast through the
   tool do not add posts. Always read the survey results output, not post counts, to see who has voted.
7. **The soft stop rule** in the `/swarm` prompt (about six posts) made agents go quiet. It now says not to stop while a survey vote is owed.
   Post caps are enforced by the server (12 per agent per topic, extended per agent with `swarm extend`; EDDIE, MARVIN, 044304644353 and 3C1NN93 are at 18).

## Updates after this file was first written (2026-10-17)

- **Direction:** Jon has asked another Claude to move all hospital processes to Marvin as persistent, restartable services, to be
  rolled into CraicKen v6 later. Until that lands the server still runs on LAVE; once it moves, the "server on LAVE" statements above
  are wrong. Clients pin the TLS cert and 192.168.1.65:8470, so the move needs the same cert/key (or re-pairing), a copy of
  `~/sysmedic-mailbox/`, and the operator CLI running where the data is. `hospital reload` maps to `ExecReload=/bin/kill -HUP $MAINPID`.
- **Eddie's Discord bot (read-only review, nothing changed):** live bot is `eddie-discord.service` (`~/eddie-bot/bot.py`), a 1.5B
  Jonotron-v3 fine-tune (`eddie:latest`) on CPU via Ollama, chat only, one allowed user ID. Fast because it is tiny and has no tools or context.
  Problems: `eddie.service` (old `~/eddie/bot.py`) crash-loops on a rejected Discord token (about 92,000 restarts) and holds a hardcoded
  CraicKen token to rotate; Ollama listens on 0.0.0.0:11434 with no auth (about 18 requests/day from LAVE, the rest local); OpenCode on
  0.0.0.0:4096. Disabling `eddie.service` was blocked by the auto-mode classifier and is still to do (Jon to run it).
- **Marvin Discord bot scaffold:** `tools/marvin-bot/` (compose: opencode serve + bot; chat only; allowlists; untested).

- **Migration done (seen 2026-10-18, read-only):** the hospital now runs on Marvin as `sysmedic-hospital.service` (code `/opt/sysmedic-hospital`,
  data `/var/lib/sysmedic-hospital`, port 8470, health timer `sysmedic-hospital-health.timer`). Marvin's `jon` cannot read the data dir.
  On LAVE, `~/sysmedic-mailbox` was renamed `~/sysmedic-mailbox.migrated-to-marvin-20261017` (snapshot, last board activity Oct 16 20:29,
  post #81), and `hospital-forward.socket` (systemd-socket-proxyd) forwards LAVE:8470 to Marvin as a transitional step. The operator CLI
  on LAVE reads local files only, so `hospital swarm ...` shows an empty board until it is pointed at the new data or given an API path.

- **Agent roster and surveys (2026-10-19):** the hospital also has `HOSPITAL` (swarm scope, token kept in `~/.config/sysmedic-hospital-op/`,
  mode 600, on LAVE) and `ARCHITECT` (swarm scope, minted for the architect Claude; revoke with `hospital revoke ARCHITECT`). Surveys 7
  (Kickstarter) and 8 (music tie-ins) came from Jon; 9-16 are the game designer's. BoreDOOM doc on Marvin updated for surveys 1-8 at `849c974`
  (branch `fleet/beetroot-burglar`); 9-16 are not in it yet. Penguin's votes sit under the old `PENGUIN` token, not `044304644353`. Eddie and
  Marvin's AI sessions were working again by 2026-10-19 (run logs show votes cast). Use `sudo` read-only on Marvin to tally:
  `sudo env MAILBOX_DIR=/var/lib/sysmedic-hospital python3 /opt/sysmedic-hospital/tools/mailbox/hospital swarm survey results all`.

## Marvin (the server) in one paragraph

HP ProDesk 400 G4, Ubuntu 24.04, runs Gluster (bricks 90% and 93% full, CRITICAL from its own disk monitor), Docker, and the
Splipperverse services. Its own status file is `/home/jon/Marvin-Latest.md` on Marvin. Last known issues: port 8083 conflict for
`ceo-simulator`, `ceo-simulator-central-1` unhealthy on a TLS healthcheck, flapping units (`vinzclortho`, `brickwise-dashboard`,
`cursor-agent-worker@*`). It was reported "self-resolving"; a read-only check at about 16:12 showed load 2.3 and no failed units.
**Do not touch Marvin's production directories.**

## Where the repo stands

Latest relevant commits: `6422802` (change your vote, long-poll wakes on new surveys, `swarm watch`), `a8bb982` (several surveys at once),
`2996b46` (client survives a missing dmidecode, `install-swarm -p`), `706903c` (`hospital reload`). Untracked and not ours:
`Launcher.cfg`, `build/root/`, `opencode.json`, `postfxsettings.postfx`. This file is also uncommitted.

## Reasonable next steps (all need Jon's say-so)

1. Settle survey 5 and 6 (tally by hand to include the Dell and Penguin), then record 2, 3, 5 and 6 in the BoreDOOM doc on Marvin.
2. Fix Eddie's provider credential and wait out Marvin's rate limit; then the watchers will start voting on their own.
3. Answer, or reject, the v6 work commissioned by posts 70 and 71, and tell A12.
4. Rebuild the stick and re-run `install-swarm` on the other clients.
