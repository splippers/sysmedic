# Fleet telemetry and the NerveCentre hook

Every computer you SSH into can announce its own health, and one hub collects it for NerveCentre (or anything else) to show.

```
each machine ──LLDP──▶ its switch / neighbours        (tools/lldp, link-local)
     │
     └──HTTP POST every 30 s──▶ telemetry hub on Marvin ──▶ /api/fleet (JSON)  and  /fleet (page)
                                                              ▲
                                       NerveCentre links, proxies or embeds it
```

## The record (the same on LLDP and to the hub)

`h` hostname · `os` · `k` kernel · `up` uptime seconds · `l` load · `cpu` cores · `m` memory % · `d` disk % · `t` hottest sensor °C · `ct` Docker containers · `sv` listening services (`name:port`) · `sm` SysMedic version · `ts` time. LLDP carries it as a custom TLV (OUI 53:4d:31) next to a one-line system description, so `sysmedic-discover` shows it too.

## The hub (`tools/telemetry/telemetry-hub.py`)

| | |
|---|---|
| `POST /ingest` | a record; private source addresses only, 8 KB max, unknown fields dropped, one push per 2 s per machine |
| `GET /api/fleet` | `{"updated", "hosts": [{record…, "ip", "age_s", "state": up / stale (90 s) / down (300 s), "flags": [...]}]}` |
| `GET /api/host/NAME` | one machine |
| `GET /fleet` | a self-refreshing page of cards (loads relative `api/fleet`, so it works behind a path prefix or in an iframe) |
| `GET /health` | `ok` |

Flags: disk or memory ≥ 90 %, ≥ 85 °C, load above twice the core count. Nothing is executed; the only thing written is a state file so the last-known picture survives a restart. Trust model is NerveCentre's own: a trusted LAN. The records are also on the wire as LLDP, so they are not secret.

Run it: `tools/telemetry/sysmedic-telemetry-hub.service` (DynamicUser, hardened, port 8471). Test: `python3 tools/telemetry/test_hub.py`.

Machines: `tools/lldp/install-lldp-telemetry --hub http://192.168.1.2:8471 jon@HOST…` (adds `/etc/sysmedic/telemetry-hub`; `--hub off` stops pushing).

## Hooking it into NerveCentre

NerveCentre's rule is one nginx `upstream` plus one `location` per service, with a card on the landing page. For the hub:

```nginx
upstream nerve_fleet { server 192.168.1.2:8471; }
# inside the portal's server block, next to the other services:
location = /fleet { return 301 http://$host/fleet/; }
location /fleet/ { proxy_pass http://nerve_fleet/fleet/; }
location /fleet/api/ { proxy_pass http://nerve_fleet/api/; }
```

(`/fleet/` serves the page; its relative `api/fleet` call lands on `/fleet/api/fleet`, which the last block maps to the hub.) The landing-page card links to `/fleet/`. A health badge for the card is `GET http://192.168.1.2:8471/health`, and `GET /api/fleet` is the feed for any future widget (host count, anything flagged).

The hub lives on Marvin, not Eddie, because the portal can point at any host: this is exactly the "service on a different machine" case the portal has to handle. This file records the hook; adding it to the portal is a change to the live NerveCentre and is made with the NerveCentre rework.
