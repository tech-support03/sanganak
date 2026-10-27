#!/usr/bin/env bash
# Live-ISO login hook (archiso runs this from ~/.zlogin). On tty1 it starts
# the sanganak installer once per boot; other ttys get a plain root shell.
if [[ $(tty) == "/dev/tty1" && ! -e /tmp/.sanganak-installer-started ]]; then
    touch /tmp/.sanganak-installer-started
    # pacman-init populates the keyring the offline install's pacstrap uses.
    systemctl is-active --quiet pacman-init.service || { echo "Preparing…"; systemctl start pacman-init.service; }
    sanganak-installer
    echo
    echo "Run 'sanganak-installer' to start the installer again."
fi
