"""wifilib — what the machine's Wi-Fi radios can do, and which one should host the private hotspot.

A radio (phy) can often be a client and an access point at the same moment, but then both must share one channel;
a second radio (a USB dongle) is free to choose. The plan prefers a radio that isn't carrying the internet link,
on 2.4 GHz (the setup that works in the field: a USB dongle for the internet, the built-in radio for the hotspot, both on
2.4 GHz). 5 GHz is only used when asked for (--band 5).
"""
import os
import re
import subprocess

PREF_5 = (36, 40, 44, 48, 149, 153, 157, 161, 165)       # non-DFS channels: no radar wait, no forced channel move
PREF_24 = (6, 1, 11)


def run(cmd, timeout=15):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def _combos(block):
    """[{groups: [(types, max)], channels}] from 'valid interface combinations'."""
    res = []
    m = re.search(r"valid interface combinations:\n(.*?)(?:\n\t\w|\Z)", block, re.S)
    if not m:
        return res
    for chunk in re.split(r"\n\s*\* ", "\n" + m.group(1)):
        groups = [({t.strip() for t in g.group(1).split(",")}, int(g.group(2)))
                  for g in re.finditer(r"#\{\s*([^}]*)\}\s*<=\s*(\d+)", chunk)]
        if groups:
            ch = re.search(r"#channels\s*<=\s*(\d+)", chunk)
            res.append({"groups": groups, "channels": int(ch.group(1)) if ch else 1})
    return res


def _ap_and_client(c):
    """Can this combination hold an access point and a client at the same time?"""
    ap = [(t, n) for t, n in c["groups"] if "AP" in t and n >= 1]
    cl = [(t, n) for t, n in c["groups"] if "managed" in t and n >= 1]
    return any(a is not b or a[1] >= 2 for a in ap for b in cl)


def radios():
    """[{phy, driver, bus, ap, channels{'2.4':[...], '5':[...]}, ap_plus_client, ap_client_channels, ifaces[], busy}]"""
    out = run(["iw", "phy"])
    devs = run(["iw", "dev"])
    res = []
    for blk in re.split(r"(?m)^(?=Wiphy )", out):
        m = re.match(r"Wiphy (\S+)", blk)
        if not m:
            continue
        phy = m.group(1)
        chans = {"2.4": [], "5": []}
        for fm in re.finditer(r"\* (\d+)\.\d+ MHz \[(\d+)\] ([^\n]*)", blk):
            mhz, ch, flags = int(fm.group(1)), int(fm.group(2)), fm.group(3)
            if "disabled" in flags or "no IR" in flags or "radar" in flags:
                continue
            band = "2.4" if mhz < 3000 else "5" if mhz < 5900 else None
            if band:
                chans[band].append(ch)
        ap = bool(re.search(r"\* AP\b", blk.split("Supported commands")[0])) if "Supported interface modes" in blk else False
        combos = _combos(blk)
        both = [c for c in combos if _ap_and_client(c)]
        n = phy.replace("phy", "")
        ifaces = []
        dm = re.search(rf"phy#{n}\n(.*?)(?=\nphy#|\Z)", devs, re.S)
        for im in re.finditer(r"Interface (\S+)\n(.*?)(?=\n\tInterface|\Z)", dm.group(1) if dm else "", re.S):
            body = im.group(2)
            t = re.search(r"type (\S+)", body)
            fr = re.search(r"channel (\d+) \((\d+) MHz\)", body)
            ifaces.append({"name": im.group(1), "type": t.group(1) if t else "?",
                           "ssid": (re.search(r"ssid (.+)", body) or [None, ""])[1].strip(),
                           "channel": int(fr.group(1)) if fr else None, "mhz": int(fr.group(2)) if fr else None})
        link = [i for i in ifaces if i["type"] == "managed" and i["channel"]]
        base = f"/sys/class/ieee80211/{phy}/device"
        res.append({"phy": phy, "ap": ap, "channels": chans,
                    "driver": os.path.basename(os.path.realpath(base + "/driver")) if os.path.exists(base) else "?",
                    "bus": os.path.basename(os.path.realpath(base + "/subsystem")) if os.path.exists(base) else "?",
                    "ap_plus_client": bool(both), "shared_channels": max((c["channels"] for c in both), default=0),
                    "ifaces": ifaces, "client": link[0] if link else None,
                    "own_ap": [i["name"] for i in ifaces if i["type"] == "AP"]})
    return res


def pick_channel(r, band):
    pref = PREF_5 if band == "5" else PREF_24
    for ch in pref:
        if ch in r["channels"][band]:
            return ch
    return None


def plan(want="auto", only=None):
    """Which radio, band and channel should host the hotspot? {ok, phy, band, channel, shared, why[], options[]}"""
    why, options = [], []
    for r in radios():
        if only and r["phy"] != only:
            continue
        label = f"{r['phy']} ({r['driver']}, {'USB' if r['bus'] == 'usb' else r['bus']})"
        if not r["ap"]:
            why.append(f"{label}: can't act as an access point")
            continue
        free = r["client"] is None
        for band in (["2.4", "5"] if want == "auto" else [want]):
            if free:
                ch = pick_channel(r, band)
                if ch:
                    options.append({"phy": r["phy"], "band": band, "channel": ch, "shared": False,
                                    "score": (1 if r["bus"] == "usb" else 2) + (5 if band == "5" else 10) + 20, "label": label})
                else:
                    why.append(f"{label}: no channel on {band} GHz where the regulatory rules allow an access point"
                               + (" (set the country: sysmedic-hotspot setup)" if band == "5" else ""))
            else:
                cl = r["client"]
                if not r["ap_plus_client"]:
                    why.append(f"{label}: is the internet link now, and can't also host an access point")
                    break
                cband = "2.4" if cl["mhz"] < 3000 else "5"
                if r["shared_channels"] < 2:        # one channel for both: the hotspot follows the internet link
                    if band != cband and want != "auto":
                        why.append(f"{label}: shares one channel with the internet link, which is on {cband} GHz")
                        continue
                    if band != cband:
                        continue
                    if cl["channel"] not in r["channels"][cband]:
                        why.append(f"{label}: the internet link is on channel {cl['channel']} ({cband} GHz), where an access point "
                                   "isn't allowed here (regulatory rules)")
                        continue
                    options.append({"phy": r["phy"], "band": cband, "channel": cl["channel"], "shared": True,
                                    "score": (5 if cband == "5" else 10), "label": label})
                else:
                    ch = pick_channel(r, band)
                    if ch:
                        options.append({"phy": r["phy"], "band": band, "channel": ch, "shared": False, "score": 10 + (5 if band == "5" else 10),
                                        "label": label})
    options.sort(key=lambda o: -o["score"])
    if not options:
        return {"ok": False, "why": why or ["no Wi-Fi radio found"], "options": []}
    best = options[0]
    return dict(best, ok=True, why=why, options=options)
