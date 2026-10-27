#!/usr/bin/env python3
"""sanganak-logo — render the संगणक chip mark (the Sahyadri ridge on a chip).

    sanganak-logo png OUT SIZE c1 c2 c3 base    antialiased RGBA PNG (hyprlock)
    sanganak-logo dur OUT PX   c1 c2 c3 base    durdraw file for ly's dur_file
                                                animation (PX wide, PX/2 rows)

Same geometry as dotfiles/quickshell/theme/ChipLogo.qml and the canvas mark
(a 100-unit grid): c2 pins + ridge, c1 sun, c3 ground line, chip body on base.
Pure stdlib — no rsvg/PIL — so it runs as root from 07-services.sh before
anything else is installed.

The dur output only uses '▀' and ' ' (both in every console font): each cell
packs two pixels, top = foreground, bottom = background, in xterm-256 colours
matched the way ly converts them back to RGB (ly 1.5 DurFile.zig).
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


def layers(c1, c2, c3, base, tty):
    """Back-to-front (shape, colour). tty=True thickens hairlines for the
    coarse console grid and raises the body off the (identical) ly background."""
    fog, acc, grn, blk = rgb(c2), rgb(c1), rgb(c3), rgb(base)
    out = []
    pr = 0 if tty else 3          # rounded pin ends alias into notches on a tty
    for p in (26, 40, 54, 68):
        out.append((rrect(p, 5, 6, 14, pr), fog))
        out.append((rrect(p, 81, 6, 14, pr), fog))
        out.append((rrect(5, p, 14, 6, pr), fog))
        out.append((rrect(81, p, 14, 6, pr), fog))
    out.append((rrect(15, 15, 70, 70, 14), mix(blk, (255, 255, 255), 0.05) if tty else blk))
    out.append((ring(15, 15, 70, 70, 14, 3.2 if tty else 1.2), mix(blk, fog, 0.22)))
    # tty: centre the sun on a pixel centre of the 32-px grid so it stays round
    out.append((circle(39.06, 35.94, 7.0) if tty else circle(38.2, 35, 6.5), acc))
    ridge = [(24, 67.7), (37, 47.6), (45.3, 57.1), (57.1, 38.2), (67.7, 54.7), (76, 45.3)]
    out.append((polyline(ridge, 6.2 if tty else 4.7), fog))
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


def write_dur(path, n, c1, c2, c3, base):
    n -= n % 2
    ss = 3
    buf, m = rasterize(n, ss, layers(c1, c2, c3, base, tty=True))
    bg = rgb(base)

    def pixel(x, y):              # majority colour of the pixel's samples
        counts = {}
        for sy in range(ss):
            row = (y * ss + sy) * m + x * ss
            for sx in range(ss):
                c = buf[row + sx] or bg
                counts[c] = counts.get(c, 0) + 1
        return max(counts, key=counts.get)

    cache = {}

    def idx(c):
        if c not in cache:
            cache[c] = nearest(c)
        return cache[c]

    rows = n // 2
    contents = []
    cmap = [[None] * rows for _ in range(n)]
    for r in range(rows):
        line = []
        for x in range(n):
            top, bot = idx(pixel(x, 2 * r)), idx(pixel(x, 2 * r + 1))
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


def main(argv):
    if len(argv) != 8 or argv[1] not in ('png', 'dur'):
        sys.exit(__doc__)
    mode, out, size = argv[1], argv[2], int(argv[3])
    cols = argv[4:8]
    for c in cols:
        if len(c.lstrip('#')) != 6:
            sys.exit('sanganak-logo: colours must be #rrggbb')
    (write_png if mode == 'png' else write_dur)(out, size, *cols)


if __name__ == '__main__':
    main(sys.argv)
