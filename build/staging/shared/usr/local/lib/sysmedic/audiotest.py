#!/usr/bin/env python3
"""audiotest — speaker test with music, made on the spot (nothing downloaded or bundled, all public domain).

Four Beethoven pieces, each chosen to show a different fault, then a sweep:
  ode        Ode to Joy: the tune on the left speaker, then the right, then both with bass (a dead or weak side)
  moonlight  Moonlight Sonata, opening: slow low octaves under soft triplets (rattle and buzz in the bass)
  elise      Für Elise: quick high notes (harsh or crackling treble)
  fifth      Symphony No. 5, opening: loud, sudden attacks (distortion at high volume)
  sweep      40 Hz → 12 kHz: the frequency a loose part buzzes at

  audiotest.py                          on a console: pick tracks, change the volume while they play
  audiotest.py --track moonlight,fifth  just those (no questions)
  audiotest.py --all --volume 60        the whole programme at 60% (what the phone dashboard and the AI run)

While playing: ↑/↓ or +/− volume, m mute, space next track, q stop.
"""
import math
import os
import re
import select
import struct
import subprocess
import sys
import tempfile
import termios
import tty
import wave

RATE = 44100
NOTE = {n: 440 * 2 ** ((i - 9) / 12) for i, n in enumerate("C C# D D# E F F# G G# A A# B".split())}
FLAT = {"Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"}


def freq(name):
    n, octave = name[:-1], int(name[-1])
    return NOTE[FLAT.get(n, n)] * 2 ** (octave - 4)


_cache = {}


def tone(f, secs, amp, bright=1.0, decay=2.6):
    """A piano-like note: a few harmonics, a quick attack and an exponential decay. Cached: tunes repeat notes."""
    key = (round(f, 3), round(secs, 4), amp, bright, decay)
    if key not in _cache:
        n, w = int(RATE * secs), 2 * math.pi * f / RATE
        release = min(n, int(RATE * 0.02))
        out = [0.0] * n
        for i in range(n):
            t = i / RATE
            env = min(1.0, t / 0.008) * math.exp(-decay * t / max(secs, 0.2))
            if i > n - release:
                env *= (n - i) / release                       # no click at the end of a note
            out[i] = amp * env * (math.sin(w * i) + 0.35 * bright * math.sin(2 * w * i) + 0.12 * bright * math.sin(3 * w * i)) / 1.47
        _cache[key] = out
    return _cache[key]


def mix(dst, src, at):
    end = at + len(src)
    if end > len(dst):
        dst.extend([0.0] * (end - len(dst)))
    for i, x in enumerate(src):
        dst[at + i] += x


def voices(events, amp=0.5, bright=1.0, decay=2.6):
    """events: [(start beat, length in beats, [notes]), …] with a beat in seconds as the first item."""
    beat, events = events[0], events[1:]
    out = []
    for start, length, notes in events:
        for nm in notes:
            mix(out, tone(freq(nm), length * beat, amp, bright, decay), int(start * beat * RATE))
    return out


def sequence(notes, beat):
    """[(note or chord, beats), …] one after another → events."""
    ev, t = [beat], 0.0
    for nm, beats in notes:
        if nm:
            ev.append((t, beats, nm if isinstance(nm, list) else [nm]))
        t += beats
    return ev


# ── The pieces ─────────────────────────────────────────────────────────────

def ode():
    a = [("E4", 1), ("E4", 1), ("F4", 1), ("G4", 1), ("G4", 1), ("F4", 1), ("E4", 1), ("D4", 1),
         ("C4", 1), ("C4", 1), ("D4", 1), ("E4", 1), ("E4", 1.5), ("D4", .5), ("D4", 2)]
    b = a[:12] + [("D4", 1.5), ("C4", .5), ("C4", 2)]
    c = [("D4", 1), ("D4", 1), ("E4", 1), ("C4", 1), ("D4", 1), ("E4", .5), ("F4", .5), ("E4", 1), ("C4", 1),
         ("D4", 1), ("E4", .5), ("F4", .5), ("E4", 1), ("D4", 1), ("C4", 1), ("D4", 1), ("G3", 2)]
    bass = {"C": "C2", "D": "G2", "E": "C3", "F": "F2", "G": "G2"}
    left, right = voices(sequence(a, .42), .55), voices(sequence(b, .42), .55)
    both = voices(sequence([([n, bass[n[0]]], d) for n, d in c + b], .42), .5)
    gap = [0.0] * int(RATE * .6)
    return [("LEFT speaker only: the tune should come only from the left", left + gap, [0.0] * (len(left) + len(gap))),
            ("RIGHT speaker only: the tune should come only from the right", [0.0] * (len(right) + len(gap)), right + gap),
            ("BOTH speakers, with bass: listen for buzz, rattle or harshness", both, both)]


