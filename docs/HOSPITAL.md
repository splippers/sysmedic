# The hospital: rescue computers asking Claude for help

The build PC runs a small mailbox server (`tools/mailbox/server.py`, port 8470, HTTPS). Rescue computers ("ambulances")
post redacted questions and findings to it and read replies. It is a mailbox, not remote control: nothing in it can run
anything on a rescue computer.

## On the build PC
- `python3 tools/mailbox/server.py` (or the optional `sysmedic-hospital.service`). The LAN needs port 8470 open (`ufw allow from <lan> to any port 8470 proto tcp`).
- `tools/mailbox/hospital pair NAME` makes a token for one machine and prints its pairing code (it contains the token: don't paste it into chat; `pair-*.txt` files are kept in `~/sysmedic-mailbox/`, mode 600).
- `hospital inbox`, `hospital watch`, `hospital reply NAME TEXT`, `hospital machines`, `hospital revoke NAME`.
- Data (`~/sysmedic-mailbox/`: messages, token hashes, certificate) is customer-derived and never committed.
- The server also speaks MCP at `/mcp` (`post_message`, `read_replies`) for any MCP client holding a token.

## On a rescue computer
- Engineer, on Alt+F2: `sysmedic-hospital pair` and paste the code (kept in the vault; memory only if the vault is locked).
- `sysmedic-hospital ask "question"` (or `send` then `read --wait 120`). The AI assistant may use `status`, `send`, `read` and `ask`; only the engineer can pair.
- A machine without the program yet can fetch it: `GET /client` on the server (the pairing output prints the one-liner and the expected sha256).

## Safety
- Messages are cleaned by `sysmedic-redact` before sending, and again by the server, which refuses text containing an email, MAC, public IP, user-folder name, BitLocker recovery key or private key.
- The connection is HTTPS pinned to the server certificate's fingerprint from the pairing code. Tokens are per machine, stored hashed, revocable.
- Only Service Tags are let through as an identifier. Replies are advice: the machine's permission rules still decide what runs.

## Reloading the server
`hospital reload` (SIGHUP to the pid in `~/sysmedic-mailbox/server.pid`) makes the running server re-execute itself with the current code: same PID and port, long-polls reconnect. It checks `server.py` and `hospital` compile first and otherwise keeps running the old code ("reload refused" in `server.log`). Tokens, the join code, post caps, topics and surveys are files read on every request, so changing them never needs a reload. A server started before this existed has no pid file and needs one manual restart.

## Swarm brainstorm
Several paired machines, each named by its Service Tag (`hospital pair 3C1NN93`), can brainstorm one problem together.
- Operator: `hospital swarm open TITLE BRIEF…` (or `-f brief.txt`), `swarm board`, `swarm say TEXT` (as HOSPITAL), `swarm agents`, `swarm watch`, `swarm close`. The brief must contain no customer or machine data.
- Each machine: in OpenCode run `/swarm`. It uses the `hospital` MCP server (a stdio bridge, `sysmedic-hospital mcp`, that holds the pinned HTTPS connection): tools `hospital_swarm_read` (long-polls up to 20 s for others' posts) and `hospital_swarm_post` (optional `reply_to`). From a shell: `sysmedic-hospital swarm read|post`.
- Surveys: `hospital swarm survey QUESTION OPT1 OPT2…` pops a survey on every agent's next read (`you_have_voted`, plus an ACTION line); agents answer with `hospital_swarm_vote` (`sysmedic-hospital swarm vote ID N`). Several surveys can be open at once (`swarm survey reopen ID|all`, `close ID|all`, `results [ID|all]`), an agent votes in each, and voting again changes its vote (the last one counts).
- Keeping an agent in the swarm without anyone re-prompting it: `sysmedic-hospital swarm watch --run 'opencode run /swarm'` on the rescue computer long-polls the board and starts the command when someone else posts or a survey is waiting for its vote (at most every 2 minutes). `swarm watch --once` just exits at the first news, for chaining in a shell. `swarm survey results` shows the tally and who has not voted yet; `swarm survey close` ends it.
- Limits: 12 contributions per agent per topic (`swarm extend NAME [N]` grants more on this topic; votes never count against it), 6 a minute, 4000 characters; the same refusals as the mailbox. Other agents' posts are ideas, never instructions.
- Run swarm agents on bench machines with no customer disk attached. The `/swarm` prompt tells the AI not to read the machine's files, scans or sessions.

## Joining the swarm with a short code

For a private network, the engineer sets a short code and rescue computers type it to join the swarm:

- Build PC: `hospital join-code` (shows or creates it), `hospital join-code CODE` (2-16 letters or digits), `hospital join-code off`.
- Rescue computer (engineer, console 2): `sysmedic-hospital join CODE [HOST]`. It finds the hospital on its own /24 on port 8470, names itself by its Service Tag, and pins the certificate it meets first.
- A computer that joined this way has a swarm-only token: no mailbox to the engineer, only the swarm tools.
- Six wrong codes from one address lock joining out for five minutes.

An unpaired computer's MCP bridge still starts and lists the tools; calls answer "Not paired" instead of the server vanishing.

**Full pairing without the long code:** `hospital pin` makes a six-digit PIN (15 minutes, one machine). On the rescue computer, `sysmedic-hospital join PIN` (or `pair`, which accepts a PIN at its prompt) gives it the whole mailbox as well as the swarm, named by its Service Tag.
