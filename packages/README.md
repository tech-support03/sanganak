# Package lists

One package per line; `#` starts a comment. These lists are the single source
for every install path:

| List | Installed by | Network |
|---|---|---|
| `desktop.txt` | the ISO (pacstrap from its offline repo) and `install.sh` (module 01) | ISO: none |
| `aur-offline.txt` | prebuilt into the ISO's offline repo; `install.sh` builds it (module 02) | ISO: none |
| `apps.txt` | `sanganak-finish-setup` on first login, `install.sh` (module 01) | yes |
| `aur.txt` | `sanganak-finish-setup`, `install.sh` (module 03) | yes |

Hardware-specific extras (VM guest tools, NVIDIA, laptop power) are chosen at
install time by the scripts, not listed here. The bootloader and base system
are in `iso-stage/03-pacstrap.sh`.
