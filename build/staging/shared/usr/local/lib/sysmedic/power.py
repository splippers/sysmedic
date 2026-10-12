"""power — the laptop's batteries, read from the kernel (no tools needed). Shared by the rescue menu and the dashboard."""
from pathlib import Path

STATES = {"charging": "charging", "discharging": "on battery", "full": "full", "not charging": "plugged in, not charging"}


def battery():
    """[{name, percent, state, health, cycles}], one per battery; health is today's full capacity vs. the design's."""
    out = []
    for b in sorted(Path("/sys/class/power_supply").glob("BAT*")):
        rd = lambda n: (b / n).read_text().strip() if (b / n).exists() else ""  # noqa: E731
        try:
            full = rd("energy_full") or rd("charge_full")
            design = rd("energy_full_design") or rd("charge_full_design")
            health = round(int(full) * 100 / int(design)) if full.isdigit() and design.isdigit() and int(design) else None
            out.append({"name": b.name, "percent": int(rd("capacity")) if rd("capacity").isdigit() else None,
                        "state": rd("status").lower(), "health": health,
                        "cycles": int(rd("cycle_count")) if rd("cycle_count").isdigit() and int(rd("cycle_count")) > 0 else None})
        except OSError:
            continue
    return out


def summary(b):
    """'Battery 70% · charging · health 85% (412 cycles)', and how worried to be: ok / warning / critical."""
    parts = ["Battery" + (f" {b['percent']}%" if b["percent"] is not None else "")]
    if b["state"]:
        parts.append(STATES.get(b["state"], b["state"]))
    if b["health"] is not None:
        parts.append(f"health {b['health']}%" + (f" ({b['cycles']} cycles)" if b["cycles"] else ""))
    sev = "ok"
    if b["health"] is not None and b["health"] < 80:
        sev = "warning"                                  # noticeably worn
    if (b["health"] is not None and b["health"] < 60) or (b["percent"] is not None and b["percent"] <= 15
                                                          and b["state"] == "discharging"):
        sev = "critical"                                 # replace it / plug in now
    elif b["percent"] is not None and b["percent"] <= 30 and b["state"] == "discharging":
        sev = "warning"
    return " · ".join(parts), sev
