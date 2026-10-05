#!/usr/bin/env python3
"""Rebrand an OpenCode binary as SysMedic (in place, same size, idempotent).

Changes only what's shown on screen: the logo, the prompt's example questions, the home-screen
tips (rescue tips instead of coding tips), and tool output starts fully expanded (OpenCode cuts it to
3-10 lines behind "Click to expand", which needs a mouse; the SysMedic console has none, so long
output is read with Page Up/Down instead).

OpenCode is a Bun single-file binary whose JavaScript is stored as text inside it. The logo is
a literal  {left:[4 rows],right:[4 rows]}  (big "opencode" and small "oc" marks). Each one is
replaced by an expression that builds the SysMedic logo, padded with spaces to the exact same
byte length, so nothing else in the binary moves. Logo markers, as OpenCode renders them:
  "_" shaded cell   "^" shadow half-block   "~" shadow block   (left half grey, right half white)

Usage: opencode-brand.py /path/to/opencode      (exit 0 = branded or already branded)
OpenCode is MIT-licensed; this changes only the logo shown on screen.
"""
import os
import re
import sys

MARK = b"__sysmedicLogo"
# Rows in a compact alphabet: # = full block, = = upper half, + = lower half
BIG_LEFT = ["              ", "#=== #  # #===", "===# #__# ===#", "==== ===# ===="]          # sys
BIG_RIGHT = ["              + =     ", "#=#=# #==# #==# # #===",                                  # medic (d ascender, i dot)
             "#_#_# #=== #__# # #___", "= = = ==== ==== = ===="]
SMALL_LEFT = ["    ", "#===", "===#", "===="]                                                     # s
SMALL_RIGHT = ["     ", "#=#=#", "#_#_#", "= = ="]                                                 # m

DECODE = (b'globalThis.__sysmedicLogo=globalThis.__sysmedicLogo||(s=>s.split("|").map(r=>r.replace(/[#=+]/g,'
          b'c=>c=="#"?"\\u2588":c=="="?"\\u2580":"\\u2584")))')
LOGO = re.compile(rb'\{left:\[("(?:[^"\\]|\\.)*"(?:,"(?:[^"\\]|\\.)*"){3})\],right:\[("(?:[^"\\]|\\.)*"(?:,"(?:[^"\\]|\\.)*"){3})\]\}')


def rows(r):
    s = "|".join(r)
    assert '"' not in s and "\\" not in s
    return s.encode()


def big():
    # an expression that defines the decoder (once, globally) and returns the logo object
    return b"(" + DECODE + b',{left:__sysmedicLogo("' + rows(BIG_LEFT) + b'"),right:__sysmedicLogo("' + rows(BIG_RIGHT) + b'")})'


def small():
    return b'{left:__sysmedicLogo("' + rows(SMALL_LEFT) + b'"),right:__sysmedicLogo("' + rows(SMALL_RIGHT) + b'")}'


PLACEHOLDERS = (b'{normal:["Why won\'t this PC boot?","Is this disk failing?","Explain the scan findings"],'
                b'shell:["sysmedic-scan","lsblk -f"]}')
CONNECT_TIP = b'"Repairs: unlock a partition on {highlight}Alt+F2{/highlight} first"'
TIPS = [
    "Start with the scan: ask {highlight}what's wrong with this machine?{/highlight}",
    "Windows problems? Ask for a {highlight}full Windows check-up{/highlight}: every event log, the registry and update logs",
    "Repairs need the engineer: {highlight}sysmedic-unlock /dev/X{/highlight} on console 2 (Alt+F2), with backups first",
    "BitLocker? Unlock on console 2, or from a phone: {highlight}sysmedic-win bitlocker-web{/highlight}",
    "Type {highlight}!{/highlight} first to run a command yourself (e.g. {highlight}!lsblk -f{/highlight})",
    "Hardware doubts? {highlight}sysmedic-hwtest{/highlight} tests CPU, RAM, disks, battery and more",
    "Note things for the job report with {highlight}sysmedic-note{/highlight}; build it with {highlight}sysmedic-report{/highlight}",
    "Something SysMedic should do better? {highlight}sysmedic-note --feedback{/highlight}",
    "No internet? The {highlight}offline assistant{/highlight} still works: type {highlight}sysmedic-ask{/highlight} at a prompt",
    "The guides are on the drive: {highlight}sysmedic-help{/highlight}",
]


def tips_array():
    return b"[" + b",".join(b'"' + t.replace('"', '\\"').encode() + b'"' for t in TIPS) + b"]"