def moonlight():
    """Sonata Op. 27 No. 2, first movement, bars 1-5: triplets over octaves in the bass."""
    t = 0.3                                       # one triplet quaver; a bar is 12 of them
    bars = [(["G#3", "C#4", "E4"] * 4, [(["C#2", "C#3"], 12)]),
            (["G#3", "C#4", "E4"] * 4, [(["B1", "B2"], 12)]),
            (["A3", "C#4", "E4"] * 2 + ["A3", "D4", "F#4"] * 2, [(["A1", "A2"], 6), (["F#1", "F#2"], 6)]),
            (["G#3", "C4", "F#4", "G#3", "C#4", "E4", "G#3", "C#4", "D#4", "F#3", "C4", "D#4"], [(["G#1", "G#2"], 12)]),
            (["G#3", "C#4", "E4"] * 4, [(["C#2", "C#3"], 12)])]
    ev, pos = [t], 0
    for triplets, bass in bars:
        for i, nm in enumerate(triplets):
            ev.append((pos + i, 2.2, [nm]))       # let each note ring into the next, like the pedal
        b = pos
        for notes, length in bass:
            ev.append((b, length, notes))
            b += length
        pos += 12
    ev.append((pos, 14, ["C#2", "C#3", "G#3", "C#4", "E4"]))
    out = voices(ev, .32, bright=.7, decay=1.4)
    return [("Moonlight Sonata (opening): deep, slow bass. Listen for rattle or buzz under the low notes", out, out)]


def elise():
    """Für Elise, WoO 59: the opening phrase twice (semiquavers)."""
    s = .14
    turn = [("E5", 1), ("D#5", 1), ("E5", 1), ("D#5", 1), ("E5", 1), ("B4", 1), ("D5", 1), ("C5", 1)]
    a = [(["A4", "A2"], 1), ("E3", 1), ("A3", 1), ("C4", 1), ("E4", 1), ("A4", 1)]
    b1 = [(["B4", "E2"], 1), ("E3", 1), ("G#3", 1), ("E4", 1), ("G#4", 1), ("B4", 1)]
    c = [(["C5", "A2"], 1), ("E3", 1), ("A3", 1), ("E4", 1)]
    b2 = [(["B4", "E2"], 1), ("E3", 1), ("G#3", 1), ("E4", 1), ("C5", 1), ("B4", 1)]
    end = [(["A4", "A2"], 1), ("E3", 1), ("A3", 1), (None, 3)]
    notes = turn + a + b1 + c + turn + a + b2 + end
    out = voices([s] + [(st, max(d * 2.5, 1.5), nm) for st, d, nm in sequence(notes, s)[1:]], .5, bright=1.3)
    return [("Für Elise: quick high notes. Listen for harsh, crackling or muffled treble", out, out)]


def fifth():
    """Symphony No. 5, Op. 67: the opening four-note motto, twice, then a loud chord."""
    q = .15
    g = ["G2", "G3", "G4"]
    eb = ["Eb2", "Eb3", "Eb4"]
    f = ["F2", "F3", "F4"]
    d = ["D2", "D3", "D4"]
    notes = [(None, 1), (g, 1), (g, 1), (g, 1), (eb, 11), (None, 3), (f, 1), (f, 1), (f, 1), (d, 15), (None, 4),
             (["C2", "C3", "G3", "Eb4", "C5"], 14)]
    out = voices(sequence(notes, q), .42, bright=1.8, decay=1.0)
    return [("Symphony No. 5 (opening): loud and sudden. Listen for distortion or rattle on the big notes", out, out)]


def sweep_track(secs=16, f0=40, f1=12000, amp=0.5):
    n, k = int(RATE * secs), math.log(f1 / f0) / secs
    s = [amp * min(1, i / 2000, (n - i) / 2000) * math.sin(2 * math.pi * f0 * (math.exp(k * i / RATE) - 1) / k) for i in range(n)]
    return [("Sweep from deep bass to high treble (16 s): a loose part rattles or buzzes at some point", s, s)]


