# marvin-bot (scaffold, untested)
Discord -> `bot` container -> `opencode serve` container -> provider (Big Pickle).
Chat only: bash/edit/webfetch denied in `opencode.json`; users/channels allowlisted (empty = deny);
4 msgs/min/user; replies filtered for secrets, private IPs, mass mentions; opencode port not published.

Before first run: `cp .env.example .env && chmod 600 .env`, fill it in, pin the image digest,
confirm the provider key works with one `opencode run`, and check the session API shape against the
installed opencode version (`POST /session`, `POST /session/:id/message`). Put it in its own directory
on Marvin, not inside any production path.
