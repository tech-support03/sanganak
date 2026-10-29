#!/usr/bin/env python3
"""zen-theme — paint Zen Browser's workspaces in the rice palette.

    zen-theme apply     colour the workspaces of every Zen profile from
                        ~/.config/rice/colors: the 1st workspace takes c1
                        (the accent), the 2nd c2, and further ones alternate
    zen-theme status    print each workspace and the colour it has now

Zen keeps each workspace's gradient in <profile>/zen-sessions.jsonlz4 and
reads it only at startup; while it runs it rewrites that file from memory. So
`apply` edits the file only while Zen is closed. With Zen open it leaves one
waiter behind (a lock in $XDG_RUNTIME_DIR) that applies the palette as soon
as Zen exits — rice-theme runs `zen-theme apply` on every switch, and niri
runs it at login.

The colours go in as Zen's own picker dots ("explicit-lightness"), so Zen
blends them with its opacity setting like any colour picked by hand, and the
picker shows the dot at the matching place on its wheel.

Pure stdlib. A .jsonlz4 file is "mozLz40\\0", the decompressed size, then one
LZ4 block. Reads decompress it; writes store the JSON as a single literal run
(valid LZ4; Zen recompresses it on its next save). The previous file is kept
as zen-sessions.jsonlz4.rice-bak.
"""
import colorsys
import fcntl
import glob
import json
import math
import os
import re
import struct
import subprocess
import sys
import time

HOME = os.path.expanduser('~')
COLORS = os.path.join(HOME, '.config/rice/colors')
SESSIONS = os.path.join(HOME, '.config/zen/*/zen-sessions.jsonlz4')
LOCK = os.path.join(os.environ.get('XDG_RUNTIME_DIR', '/tmp'), 'zen-theme.lock')
MAGIC = b'mozLz40\0'


# ---- mozlz4 -----------------------------------------------------------------
def lz4_decompress(src):
    dst = bytearray()
    i, n = 0, len(src)
    while i < n:
        token = src[i]
        i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]
                i += 1
                lit += b
                if b != 255:
                    break
        dst += src[i:i + lit]
        i += lit
        if i >= n:
            break
        off = src[i] | (src[i + 1] << 8)
        i += 2
        ml = token & 15
        if ml == 15:
            while True:
                b = src[i]
                i += 1
                ml += b
                if b != 255:
                    break
        start = len(dst) - off
        for k in range(ml + 4):
            dst.append(dst[start + k])
    return bytes(dst)


def lz4_literals(raw):
    """One literal-only sequence: the simplest valid LZ4 block."""
    n = len(raw)
    if n < 15:
        return bytes([n << 4]) + raw
    rest, ext = n - 15, bytearray()
    while rest >= 255:
        ext.append(255)
        rest -= 255
    ext.append(rest)
    return bytes([0xF0]) + bytes(ext) + raw


def read_session(path):
    with open(path, 'rb') as f:
        data = f.read()
    if data[:8] != MAGIC:
        raise ValueError('not a mozlz4 file')
    return json.loads(lz4_decompress(data[12:]))


def write_session(path, obj):
    raw = json.dumps(obj, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
    blob = MAGIC + struct.pack('<I', len(raw)) + lz4_literals(raw)
    tmp = path + '.rice-tmp'
    with open(tmp, 'wb') as f:
        f.write(blob)
    if read_session(tmp) != obj:                 # never swap in a bad file
        os.unlink(tmp)
        raise ValueError('round trip failed')
    with open(path, 'rb') as src, open(path + '.rice-bak', 'wb') as bak:
        bak.write(src.read())
    os.replace(tmp, path)


# ---- palette → Zen picker dots -----------------------------------------------
def palette():
    try:
        with open(COLORS) as f:
            hexes = re.findall(r'#[0-9a-fA-F]{6}', f.read())
    except OSError:
        hexes = []
    return hexes[:2] if len(hexes) >= 2 else ['#f0522d', '#dfe5eb']


def dot(hexc):
    """A primary picker dot for one colour. Zen's wheel maps hue to the angle
    and saturation to the distance from the centre (fully saturated in the
    middle) on a 193 px radius around (208, 208), less the 29 px dot centring."""
    r, g, b = (int(hexc[i:i + 2], 16) for i in (1, 3, 5))
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    dist = (1 - s) * 193 + 0.2
    x = 208 + dist * math.cos(h * 2 * math.pi) - 29
    y = 208 + dist * math.sin(h * 2 * math.pi) - 29
    return {'c': [r, g, b], 'isCustom': False, 'algorithm': 'floating', 'isPrimary': True,
            'lightness': str(round(l * 100)), 'position': {'x': round(x), 'y': round(y)},
            'type': 'explicit-lightness'}


def zen_running():
    for comm in glob.glob('/proc/[0-9]*/comm'):
        try:
            with open(comm) as f:
                if f.read().strip() in ('zen-bin', 'zen'):
                    return True
        except OSError:
            pass
    return False


def apply():
    cols = palette()
    for path in glob.glob(SESSIONS):
        try:
            j = read_session(path)
        except (OSError, ValueError) as e:
            print(f'zen-theme: skipping {path}: {e}', file=sys.stderr)
            continue
        changed = False
        for i, space in enumerate(j.get('spaces') or []):
            theme = space.setdefault('theme', {'type': 'gradient', 'opacity': 0.5, 'texture': 0})
            want = [dot(cols[i % 2])]
            if theme.get('gradientColors') != want:
                theme['gradientColors'] = want
                theme.setdefault('type', 'gradient')
                changed = True
        if changed:
            write_session(path, j)
            print(f'zen-theme: {os.path.basename(os.path.dirname(path))} → {" ".join(cols)}')


def wait_then_apply():
    """Single waiter: hold the lock, wait for Zen to exit, then apply the
    palette as it is at that moment."""
    fd = os.open(LOCK, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return                                  # another waiter has it
    while zen_running():
        time.sleep(3)
    time.sleep(2)                               # let its final session write land
    if not zen_running():
        apply()


def status():
    for path in glob.glob(SESSIONS):
        try:
            j = read_session(path)
        except (OSError, ValueError) as e:
            print(f'{path}: {e}')
            continue
        print(os.path.basename(os.path.dirname(path)))
        for space in j.get('spaces') or []:
            cs = ['#%02x%02x%02x' % tuple(d['c']) for d in space.get('theme', {}).get('gradientColors', [])
                  if isinstance(d.get('c'), list)]
            print(f'  {space.get("name", "?")}: {" ".join(cs) or "(none)"}')


def main(argv):
    cmd = argv[1] if len(argv) > 1 else 'status'
    if cmd == 'status':
        status()
    elif cmd == 'apply' and '--wait' in argv:
        wait_then_apply()
    elif cmd == 'apply':
        if not glob.glob(SESSIONS):
            return
        if zen_running():
            subprocess.Popen([sys.executable, os.path.abspath(argv[0]), 'apply', '--wait'],
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
            print('zen-theme: Zen is open — its workspaces take the palette when it next closes')
        else:
            apply()
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv)