TRACKS = [("ode", "Ode to Joy", "left, right, then both: a dead or weak side", ode),
          ("moonlight", "Moonlight Sonata", "deep slow bass: rattle, buzz", moonlight),
          ("elise", "Für Elise", "quick high notes: harsh or crackling treble", elise),
          ("fifth", "Symphony No. 5", "loud sudden notes: distortion at volume", fifth),
          ("sweep", "Frequency sweep", "40 Hz → 12 kHz: where a loose part buzzes", sweep_track)]


def write(path, left, right, peak=0.85):
    """Stereo WAV, scaled so the loudest moment is at `peak`: chords add up, and clipping would sound like a
    damaged speaker."""
    if len(right) < len(left):
        right = right + [0.0] * (len(left) - len(right))
    top = max(max(map(abs, left), default=0), max(map(abs, right), default=0))
    if top > 0:
        k = peak / top
        left, right = [x * k for x in left], [x * k for x in right]
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<hh", int(max(-1, min(1, l)) * 32000), int(max(-1, min(1, r)) * 32000))
                               for l, r in zip(left, right)))


# ── Volume ─────────────────────────────────────────────────────────────────

def controls():
    out = subprocess.run(["amixer", "scontrols"], capture_output=True, text=True).stdout
    return re.findall(r"'([^']+)',\d+", out)


