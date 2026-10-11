"""The machine's GPUs, and how to steer the graphics tests to one of them.

Hybrid laptops (Intel + NVIDIA/AMD) drive the screen from the integrated GPU; the discrete one only renders when
a program asks for it. Mesa's OpenGL follows DRI_PRIME=pci-DDDD_BB_DD_F, Vulkan follows MESA_VK_DEVICE_SELECT
(Mesa's device-select layer) and VA-API takes a render node, so a test can run on either GPU while the picture
still appears on the laptop's screen.

GPU numbers are 1-based: 1 is the GPU driving the display (boot VGA), then the others in PCI order.
"""
import glob
import os
import re
import subprocess

REAL = ("i915", "xe", "amdgpu", "radeon", "nouveau", "nvidia")


def _read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def _name(slot):
    try:
        out = subprocess.run(["lspci", "-mm", "-s", slot], capture_output=True, text=True, timeout=5).stdout
        f = re.findall(r'"([^"]*)"', out)
        if len(f) >= 3:
            vendor = re.sub(r"\b(Corporation|Inc\.?|Co\.?|Ltd\.?|\[AMD/ATI\])", "", f[1]).strip()
            model = re.sub(r".*\[(.+)\].*", r"\1", f[2])        # "TU117M [GeForce GTX 1650 Mobile / Max-Q]" → the marketing name
            return f"{vendor} {model}".strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return slot


def list_gpus():
    """[{n, card, slot, driver, name, vendor, device, render, boot_vga, display}] — real GPUs only."""
    found = []
    for card in sorted(glob.glob("/sys/class/drm/card[0-9]*")):
        if "-" in os.path.basename(card):
            continue
        dev = os.path.realpath(os.path.join(card, "device"))
        driver = os.path.basename(os.path.realpath(os.path.join(dev, "driver")))
        if driver not in REAL:
            continue
        slot = os.path.basename(dev)
        render = sorted(glob.glob(os.path.join(dev, "drm", "renderD*")))
        found.append({
            "card": card, "slot": slot, "driver": driver, "name": _name(slot),
            "vendor": _read(os.path.join(dev, "vendor")).replace("0x", ""),
            "device": _read(os.path.join(dev, "device")).replace("0x", ""),
            "render": "/dev/dri/" + os.path.basename(render[0]) if render else "",
            "boot_vga": _read(os.path.join(dev, "boot_vga")) == "1",
            "display": any(_read(c + "/status") == "connected" for c in glob.glob(card + "-*")),
        })
    found.sort(key=lambda g: (not g["boot_vga"], not g["display"], g["slot"]))
    for i, g in enumerate(found, 1):
        g["n"] = i
        g["label"] = f"{i}: {g['name']} ({g['driver']}{', drives the screen' if g['display'] or g['boot_vga'] else ''})"
    return found


def pick(sel, gpus=None):
    """sel: '' / 'auto' (the display GPU), a number, or a PCI slot. Returns the GPU dict or raises ValueError."""
    gpus = list_gpus() if gpus is None else gpus
    if not gpus:
        raise ValueError("no GPU with a working driver found")
    sel = str(sel or "").strip()
    if sel in ("", "auto", "0"):
        return gpus[0]
    for g in gpus:
        if sel == str(g["n"]) or sel in (g["slot"], g["slot"].split(":", 1)[-1]):
            return g
    raise ValueError(f"no GPU {sel!r}; this machine has: " + "; ".join(g["label"] for g in gpus))


def env_for(g):
    """Environment that makes OpenGL, Vulkan and VA-API programs use GPU g."""
    dom, bus, rest = g["slot"].split(":")
    devfn = rest.replace(".", "_")
    env = {"DRI_PRIME": f"pci-{dom}_{bus}_{devfn}",
           "MESA_VK_DEVICE_SELECT": f"{g['vendor']}:{g['device']}",
           "SYSMEDIC_GPU": str(g["n"]), "SYSMEDIC_GPU_CARD": g["card"]}
    if g["render"]:
        env["SYSMEDIC_GPU_RENDER"] = g["render"]
    if g["driver"] == "nvidia":                       # the proprietary driver's own offload switch
        env.update({"__NV_PRIME_RENDER_OFFLOAD": "1", "__GLX_VENDOR_LIBRARY_NAME": "nvidia", "__VK_LAYER_NV_optimus": "NVIDIA_only"})
    return env


def from_env():
    """The GPU chosen for this run (SYSMEDIC_GPU), or the display GPU."""
    try:
        return pick(os.environ.get("SYSMEDIC_GPU", ""))
    except ValueError:
        return None
