#!/usr/bin/env python3
"""arch-logo — the stock Arch Linux ASCII logo, in one colour, for terminals.

    arch-logo dur OUT COLOR BASE    durdraw file for ly's dur_file animation
    arch-logo ansi OUT COLOR        truecolor ANSI text (installer, Finish setup);
                                    OUT '-' prints it

The art is the Arch logo fastfetch/neofetch print (37 columns × 19 rows). It
is plain ASCII, so any console font draws it. Pure stdlib, so it runs as root
from theme-ly.sh and from iso/build.sh before anything else is installed.

dur uses xterm-256 colours matched the way ly converts them back to RGB (ly
DurFile.zig); BASE paints the cells around the strokes. ansi uses 24-bit colour
and leaves the background alone.
"""
import gzip
import json
import sys

ART = r"""
                  -`
                 .o+`
                `ooo/
               `+oooo:
              `+oooooo:
              -+oooooo+:
            `/:-:++oooo+:
           `/++++/+++++++:
          `/++++++++++++++:
         `/+++ooooooooooooo/`
        ./ooosssso++osssssso+`
       .oossssso-````/ossssss+`
      -osssssso.      :ssssssso.
     :osssssss/        osssso+++.
    /ossssssss/        +ssssooo/-
  `/ossssso+/:-        -:/+osssso+-
 `+sso+:-`                 `.-/+oso:
`++:.                           `-/+/
.`                                 `/
""".strip('\n').split('\n')
WIDTH = max(len(line) for line in ART)
LINES = [line.ljust(WIDTH) for line in ART]


def rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


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


def write_dur(path, color, base):
    fg, bg = nearest(rgb(color)), nearest(rgb(base))
    cmap = [[[fg, bg] for _ in LINES] for _ in range(WIDTH)]
    movie = {'DurMovie': {
        'formatVersion': 7, 'colorFormat': '256', 'preferredFont': 'fixed',
        'encoding': 'utf-8', 'name': 'archlinux', 'artist': 'sanganak rice',
        'framerate': 1.0, 'sizeX': WIDTH, 'sizeY': len(LINES), 'extra': None,
        'frames': [{'frameNumber': 1, 'delay': 0, 'contents': LINES, 'colorMap': cmap}],
    }}
    with gzip.open(path, 'wb') as f:
        f.write(json.dumps(movie, ensure_ascii=False).encode('utf-8'))


def write_ansi(path, color):
    sgr = '\x1b[38;2;%d;%d;%dm' % rgb(color)
    art = ''.join(sgr + line.rstrip() + '\x1b[0m\n' for line in LINES)
    if path == '-':
        sys.stdout.write(art)
        return
    with open(path, 'w', encoding='utf-8') as f:
        f.write(art)


def main(argv):
    if len(argv) < 2 or argv[1] not in ('dur', 'ansi') or len(argv) != {'dur': 5, 'ansi': 4}[argv[1]]:
        sys.exit(__doc__)
    for c in argv[3:]:
        if len(c.lstrip('#')) != 6:
            sys.exit('arch-logo: colours must be #rrggbb')
    if argv[1] == 'dur':
        write_dur(argv[2], argv[3], argv[4])
    else:
        write_ansi(argv[2], argv[3])


if __name__ == '__main__':
    main(sys.argv)
