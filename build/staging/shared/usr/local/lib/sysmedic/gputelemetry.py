"""gputelemetry — GPU/CPU telemetry from the kernel (sysfs), no vendor tools.

Intel (i915/xe): clock from gt_cur_freq_mhz, busy from RC6 residency. AMD (amdgpu): gpu_busy_percent, sclk,
hwmon temperature and power. nouveau: hwmon temperature. CPU: package temperature (coretemp/k10temp), package
power (RAPL), load and clock. Every field is optional: what the machine doesn't expose is None.
"""
import glob
import os
import re
import time


def _read(path, default=None):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def _num(path, scale=1.0):
    v = _read(path)
    try:
        return float(v) * scale
    except (TypeError, ValueError):
        return None


def gpu_cards():
    """[(card path, driver)] for real GPUs (not simpledrm), primary first."""
    out = []
    for c in sorted(glob.glob("/sys/class/drm/card[0-9]")):
        drv = os.path.basename(os.path.realpath(os.path.join(c, "device/driver")))
        if drv in ("i915", "xe", "amdgpu", "radeon", "nouveau", "nvidia"):
            out.append((c, drv))
    return out


def _hwmon(dev, names):
    for h in glob.glob(os.path.join(dev, "hwmon/hwmon*")) + glob.glob("/sys/class/hwmon/hwmon*"):
        if _read(os.path.join(h, "name")) in names:
            yield h


class Sampler:
    """Call sample() about once a second; each call returns one dict of readings."""

    def __init__(self):
        self.cards = gpu_cards()
        self.card, self.driver = self.cards[0] if self.cards else (None, None)
        self.prev = {}
        self.t0 = time.time()

    def _delta(self, key, value, now):
        old = self.prev.get(key)
        self.prev[key] = (value, now)
        if old is None or value is None:
            return None
        dv, dt = value - old[0], now - old[1]
        return (dv, dt) if dt > 0 else None

    def gpu(self, now):
        r = {"gpu_mhz": None, "gpu_max_mhz": None, "gpu_busy": None, "gpu_temp": None, "gpu_watts": None}
        if not self.card:
            return r
        c, dev = self.card, os.path.join(self.card, "device")
        if self.driver in ("i915", "xe"):
            r["gpu_mhz"] = _num(f"{c}/gt_cur_freq_mhz") or _num(f"{c}/gt/gt0/rps_cur_freq_mhz") or \
                _num(f"{dev}/tile0/gt0/freq0/cur_freq")
            r["gpu_max_mhz"] = _num(f"{c}/gt_RP0_freq_mhz") or _num(f"{c}/gt_max_freq_mhz") or \
                _num(f"{dev}/tile0/gt0/freq0/rp0_freq")
            rc6 = _num(f"{c}/power/rc6_residency_ms") or _num(f"{c}/gt/gt0/rc6_residency_ms") or \
                _num(f"{dev}/tile0/gt0/gtidle/idle_residency_ms")
            d = self._delta("rc6", rc6, now)
            if d:
                r["gpu_busy"] = max(0.0, min(100.0, 100.0 - d[0] / (d[1] * 1000) * 100))
        elif self.driver in ("amdgpu", "radeon"):
            r["gpu_busy"] = _num(f"{dev}/gpu_busy_percent")
            sclk = _read(f"{dev}/pp_dpm_sclk", "")
            cur = re.search(r"(\d+)Mhz \*", sclk)
            levels = [int(x) for x in re.findall(r"(\d+)Mhz", sclk)]
            r["gpu_mhz"] = float(cur.group(1)) if cur else None
            r["gpu_max_mhz"] = float(max(levels)) if levels else None
        for h in _hwmon(dev, ("amdgpu", "radeon", "nouveau")):
            r["gpu_temp"] = _num(f"{h}/temp1_input", 0.001)
            r["gpu_watts"] = _num(f"{h}/power1_average", 1e-6) or _num(f"{h}/power1_input", 1e-6)
            break
        return r

    def cpu(self, now):
        r = {"cpu_temp": None, "cpu_watts": None, "cpu_busy": None, "cpu_mhz": None, "throttle": None}
        for h in _hwmon("/nonexistent", ("coretemp", "k10temp", "zenpower")):
            temps = [_num(p, 0.001) for p in glob.glob(f"{h}/temp*_input")]
            temps = [t for t in temps if t]
            if temps:
                r["cpu_temp"] = max(temps)
                break
        energy = _num("/sys/class/powercap/intel-rapl:0/energy_uj")
        d = self._delta("rapl", energy, now)
        if d and d[0] >= 0:
            r["cpu_watts"] = d[0] / 1e6 / d[1]
        stat = _read("/proc/stat", "").splitlines()
        if stat:
            f = [float(x) for x in stat[0].split()[1:]]
            idle, total = f[3] + (f[4] if len(f) > 4 else 0), sum(f)
            d1, d2 = self._delta("idle", idle, now), self._delta("total", total, now)
            if d1 and d2 and d2[0] > 0:
                r["cpu_busy"] = 100.0 * (1 - d1[0] / d2[0])
        mhz = [_num(p, 0.001) for p in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq")]
        mhz = [m for m in mhz if m]
        r["cpu_mhz"] = sum(mhz) / len(mhz) if mhz else None
        thr = [_num(p) for p in glob.glob("/sys/devices/system/cpu/cpu*/thermal_throttle/package_throttle_count")]
        thr = [t for t in thr if t is not None]
        r["throttle"] = max(thr) if thr else None
        return r

    def sample(self):
        now = time.time()
        r = {"t": round(now - self.t0, 1)}
        r.update(self.gpu(now))
        r.update(self.cpu(now))
        return r


def gpu_hang_lines(since_text=""):
    """Kernel messages that mean the GPU hung or was reset (new since since_text, the earlier dmesg)."""
    import subprocess
    try:
        out = subprocess.run(["dmesg"], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    if since_text and out.startswith(since_text[:2000]):
        out = out[len(since_text):]
    rx = re.compile(r"GPU HANG|gpu hang|ring \S+ timeout|GPU reset|amdgpu.*(timeout|fault|reset)|nouveau.*(fault|timeout)|"
                    r"i915.*(reset|wedged|error)|\*ERROR\* .*(hang|timeout)", re.I)
    return [l for l in out.splitlines() if rx.search(l)][-8:]
