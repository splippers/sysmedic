#!/usr/bin/env python3
"""audiotest — an extended speaker test with music, made on the spot (nothing downloaded or bundled).

Beethoven's "Ode to Joy" (public domain), synthesised here: melody on the left speaker, then the right, then
the whole tune with a bass line on both; then a slow 40 Hz → 12 kHz sweep. Richer and longer than two beeps:
drop damage shows up as rattle, buzz, distortion, a weak or dead side, or a missing bass/treble range.
"""
import math
import os
import struct
import subprocess
import sys
import tempfile
import wave

RATE = 44100
NOTE = {n: 440 * 2 ** ((i - 9) / 12) for i, n in enumerate("C C# D D# E F F# G G# A A# B".split())}


def freq(name):
    n, octave = name[:-1], int(name[-1])
    return NOTE[n] * 2 ** (octave - 4)


# (note, beats); the tune's four phrases
PHRASE_A = [("E4", 1), ("E4", 1), ("F4", 1), ("G4", 1), ("G4", 1), ("F4", 1), ("E4", 1), ("D4", 1),
            ("C4", 1), ("C4", 1), ("D4", 1), ("E4", 1), ("E4", 1.5), ("D4", .5), ("D4", 2)]
PHRASE_B = PHRASE_A[:12] + [("D4", 1.5), ("C4", .5), ("C4", 2)]
PHRASE_C = [("D4", 1), ("D4", 1), ("E4", 1), ("C4", 1), ("D4", 1), ("E4", .5), ("F4", .5), ("E4", 1), ("C4", 1),
            ("D4", 1), ("E4", .5), ("F4", .5), ("E4", 1), ("D4", 1), ("C4", 1), ("D4", 1), ("G3", 2)]
BASS = {"C": "C2", "D": "G2", "E": "C3", "F": "F2", "G": "G2"}
BEAT = 0.42


def tone(f, secs, amp, bright=1.0):
    """A soft piano-like note: a few harmonics with a quick attack and exponential decay."""
    n = int(RATE * secs)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / 0.01) * math.exp(-2.6 * t / max(secs, 0.2))
        s = math.sin(2 * math.pi * f * t) + 0.35 * bright * math.sin(4 * math.pi * f * t) + 0.12 * bright * math.sin(6 * math.pi * f * t)
        out.append(amp * env * s / 1.47)
    return out


def melody(phrase, with_bass=False):
    left = []
    for name, beats in phrase:
        secs = beats * BEAT
        note = tone(freq(name), secs, 0.55)
        if with_bass:
            b = tone(freq(BASS[name[0]]), secs, 0.45, bright=0.6)
            note = [x + y for x, y in zip(note, b)]
        left += note
    return left


def sweep(secs=16, f0=40, f1=12000, amp=0.5):
    n = int(RATE * secs)
    k = math.log(f1 / f0) / secs
    return [amp * min(1, i / 2000, (n - i) / 2000) * math.sin(2 * math.pi * f0 * (math.exp(k * i / RATE) - 1) / k) for i in range(n)]


def write(path, left, right):
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<hh", int(max(-1, min(1, l)) * 32000), int(max(-1, min(1, r)) * 32000))
                               for l, r in zip(left, right)))


def main():
    for ctl in ("Master", "Speaker", "PCM", "Headphone"):
        subprocess.run(["amixer", "-q", "sset", ctl, "80%", "unmute"], stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    if subprocess.run(["aplay", "-l"], capture_output=True, text=True).stdout.count("card") == 0:
        print("  No sound card found.")
        return 1
    tmp = tempfile.mkdtemp(prefix="sysmedic-audio-")
    a, b, c = melody(PHRASE_A), melody(PHRASE_B), melody(PHRASE_C + PHRASE_B, with_bass=True)
    sw = sweep()
    parts = [("LEFT speaker only: the tune should come only from the left", a, [0.0] * len(a)),
             ("RIGHT speaker only: the tune should come only from the right", [0.0] * len(b), b),
             ("BOTH speakers, with bass: listen for buzz, rattle or harshness", c, c),
             ("Sweep from deep bass to high treble (16 s): a loose part rattles or buzzes at some point", sw, sw)]
    print("  Extended speaker test: Beethoven's 'Ode to Joy' (synthesised here), then a frequency sweep. About 45 s.")
    print("  Stay near the laptop and listen; the volume is set to 80%.\n")
    try:
        for i, (what, l, r) in enumerate(parts, 1):
            path = os.path.join(tmp, f"{i}.wav")
            write(path, l, r)
            print(f"  {i}/4  {what}", flush=True)
            subprocess.run(["aplay", "-q", path], stderr=subprocess.DEVNULL)
    except KeyboardInterrupt:
        print("\n  Stopped.")
    finally:
        for f in os.listdir(tmp):
            os.unlink(os.path.join(tmp, f))
        os.rmdir(tmp)
    print("\n  Note what you heard in the job report, e.g.: sysmedic-note \"speakers: right side weak, rattle at low bass\"")
    return 0


if __name__ == "__main__":
    sys.exit(main())
