#!/usr/bin/env python3
"""sanganak-logo — render the संगणक chip mark (the Sahyadri ridge on a chip).

    sanganak-logo png OUT SIZE c1 c2 c3 base    antialiased RGBA PNG (hyprlock)
    sanganak-logo dur OUT PX   c1 c2 c3 base    durdraw file for ly's dur_file
                                                animation (PX wide, PX/2 rows)
    sanganak-logo ansi OUT PX  c1 c2 c3 base    truecolor ANSI half-block art for
                                                fastfetch's file-raw logo

Same geometry as dotfiles/quickshell/theme/ChipLogo.qml and the canvas mark
(a 100-unit grid): c2 pins + ridge, c1 sun, c3 ground line, chip body on base.
Pure stdlib — no rsvg/PIL — so it runs as root from 07-services.sh before
anything else is installed.

The terminal outputs (dur, ansi) share one pixel grid: pins, sun and ridge are
placed on whole pixels so the pins stay evenly spaced and the ridge one pixel
wide at any size. Each cell packs two pixels with '▀'/'▄'/'█'. dur uses
xterm-256 colours matched the way ly converts them back to RGB (ly 1.5
DurFile.zig); ansi uses 24-bit colour and leaves the background transparent.
"""
import gzip
import json
import struct
import sys
import zlib


def rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


# ---- geometry (100-unit grid) ----------------------------------------------
def rrect(x, y, w, h, r):
    def inside(px, py):
        dx = max(x + r - px, 0.0, px - (x + w - r))
        dy = max(y + r - py, 0.0, py - (y + h - r))
        return px >= x and px <= x + w and py >= y and py <= y + h and dx * dx + dy * dy <= r * r
    return (x, y, x + w, y + h), inside


def ring(x, y, w, h, r, t):
    _, outer = rrect(x, y, w, h, r)
    _, inner = rrect(x + t, y + t, w - 2 * t, h - 2 * t, max(0.0, r - t))
    return (x, y, x + w, y + h), lambda px, py: outer(px, py) and not inner(px, py)


def circle(cx, cy, r):
    return (cx - r, cy - r, cx + r, cy + r), lambda px, py: (px - cx) ** 2 + (py - cy) ** 2 <= r * r


def polyline(pts, width):
    h = width / 2.0
    segs = list(zip(pts, pts[1:]))

    def inside(px, py):
        for (ax, ay), (bx, by) in segs:
            vx, vy = bx - ax, by - ay
            t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy)))
            dx, dy = px - (ax + t * vx), py - (ay + t * vy)
            if dx * dx + dy * dy <= h * h:
                return True
        return False
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return (min(xs) - h, min(ys) - h, max(xs) + h, max(ys) + h), inside


RIDGE = [(24, 67.7), (37, 47.6), (45.3, 57.1), (57.1, 38.2), (67.7, 54.7), (76, 45.3)]


def pixel_line(n, pts):
    """8-connected 1-px Bresenham polyline through RIDGE on an n×n grid. A
    supersampled stroke is either too fat or breaks up at console resolution;
    this stays one clean pixel wide and never touches the sun."""
    def px(p):
        return (min(n - 1, int(p[0] * n / 100)), min(n - 1, int(p[1] * n / 100)))
    cells = []
    for a, b in zip(pts, pts[1:]):
        (x0, y0), (x1, y1) = px(a), px(b)
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            cells.append((x0, y0))
            if (x0, y0) == (x1, y1):
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy; x0 += sx
            if e2 <= dx:
                err += dx; y0 += sy
    return cells


