"""engineer — the engineer's own preferences, kept in the encrypted vault so they follow them from job to job.

Today: the private hotspot's name, password, band and country. Locked vault: nothing is kept (a fresh random profile
for the visit), so a drive found in the street holds no one's Wi-Fi password.
"""
import json
import os
import secrets

import accesscode

FILE = "/run/sysmedic/vault-fs/engineer.json"
TMP = "/run/sysmedic/hotspot/profile.json"          # visit-only profile while the vault is locked


def persistent():
    return os.path.isdir(os.path.dirname(FILE)) and os.path.ismount(os.path.dirname(FILE))


def load():
    for path in (FILE, TMP):
        try:
            return json.load(open(path)), path == FILE
        except (OSError, ValueError):
            continue
    return {}, False


def save(prof):
    path = FILE if persistent() else TMP
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(prof, f, indent=1)
    os.sync()
    return path == FILE


def hotspot():
    """The hotspot profile, filled in with defaults on first use: {ssid, psk, band, country}. psk '' = use the access code."""
    prof, kept = load()
    h = prof.get("hotspot", {})
    changed = False
    if not h.get("ssid"):
        h["ssid"] = "SysMedic-" + secrets.token_hex(2).upper()
        changed = True
    h.setdefault("psk", "")
    h.setdefault("band", "auto")
    h.setdefault("country", "")
    prof["hotspot"] = h
    if changed:
        kept = save(prof)
    return h, kept


def psk(h):
    """The Wi-Fi password: the engineer's own, else their access code, else a random one kept with the profile."""
    if h.get("psk"):
        return h["psk"]
    code = accesscode.get()
    if len(code) >= 8:
        return code
    prof, _ = load()
    hs = prof.setdefault("hotspot", h)
    if not hs.get("generated"):
        hs["generated"] = accesscode.suggest(4)
        save(prof)
    return hs["generated"]
