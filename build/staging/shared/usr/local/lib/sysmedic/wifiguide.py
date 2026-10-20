"""Which Wi-Fi radio should do which job? Shown on the boot Wi-Fi screen, in `wifi`, and in the hotspot guide.

The setup that works in the field: a USB Wi-Fi dongle carries the internet link (the "backhaul"), the computer's own
PCIe/built-in Wi-Fi hosts the engineer's phone hotspot, and both stay on 2.4 GHz (no regulatory or DFS surprises, and
every phone and dongle can do it)."""
import wifilib

B, D, G, Y, N = "\033[1m", "\033[2m", "\033[0;32m", "\033[1;33m", "\033[0m"


def _name(r):
    ifs = [i["name"] for i in r["ifaces"] if i["type"] == "managed"]
    return ifs[0] if ifs else r["phy"]


def roles(rs=None):
    """{'backhaul': radio, 'hotspot': radio} when there is a USB dongle and a built-in radio, else {}."""
    rs = wifilib.radios() if rs is None else rs
    usb = [r for r in rs if r["bus"] == "usb"]
    inner = [r for r in rs if r["bus"] != "usb" and r["ap"]]
    return {"backhaul": usb[0], "hotspot": inner[0]} if usb and inner else {}


def panel(rs=None):
    """The guidance text, as a list of lines."""
    rs = wifilib.radios() if rs is None else rs
    out = []
    rl = roles(rs)
    if rl:
        bk, hs = rl["backhaul"], rl["hotspot"]
        out += [f"  {B}Two Wi-Fi radios: give each one a job{N}",
                f"    {G}Internet{N}  -> the {B}USB dongle{N} ({bk['driver']}, {_name(bk)}). The network list below uses it.",
                f"    {G}Hotspot{N}   -> the {B}built-in Wi-Fi{N} ({hs['driver']}, {_name(hs)}). Start it later: menu H, option 1.",
                f"    {B}Keep everything on 2.4 GHz.{N} Join a 2.4 GHz network (a dual-band router often has a separate \"-2G\" name),"
                f" and the hotspot uses 2.4 GHz too: the most reliable choice, and it works with every phone."]
        out.append(f"    {D}While you choose, SysMedic sets the built-in radio aside so the list is the dongle's; the hotspot takes it from there.{N}")
    elif len(rs) == 1 and rs[0]["bus"] == "usb":
        out += [f"  {B}One Wi-Fi radio (USB dongle){N}: it carries the internet. For a phone hotspot as well you need a second radio:"
                " the computer's own Wi-Fi, or another dongle."]
    elif len(rs) == 1:
        out += [f"  {B}One Wi-Fi radio (built in){N}: it can join a network or host the phone hotspot, not both comfortably.",
                f"    For the best setup, plug in a {B}USB Wi-Fi dongle{N} for the internet and keep the built-in radio for the hotspot (2.4 GHz)."]
    return out


def reserve(rs=None):
    """Set the hotspot's radio aside from NetworkManager so the network picker can only use the dongle. Returns its name or ''."""
    import subprocess
    rl = roles(rs)
    if not rl:
        return ""
    name = _name(rl["hotspot"])
    subprocess.run(["nmcli", "device", "set", name, "managed", "no"], capture_output=True)
    return name


def show():
    for line in panel():
        print(line)
    return 0


if __name__ == "__main__":
    import sys
    if "--reserve" in sys.argv:
        reserve()
        sys.exit(0)
    sys.exit(show())