class Volume:
    """The volume the engineer controls is Master (or Speaker/PCM when there's no Master); the rest stay at full."""

    def __init__(self, level):
        have = controls()
        self.ctl = next((c for c in ("Master", "Speaker", "PCM") if c in have), None)
        for c in ("Speaker", "PCM", "Headphone", "Front", "Master"):
            if c in have and c != self.ctl:
                self.amixer(c, "100%")
                self.amixer(c, "unmute")
        self.level, self.muted = level, False
        self.set(level)

    @staticmethod
    def amixer(ctl, arg):
        # One setting per call: "sset Master 30% unmute" fails as a whole on a control without a mute switch
        subprocess.run(["amixer", "-q", "sset", ctl, arg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def set(self, level):
        self.level = max(0, min(100, level))
        if self.ctl:
            # Muting by level too: not every card's volume control has a mute switch
            self.amixer(self.ctl, "0%" if self.muted else f"{self.level}%")
            self.amixer(self.ctl, "mute" if self.muted else "unmute")

    def toggle_mute(self):
        self.muted = not self.muted
        self.set(self.level)

    def bar(self):
        if self.muted:
            return "muted"
        full = self.level // 10
        return "█" * full + "·" * (10 - full) + f" {self.level}%"


# ── Playing ────────────────────────────────────────────────────────────────

def keys(fd, timeout):
    """One key press (arrow keys as 'up'/'down'), or None."""
    if not select.select([fd], [], [], timeout)[0]:
        return None
    ch = os.read(fd, 1)
    if ch == b"\x1b":
        seq = os.read(fd, 2) if select.select([fd], [], [], 0.05)[0] else b""
        return {b"[A": "up", b"[B": "down"}.get(seq, "esc")
    return ch.decode(errors="replace")


FAILURES = []      # what aplay reported when it could not play (it used to be thrown away)


def diagnose():
    """Say what sound hardware the kernel found: a card that exists but is HDMI-only, or has no driver, is the usual reason for silence."""
    cards = subprocess.run(["aplay", "-l"], capture_output=True, text=True).stdout
    print("  Sound hardware the kernel found:")
    for l in cards.splitlines():
        if l.startswith("card"):
            print("    " + l.strip())
    names = cards.lower()
    if "hdmi" in names and not any(k in names for k in ("analog", "alc", "realtek", "codec", "speaker")):
        print("  Only HDMI/DisplayPort audio is listed: no driver for the built-in speakers or headphone jack was loaded.")
    log = subprocess.run("dmesg 2>/dev/null | grep -i -E 'snd|hda|asoc|sof-audio|audio codec|firmware.*(audio|sof)' | tail -12",
                         shell=True, capture_output=True, text=True).stdout.strip()
    if log:
        print("  Kernel messages about sound:")
        for l in log.splitlines():
            print("    " + l[:150])
    else:
        print("  The kernel logged nothing about sound at all.")


def play(path, vol, interactive):
    """Play one file; returns 'next', 'quit' or 'done'."""
    p = subprocess.Popen(["aplay", "-q", path], stderr=subprocess.PIPE, text=True)
    if not interactive:
        _, err = p.communicate()
        if p.returncode:
            FAILURES.append((err or "").strip().splitlines()[-1:] or [f"aplay exit {p.returncode}"])
        return "done"
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
        while p.poll() is None:
            sys.stdout.write(f"\r       volume {vol.bar():<16} ↑/↓ volume · m mute · space next · q stop ")
            sys.stdout.flush()
            k = keys(fd, 0.2)
            if k in ("up", "+", "="):
                vol.set(vol.level + 5)
            elif k in ("down", "-", "_"):
                vol.set(vol.level - 5)
            elif k in ("m", "M"):
                vol.toggle_mute()
            elif k in (" ", "n", "N"):
                p.terminate()
                return "next"
            elif k in ("q", "Q", "esc"):
                p.terminate()
                return "quit"
        if p.returncode:
            FAILURES.append((p.stderr.read() or "").strip().splitlines()[-1:] or [f"aplay exit {p.returncode}"])
        return "done"
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        sys.stdout.write("\r" + " " * 78 + "\r")


def run(names, vol, interactive):
    tmp = tempfile.mkdtemp(prefix="sysmedic-audio-")
    played = []
    try:
        for key in names:
            _, title, _, build = next(t for t in TRACKS if t[0] == key)
            print(f"  ► {title}" + (" (preparing…)" if interactive else ""), flush=True)
            parts = build()
            for i, (what, left, right) in enumerate(parts):
                path = os.path.join(tmp, f"{key}-{i}.wav")
                write(path, left, right)
                print(f"     {what}", flush=True)
                r = play(path, vol, interactive)
                os.unlink(path)
                if r == "quit":
                    return played
                if r == "next":
                    break
            played.append(key)
    except KeyboardInterrupt:
        print("\n  Stopped.")
    finally:
        for f in os.listdir(tmp):
            os.unlink(os.path.join(tmp, f))
        os.rmdir(tmp)
    return played


def main():
    args = sys.argv[1:]
    if args[:1] in (["-h"], ["--help"]):
        print(__doc__)
        return 0
    level, names = 80, None
    if "--volume" in args:
        try:
            level = int(args[args.index("--volume") + 1].rstrip("%"))
        except (IndexError, ValueError):
            sys.exit("--volume needs a number (0-100)")
    if "--all" in args:
        names = [t[0] for t in TRACKS]
    if "--track" in args:
        try:
            names = [n.strip().lower() for n in args[args.index("--track") + 1].split(",") if n.strip()]
        except IndexError:
            sys.exit("--track needs a name: " + ", ".join(t[0] for t in TRACKS))
        bad = [n for n in names if n not in {t[0] for t in TRACKS}]
        if bad:
            sys.exit(f"No track '{bad[0]}'. Tracks: " + ", ".join(t[0] for t in TRACKS))
    if subprocess.run(["aplay", "-l"], capture_output=True, text=True).stdout.count("card") == 0:
        print("  No sound card found.")
        return 1
    interactive = sys.stdin.isatty() and sys.stdout.isatty()
    vol = Volume(level)
    diagnose()
    if not vol.ctl:
        print("  (No volume control SysMedic recognises on the sound hardware: playing at its current level."
              " That usually means no built-in speaker driver.)")
    print("  Speaker test with music: Beethoven (synthesised here, nothing downloaded) and a frequency sweep.")
    if names is None and not interactive:
        names = [t[0] for t in TRACKS]
    if names is not None:
        print(f"  Volume {level}%. Stay near the laptop and listen.\n")
        played = run(names, vol, interactive)
    else:
        played = []
        while True:
            print()
            for i, (_, title, why, _) in enumerate(TRACKS, 1):
                print(f"   {i}  {title:<20} {why}")
            print("   a  All of them, in order        q  Done")
            try:
                a = input(f"  ❯ Play which? (volume {vol.level}%: change it while it plays) ").strip().lower()
            except EOFError:
                break
            if a in ("q", "0", ""):
                break
            picks = [t[0] for t in TRACKS] if a == "a" else \
                [TRACKS[int(c) - 1][0] for c in re.findall(r"\d", a) if 1 <= int(c) <= len(TRACKS)]
            if not picks:
                print("  Choose a number, a or q.")
                continue
            print()
            played += run(picks, vol, interactive)
    if FAILURES:
        print(f"\n  aplay could NOT play {len(FAILURES)} piece(s): {FAILURES[0][0]}")
        print("  Nothing came out of the speakers; the built-in sound hardware is not working in this Linux.")
        return 2
    if played:
        print(f"\n  Played: {', '.join(played)} (volume {vol.level}%).")
        print("  Note what you heard in the job report, e.g.: sysmedic-note \"speakers: right side weak, rattle on the Moonlight bass\"")
    return 0


if __name__ == "__main__":
    sys.exit(main())
