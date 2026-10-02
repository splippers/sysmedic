#!/usr/bin/env python3
"""vm.py shot NAME | vm.py type 'text\n' — drive QEMU via its monitor socket."""
import socket, subprocess, sys, time
from PIL import Image
SOCK = '/home/jon/sysmedic-build/mon.sock'
KEYS = {' ': 'spc', '\n': 'ret', '-': 'minus', '/': 'slash', '.': 'dot', '=': 'equal', ';': 'semicolon',
        ',': 'comma', "'": 'apostrophe', '\\': 'backslash', '[': 'bracket_left', ']': 'bracket_right',
        ':': 'shift-semicolon', '|': 'shift-backslash', '"': 'shift-apostrophe', '_': 'shift-minus',
        '>': 'shift-dot', '<': 'shift-comma', '&': 'shift-7', '$': 'shift-4', '*': 'shift-8', '(': 'shift-9',
        ')': 'shift-0', '~': 'shift-grave_accent', '+': 'shift-equal', '!': 'shift-1', '?': 'shift-slash'}
def cmd(c):
    s = socket.socket(socket.AF_UNIX); s.connect(SOCK); s.recv(4096); s.sendall((c + '\n').encode()); time.sleep(0.05); s.close()
if sys.argv[1] == 'shot':
    p = f'/home/jon/sysmedic-build/{sys.argv[2]}'; cmd(f'screendump {p}.ppm'); time.sleep(0.7); subprocess.run(['sudo', '-n', 'chmod', '644', p + '.ppm'])
    Image.open(p + '.ppm').save(p + '.png'); print(p + '.png')
else:
    for ch in sys.argv[2].encode().decode('unicode_escape'):
        k = KEYS.get(ch) or (f'shift-{ch.lower()}' if ch.isupper() else ch); cmd(f'sendkey {k}')
