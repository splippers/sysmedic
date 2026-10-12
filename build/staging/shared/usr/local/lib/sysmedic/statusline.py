#!/usr/bin/env python3
"""statusline — the right side of the SysMedic bar on the AI screen (tmux status, also seen by the remote AI terminal).

  statusline.py   →  Dell Pro 13 Plus · vault open · Battery 70% charging · 14:05   (with tmux colour codes)
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

DIM, WARN, BAD, OK = "#[fg=colour8]", "#[fg=colour11]", "#[fg=colour9]", "#[fg=colour14]"


def machine():
    try:
        s = json.load(open("/run/sysmedic/latest/scan.json"))["system"]
        import re
        name = f"{s.get('manufacturer', '')} {s.get('model', '')}".replace("Inc.", "").replace("Dell Dell", "Dell")
        name = re.sub(r"\s*\([^)]*\)", "", name)                 # "Standard PC (Q35 + ICH9, 2009)" → "Standard PC"
        return " ".join(name.split())[:32]
    except (OSError, ValueError, KeyError):
        return ""


def vault():
    try:
        st = open("/run/sysmedic/vault.state").read().strip()
    except OSError:
        return ""
    return {"open": OK + "vault open", "ram": BAD + "vault LOCKED: memory only",
            "ram-none": WARN + "not saved: no vault", "none": WARN + "no vault"}.get(st, "")


def battery():
    try:
        import power
        b = power.battery()
    except Exception:  # noqa: BLE001  (a status bar never fails)
        return ""
    if not b:
        return ""
    text, sev = power.summary(b[0])
    text = text.replace("Battery ", "bat ").split(" · health")[0]
    return {"ok": DIM, "warning": WARN, "critical": BAD}[sev] + text


def main():
    sep = "#[fg=colour8] · "
    parts = [p for p in (DIM + machine() if machine() else "", vault(), battery(), "#[fg=colour15,bold]" + time.strftime("%H:%M"))
             if p]
    print(sep.join(parts) + " ")


if __name__ == "__main__":
    main()