def replace_span(data, start, end, new, what):
    """Replace data[start:end] with new, padded with spaces (JS whitespace) to the same length."""
    if len(new) > end - start:
        print(f"  {what}: replacement too long ({len(new)} > {end - start}), skipped", file=sys.stderr)
        return data, False
    return data[:start] + new + b" " * (end - start - len(new)) + data[end:], True


def patch_texts(data):
    done = []
    # Prompt placeholder examples
    m = re.search(rb'\{normal:\["Fix a TODO in the codebase",(?:"(?:[^"\\]|\\.)*",?)*\],shell:\[(?:"(?:[^"\\]|\\.)*",?)*\]\}', data)
    if m:
        data, ok = replace_span(data, m.start(), m.end(), PLACEHOLDERS, "prompt examples")
        ok and done.append("prompt examples")
    # "Run /connect to add an AI provider" tip (SysMedic's providers are preconfigured)
    old = b'"Run {highlight}/connect{/highlight} to add an AI provider and start coding"'
    i = data.find(old)
    if i >= 0:
        data, ok = replace_span(data, i, i + len(old), CONNECT_TIP, "connect tip")
        ok and done.append("connect tip")
    # Home-screen tips array: from its first tip to the closing bracket after the /rename tip
    i = data.find(b'["Type {highlight}@{/highlight} followed by a filename')
    j = data.find(b'"Use {highlight}/rename{/highlight} to rename the current session"]', i)
    if i >= 0 and j > i:
        end = data.find(b"]", j) + 1
        data, ok = replace_span(data, i, end, tips_array(), "tips")
        ok and done.append("tips")
    # Tool output fully expanded: the "expanded" state of each collapsible output starts true (!1 -> !0)
    n = 0
    for m in list(re.finditer(rb'\[\w+,\w+\]=\w+\(!1\),\w+=\d+,\w+=V\(\(\)=>\d+\*Math\.max\(20', data)):
        i = m.group(0).find(b"(!1)") + m.start()
        data = data[:i] + b"(!0)" + data[i + 4:]
        n += 1
    # OpenCode 2.x: the bash output's "expanded" state starts true; other tools' 4-line summaries uncut
    for m in list(re.finditer(rb'\[\w+,\w+\]=\w+\(!1\),\[\w+,\w+\]=\w+\(""\),\[\w+,\w+\]=\w+\(!1\),\w+=!1,\w+=!1,\w+=0,', data)):
        i = m.group(0).find(b"(!1)") + m.start()
        data = data[:i] + b"(!0)" + data[i + 4:]
        n += 1
    for m in list(re.finditer(rb'=(\w+)\(\(\)=>\w+\((\w+)\(\),4,4\*Math\.max\(20,\w+\.width-6\)\)\.output\)', data)):
        new = b"=" + m.group(1) + b"(()=>" + m.group(2) + b"())"
        data, ok = replace_span(data, m.start(), m.end(), new[:-1] + b" " * (m.end() - m.start() - len(new)) + b")", "tool summary")
        n += ok
    old = b'?"Click to collapse":"Click to expand"'
    k = data.count(old)
    data = data.replace(old, b'?"(full output)    ":"Click to expand"')
    if n:
        done.append(f"tool output expanded ({n} kinds)")
    if k:
        done.append("collapse label")
    return data, done


def main(path):
    data = open(path, "rb").read()
    out, n, pos = bytearray(), 0, 0
    found = [] if MARK in data else [m for m in LOGO.finditer(data) if b"\\u2588" in m.group(0)]
    if not found and MARK not in data:
        print(f"  {path}: OpenCode logo not found (new OpenCode version?)", file=sys.stderr)
    # The small logo sits right after a big one in the same statement, so the decoder is defined first.
    for m in found:
        width = len(re.findall(rb'"((?:[^"\\]|\\.)*)"', m.group(1))[1].decode("unicode_escape"))
        new = big() if width > 8 else small()
        old = m.group(0)
        if len(new) > len(old):
            print(f"{path}: SysMedic logo ({len(new)} bytes) doesn't fit the slot ({len(old)} bytes)", file=sys.stderr)
            return 1
        out += data[pos:m.start()] + new + b" " * (len(old) - len(new))
        pos, n = m.end(), n + 1
    out += data[pos:]
    assert len(out) == len(data)
    out, texts = patch_texts(bytes(out))
    assert len(out) == len(data)
    if not n and not texts:
        print(f"{path}: already SysMedic-branded" if MARK in data else f"{path}: nothing to change")
        return 0
    tmp = path + ".sysmedic-tmp"
    with open(tmp, "wb") as f:
        f.write(out)
    os.chmod(tmp, os.stat(path).st_mode)
    os.replace(tmp, path)
    print(f"{path}: SysMedic changes applied: {n} logo(s)" + (f"; {', '.join(texts)}" if texts else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
