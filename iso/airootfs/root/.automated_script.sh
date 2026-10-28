#!/usr/bin/env bash
# Live-ISO login hook (archiso runs this from ~/.zlogin). On tty1 it starts
# the sanganak installer once per boot; other ttys get a plain root shell.
if [[ $(tty) == "/dev/tty1" && ! -e /tmp/.sanganak-installer-started ]]; then
    touch /tmp/.sanganak-installer-started
    # No waiting on pacman-init: pacstrap -K builds the target's own keyring,
    # and with no network pacman-init sits behind time sync for minutes.
    sanganak-installer
    echo
    echo "Run 'sanganak-installer' to start the installer again."
fi