def layers(c1, c2, c3, base, tty):
    """Back-to-front (shape, colour). tty=True thickens hairlines for the
    coarse console grid and raises the body off the (identical) ly background."""
    fog, acc, grn, blk = rgb(c2), rgb(c1), rgb(c3), rgb(base)
    out = []
    if not tty:                   # tty pins are placed on whole pixels (pixel_grid)
        for p in (26, 40, 54, 68):
            out.append((rrect(p, 5, 6, 14, 3), fog))
            out.append((rrect(p, 81, 6, 14, 3), fog))
            out.append((rrect(5, p, 14, 6, 3), fog))
            out.append((rrect(81, p, 14, 6, 3), fog))
    out.append((rrect(15, 15, 70, 70, 14), mix(blk, (255, 255, 255), 0.05) if tty else blk))
    out.append((ring(15, 15, 70, 70, 14, 3.2 if tty else 1.2), mix(blk, fog, 0.22)))
    if not tty:                   # tty sun is centred on a pixel (pixel_grid)
        out.append((circle(38.2, 35, 6.5), acc))
    if not tty:                   # tty draws the ridge as a 1-px pixel line instead
        out.append((polyline(RIDGE, 4.7), fog))
    out.append((rrect(24, 71.5, 52, 4.6 if tty else 3.6, 1.8), grn))
    return out


def rasterize(n, ss, shapes):
    """n×n pixels, ss×ss samples each → per-pixel list of sample colours (None = clear)."""
    m = n * ss
    buf = [None] * (m * m)
    k = 100.0 / m
    for (bbox, inside), col in shapes:
        x0, y0, x1, y1 = bbox
        for sy in range(max(0, int(y0 / k)), min(m, int(y1 / k) + 1)):
            py = (sy + 0.5) * k
            row = sy * m
            for sx in range(max(0, int(x0 / k)), min(m, int(x1 / k) + 1)):
                if inside((sx + 0.5) * k, py):
                    buf[row + sx] = col
    return buf, m


