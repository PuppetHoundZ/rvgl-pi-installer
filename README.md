Self-contained — downloads and installs RVGL from official distribution:

* RVGL binary (aarch64)           → ~/.local/share/rvgl/rvgl.arm64
* RVGL launcher script            → ~/.local/share/rvgl/rvgl
* Game data + assets + soundtrack → ~/.local/share/rvgl/
* Desktop shortcut                → ~/.local/share/applications/rvgl.desktop

No companion files required. Distribute and run this single script.

RVGL — Open-source Re-Volt port for Linux
Official site: [https://re-volt.io](https://re-volt.io)
Downloads:     [https://distribute.re-volt.io](https://distribute.re-volt.io)
License:       Proprietary freeware binary; original Re-Volt content
is distributed by the community with developer permission.

Features:

* Downloads official pre-built aarch64 binary (no compilation)
* Installs to ~/.local/share/rvgl (fully userland, no root beyond apt)
* Runs own bundled OpenAL — zero PipeWire interference
* SDL2-based, Wayland-native via SDL_VIDEODRIVER=wayland
* Uninstall cleanly removes all installed files
* Rollback on failure — restores previous state on error or power loss

Requirements:

* Raspberry Pi OS Trixie (Debian 13) arm64
* PipeWire audio (default on Trixie — NOT touched by this script)
* Internet connection (~176 MB download, one-time)
* ~400 MB free disk space installed

Usage:
chmod +x rvgl-manager.sh
./rvgl-manager.sh

Do NOT run as root.

Disclaimer:
Provided as-is, free of charge, for Raspberry Pi users. Not affiliated
with the RVGL team or Raspberry Pi Ltd. Use at your own risk.
