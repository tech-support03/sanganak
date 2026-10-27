#!/usr/bin/env python3
"""sanganak-keybindings — searchable list of the niri keybindings in effect.

Reads the binds block of the live ~/.config/niri/config.kdl (the generated
file rice-profile validated and niri loaded), so the list is always the binds
niri is actually using. Each bind is described by its hotkey-overlay-title
when it has one, otherwise by its action.

  sanganak-keybindings          fzf list in a floating terminal
  sanganak-keybindings --print  plain list on stdout (for scripts / testing)
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

CONFIG = Path(os.environ.get("NIRI_CONFIG", Path.home() / ".config/niri/config.kdl"))

KEY_NAMES = {
    "Mod": "Super", "Return": "Enter", "Escape": "Esc", "Space": "Space",
    "Print": "PrtSc", "Slash": "/", "Comma": ",", "Period": ".", "Minus": "-",
    "Equal": "=", "BracketLeft": "[", "BracketRight": "]", "Tab": "Tab",
    "XF86AudioRaiseVolume": "Volume Up", "XF86AudioLowerVolume": "Volume Down",
    "XF86AudioMute": "Mute", "XF86AudioPlay": "Play/Pause", "XF86AudioNext": "Next Track",
    "XF86AudioPrev": "Previous Track", "XF86MonBrightnessUp": "Brightness Up",
    "XF86MonBrightnessDown": "Brightness Down", "WheelScrollDown": "Wheel Down",
    "WheelScrollUp": "Wheel Up",
}


def binds_block(text):
    """The text inside the top-level `binds { … }`, with comments removed."""
    # Whole-line // comments only: a // inside a string (a URL) must survive.
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"^\s*//.*$", "", text, flags=re.M)
    m = re.search(r"^binds\s*\{", text, flags=re.M)
    if not m:
        return ""
    depth, i = 1, m.end()
    in_str = False
    while i < len(text) and depth:
        c = text[i]
        if c == '"' and text[i - 1] != "\\":
            in_str = not in_str
        elif not in_str and c == "{":
            depth += 1
        elif not in_str and c == "}":
            depth -= 1
        i += 1
    return text[m.end():i - 1]


def humanize_key(combo):
    return " + ".join(KEY_NAMES.get(p, p) for p in combo.split("+"))


def describe(action):
    action = action.strip().rstrip(";").strip()
    m = re.match(r'spawn(?:-sh)?\s+(.*)', action)
    if m:
        args = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))
        cmd = " ".join(args)
        cmd = re.sub(r"^sh -c ", "", cmd)
        return "Run: " + cmd
    words = action.split()
    return " ".join(w.replace("-", " ") for w in words).capitalize() if words else ""


def parse(text):
    out = []
    for m in re.finditer(r'^\s*([A-Za-z0-9_+]+)((?:\s+[a-z-]+=(?:"[^"]*"|\S+))*)\s*\{(.*?)\}', binds_block(text), flags=re.M | re.S):
        combo, props, action = m.group(1), m.group(2), m.group(3)
        title = re.search(r'hotkey-overlay-title="([^"]*)"', props or "")
        desc = title.group(1) if title else describe(action)
        out.append((humanize_key(combo), desc))
    return out


def main():
    try:
        binds = parse(CONFIG.read_text())
    except OSError as e:
        print(f"Can't read {CONFIG}: {e}", file=sys.stderr)
        sys.exit(1)
    width = max((len(k) for k, _ in binds), default=0)
    lines = [f"{k.ljust(width)}   {d}" for k, d in binds]
    if "--print" in sys.argv:
        print("\n".join(lines))
        return
    if not sys.stdin.isatty():
        # Launched from a keybind or the menu: open in a floating terminal.
        os.execvp("alacritty", ["alacritty", "--class", "sanganak.float", "-e", sys.argv[0]])
    if not shutil.which("fzf"):
        print("\n".join(lines))
        input("\nPress Enter to close")
        return
    subprocess.run(["fzf", "--no-sort", "--layout=reverse", "--prompt", "keys › ",
                    "--header", "sanganak keybindings — type to search, Esc to close",
                    "--color", "pointer:#f0522d,prompt:#f0522d,hl:#f0522d,hl+:#f0522d",
                    "--bind", "enter:ignore"], input="\n".join(lines), text=True)


if __name__ == "__main__":
    main()