# ---- PNG --------------------------------------------------------------------
def write_png(path, n, c1, c2, c3, base):
    ss = 3
    buf, m = rasterize(n, ss, layers(c1, c2, c3, base, tty=False))
    raw = bytearray()
    for y in range(n):
        raw.append(0)
        for x in range(n):
            r = g = b = a = 0
            for sy in range(ss):
                row = (y * ss + sy) * m + x * ss
                for sx in range(ss):
                    c = buf[row + sx]
                    if c is not None:
                        r += c[0]; g += c[1]; b += c[2]; a += 1
            if a:
                raw += bytes((r // a, g // a, b // a, round(255 * a / (ss * ss))))
            else:
                raw += b'\0\0\0\0'

    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', n, n, 8, 6, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)


# ---- dur (ly) ---------------------------------------------------------------
def ly_256_rgb(i):
    """xterm index → RGB exactly as ly's convert256ToRgb does it (16..255 only)."""
    if i < 232:
        def ch(v):
            return v * 40 + 55 if v else 0
        i -= 16
        return (ch(i // 36 % 6), ch(i // 6 % 6), ch(i % 6))
    v = 8 + 10 * (i - 232)
    return (v, v, v)


PAL = [(i, ly_256_rgb(i)) for i in range(16, 256)]


def nearest(c):
    return min(PAL, key=lambda p: sum((a - b) ** 2 for a, b in zip(p[1], c)))[0]


def pixel_grid(n, c1, c2, c3, base):
    """n×n RGB pixels for the terminal outputs; None = background."""
    n -= n % 2
    ss = 3
    buf, m = rasterize(n, ss, layers(c1, c2, c3, base, tty=True))
    fog, acc = rgb(c2), rgb(c1)

    # Pins: 4 per side on an integer pitch, centred on the chip, so every gap
    # is identical (snapping the vector pins to the grid made the middle pair
    # look closer). They sit behind the body.
    pitch = max(3, round(n * 0.14))
    pw = max(1, round(n * 0.06))
    span = 3 * pitch + pw
    start = (n - span) // 2
    outer, inner = round(n * 0.05), round(n * 0.20)
    pins = set()
    for k in range(4):
        for a in range(start + k * pitch, start + k * pitch + pw):
            for d in range(outer, inner):
                for x, y in ((a, d), (a, n - 1 - d), (d, a), (n - 1 - d, a)):
                    pins.add((x, y))

    # Sun: a disc centred on a pixel centre so it stays round at any size.
    scx, scy = int(38.2 * n / 100) + 0.5, int(35 * n / 100) + 0.5
    sr = 7.0 * n / 100

    ridge = set(pixel_line(n, RIDGE))
    grid = []
    for y in range(n):
        row = []
        for x in range(n):
            counts = {}
            for sy in range(ss):
                r0 = (y * ss + sy) * m + x * ss
                for sx in range(ss):
                    c = buf[r0 + sx]
                    counts[c] = counts.get(c, 0) + 1
            c = max(counts, key=counts.get)
            if c is None and (x, y) in pins:
                c = fog
            if c is not None and (x + 0.5 - scx) ** 2 + (y + 0.5 - scy) ** 2 <= sr * sr:
                c = acc
            if (x, y) in ridge:
                c = fog
            row.append(c)
        grid.append(row)
    return grid


def write_dur(path, n, c1, c2, c3, base):
    grid = pixel_grid(n, c1, c2, c3, base)
    n = len(grid)
    bg = rgb(base)
    cache = {}

    def idx(c):
        c = c or bg
        if c not in cache:
            cache[c] = nearest(c)
        return cache[c]

    rows = n // 2
    contents = []
    cmap = [[None] * rows for _ in range(n)]
    for r in range(rows):
        line = []
        for x in range(n):
            top, bot = idx(grid[2 * r][x]), idx(grid[2 * r + 1][x])
            line.append(' ' if top == bot else '▀')
            cmap[x][r] = [top, bot]
        contents.append(''.join(line))
    movie = {'DurMovie': {
        'formatVersion': 7, 'colorFormat': '256', 'preferredFont': 'fixed',
        'encoding': 'utf-8', 'name': 'sanganak', 'artist': 'sanganak rice',
        'framerate': 1.0, 'sizeX': n, 'sizeY': rows, 'extra': None,
        'frames': [{'frameNumber': 1, 'delay': 0, 'contents': contents, 'colorMap': cmap}],
    }}
    with gzip.open(path, 'wb') as f:
        f.write(json.dumps(movie, ensure_ascii=False).encode('utf-8'))


def write_ansi(path, n, c1, c2, c3, base):
    """24-bit half-block art; background pixels stay transparent so the logo
    sits on alacritty's translucent theme base like the rest of fastfetch."""
    grid = pixel_grid(n, c1, c2, c3, base)
    n = len(grid)

    def fg(c):
        return '\x1b[38;2;%d;%d;%dm' % c

    def bgc(c):
        return '\x1b[48;2;%d;%d;%dm' % c
    out = []
    for r in range(n // 2):
        line = []
        for x in range(n):
            t, b = grid[2 * r][x], grid[2 * r + 1][x]
            if t is None and b is None:
                line.append('\x1b[0m ')
            elif t == b:
                line.append('\x1b[0m' + fg(t) + '█')
            elif b is None:
                line.append('\x1b[0m' + fg(t) + '▀')
            elif t is None:
                line.append('\x1b[0m' + fg(b) + '▄')
            else:
                line.append(fg(t) + bgc(b) + '▀')
        out.append(''.join(line) + '\x1b[0m')
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out) + '\n')


def main(argv):
    if len(argv) != 8 or argv[1] not in ('png', 'dur', 'ansi'):
        sys.exit(__doc__)
    mode, out, size = argv[1], argv[2], int(argv[3])
    cols = argv[4:8]
    for c in cols:
        if len(c.lstrip('#')) != 6:
            sys.exit('sanganak-logo: colours must be #rrggbb')
    {'png': write_png, 'dur': write_dur, 'ansi': write_ansi}[mode](out, size, *cols)


if __name__ == '__main__':
    main(sys.argv)
