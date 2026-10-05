#!/usr/bin/env python3
"""vm.py shot NAME | vm.py type 'text\n' | vm.py key KEY — drive QEMU via its monitor socket.
Run from the kit folder: QEMU started with -monitor unix:mon.sock,server,nowait there (see docs/BUILDING.md)."""
import os, socket, subprocess, sys, time
from PIL import Image
KIT = os.path.dirname(os.path.abspath(sys.argv[0]))
SOCK = os.path.join(KIT, 'mon.sock')
KEYS = {' ': 'spc', '\n': 'ret', '-': 'minus', '/': 'slash', '.': 'dot', '=': 'equal', ';': 'semicolon',
        ',': 'comma', "'": 'apostrophe', '\\': 'backslash', '[': 'bracket_left', ']': 'bracket_right',
        ':': 'shift-semicolon', '|': 'shift-backslash', '"': 'shift-apostrophe', '_': 'shift-minus',
        '>': 'shift-dot', '<': 'shift-comma', '&': 'shift-7', '$': 'shift-4', '*': 'shift-8', '(': 'shift-9',
        ')': 'shift-0', '~': 'shift-grave_accent', '+': 'shift-equal', '!': 'shift-1', '?': 'shift-slash',
        '{': 'shift-bracket_left', '}': 'shift-bracket_right', '@': 'shift-2', '#': 'shift-3', '%': 'shift-5', '^': 'shift-6'}
def cmd(c):
    s = socket.socket(socket.AF_UNIX); s.connect(SOCK); s.recv(4096); s.sendall((c + '\n').encode()); time.sleep(0.05); s.close()
if sys.argv[1] == 'shot':
    p = os.path.join(KIT, sys.argv[2]); cmd(f'screendump {p}.ppm'); time.sleep(0.7); subprocess.run(['sudo', '-n', 'chmod', '644', p + '.ppm'])
    Image.open(p + '.ppm').save(p + '.png'); print(p + '.png')
elif sys.argv[1] == 'key':
    cmd(f'sendkey {sys.argv[2]}')
else:
    for ch in sys.argv[2].encode().decode('unicode_escape'):
        k = KEYS.get(ch) or (f'shift-{ch.lower()}' if ch.isupper() else ch); cmd(f'sendkey {k}')
