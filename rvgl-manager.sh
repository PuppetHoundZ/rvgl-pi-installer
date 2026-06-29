#!/usr/bin/env bash
# =============================================================================
# rvgl-manager.sh
# RVGL — Re-Volt Game for Linux — Manager Script
# Version: 1.0.4
# Last updated: 2026-06-19
#
# Self-contained — downloads and installs RVGL from official distribution:
#   • RVGL binary (aarch64)           → ~/.local/share/rvgl/rvgl.arm64
#   • RVGL launcher script            → ~/.local/share/rvgl/rvgl
#   • Game data + assets + soundtrack → ~/.local/share/rvgl/
#   • Desktop shortcut                → ~/.local/share/applications/rvgl.desktop
#
# No companion files required. Distribute and run this single script.
#
# RVGL — Open-source Re-Volt port for Linux
#   Official site: https://re-volt.io
#   Downloads:     https://distribute.re-volt.io
#   License:       Proprietary freeware binary; original Re-Volt content
#                  is distributed by the community with developer permission.
#
# Features:
#   • Downloads official pre-built aarch64 binary (no compilation)
#   • Installs to ~/.local/share/rvgl (fully userland, no root beyond apt)
#   • Runs own bundled OpenAL — zero PipeWire interference
#   • SDL2-based, Wayland-native via SDL_VIDEODRIVER=wayland
#   • Uninstall cleanly removes all installed files
#   • Rollback on failure — restores previous state on error or power loss
#
# Requirements:
#   - Raspberry Pi OS Trixie (Debian 13) arm64
#   - PipeWire audio (default on Trixie — NOT touched by this script)
#   - Internet connection (~176 MB download, one-time)
#   - ~400 MB free disk space installed
#
# Usage:
#   chmod +x rvgl-manager.sh
#   ./rvgl-manager.sh
#
# Do NOT run as root.
#
# Disclaimer:
#   Provided as-is, free of charge, for Raspberry Pi users. Not affiliated
#   with the RVGL team or Raspberry Pi Ltd. Use at your own risk.
# =============================================================================

# =============================================================================
# AI REFERENCE NOTES — rvgl-manager.sh
# Single source of truth. Read this block in full before making any changes.
# Cross-reference CLAUDEROOT.md for project-wide rules.
#
# ── WHAT THIS SCRIPT DOES ────────────────────────────────────────────────────
#   Downloads the official RVGL Linux release (precompiled binary, no build).
#   Source: https://distribute.re-volt.io/releases/rvgl_full_linux_original.zip
#   (~176 MB). Extracts to ~/.local/share/rvgl/. Runs the included `setup`
#   script for permissions + case-fixing. Creates a desktop launcher.
#
# ── BINARY STRUCTURE (CONFIRMED 2026-06-17) ──────────────────────────────────
#   Zip root contains:
#     rvgl              — bash launcher (auto-detects arch, sets LD_LIBRARY_PATH)
#     rvgl.arm64        — aarch64 binary  ← THIS IS WHAT Pi 4 RUNS
#     rvgl.armhf        — armhf binary
#     rvgl.64           — x86_64 binary
#     rvgl.32           — x86 binary
#     setup             — one-time setup script (permissions + case-fix + desktop)
#     alsoft_log        — OpenAL log helper
#     fix_cases         — filename case fixer for game data
#     lib/libarm64/     — bundled libopenal.so.1, libenet.so.7, libunistring.so.2
#     icons/256x256/apps/rvgl.png — app icon
#
#   The `rvgl` launcher script:
#     1. Detects arch (aarch64 → suffix "arm64")
#     2. Checks if bundled libs are needed via ldd
#     3. Sets LD_LIBRARY_PATH=./lib (with arch-symlinks if needed)
#     4. exec ./rvgl.arm64 "$@"
#
#   We call `setup` from within the install dir rather than writing our own
#   permission/desktop logic — it handles everything correctly.
#   EXCEPTION: We write our OWN desktop file because `setup`'s embedded
#   `./rvgl -register` step talks to the online lobby, which we skip on
#   first install (user can register from the in-game menu). If registration
#   is needed, user runs `~/.local/share/rvgl/setup` manually.
#
# ── AUDIO — ZERO PIPEWIRE RISK ───────────────────────────────────────────────
#   RVGL bundles its own libopenal.so.1 in lib/libarm64/. The rvgl launcher
#   script adds this to LD_LIBRARY_PATH so the system OpenAL is bypassed.
#   No ALSA, no PulseAudio, no PipeWire interaction — completely self-contained.
#   This is the same pattern as Minecraft Java bundling its own LWJGL.
#
# ── WAYLAND / DISPLAY ────────────────────────────────────────────────────────
#   RVGL is SDL2-based. SDL2 on Pi OS Trixie supports Wayland natively (Trixie's
#   libsdl2-2.0-0 2.30.0 depends on libwayland-client/cursor/egl — confirmed via
#   apt-cache, 2026-06-18). SDL2 has preferred Wayland over X11 by default since
#   2.0.22, so SDL_VIDEODRIVER=wayland is now a forcing/safety-net flag rather
#   than strictly required — but it removes ambiguity and is harmless to set.
#   Do NOT use GDK_BACKEND=x11 — SDL2 does not use GDK, that var has no effect.
#   labwc does NOT exhibit the known SDL2 fullscreen-blackscreen bug that
#   affects Sway/wlroots compositors in some configurations (verified via
#   GitHub swaywm/sway#8161 — explicitly notes labwc runs fine, only Sway fails).
#   Trixie ships genuine libsdl2 (not the sdl2-compat shim over SDL3), which
#   sidesteps a separate documented fullscreen blackscreen bug specific to
#   sdl2-compat (libsdl-org/sdl2-compat#549).
#
# ── CONFIRMED: OpenGL profile on V3D driver — WORKS, NO TRANSLATION NEEDED ──
#   RVGL's Linux fallback chain tries OpenGL 4.5 Core -> 3.2 Core -> legacy
#   fixed-pipeline OpenGL (confirmed from official RVGL changelog text).
#   CONFIRMED ON REAL HARDWARE (2026-06-19, user's Pi 4, Trixie, Mesa
#   25.0.7-2+rpt4): rvgl.log shows "GL Vendor: Broadcom / GL Renderer: V3D
#   4.2.14.0 / GL Version: 3.1 Mesa 25.0.7-2+rpt4" — the native V3D driver,
#   landing on its legacy/compatibility OpenGL 3.1 path (as expected, since
#   the driver can't satisfy the 4.5/3.2 Core attempts). NO GL4ES or other
#   translation shim was needed. Game runs ALL graphics settings on High at
#   1080p, stable 60fps, with anti-aliasing off (AA may not be supported
#   cleanly on this non-Core legacy path — untested whether enabling it
#   causes issues, since user left it off). This resolves the open question
#   from earlier development: older GL4ES compatibility notes for RVGL on
#   ARM/embedded GPUs (ptitSeb/gl4es README) are now confirmed OBSOLETE for
#   this driver generation — Mesa's V3D driver handles RVGL's legacy OpenGL
#   fallback natively and performantly on Trixie.
#   If a FUTURE Pi OS update or different hardware ever fails to launch,
#   shows a black screen, or throws GL context errors, the troubleshooting
#   path is still:
#     1. ./rvgl -noshader   (forces legacy fixed-pipeline renderer directly,
#        skipping the 4.5/3.2 Core attempt entirely — documented RVGL flag,
#        added in version 18.0428a)
#     2. Check ~/.local/share/rvgl/profiles/rvgl.log (menu option 7) for the
#        actual GL vendor/renderer/version string RVGL negotiated.
#     3. GL4ES as a translation layer is very unlikely to be needed given
#        the confirmed result above, but remains a documented last resort.
#
# ── DISPLAY RESOLUTION ───────────────────────────────────────────────────────
#   CONFIRMED SYNTAX (official RVGL docs at rvgl.org + real forum usage):
#   -window <width> <height>  — positional arguments, NO -w/-h flag prefixes.
#   Forum example: "./rvgl -window 3840 1080" for a dual-monitor span.
#   Omitting width/height defaults to half the desktop resolution.
#   For the 800x480 touchscreen: ./rvgl -window 800 480
#   (Earlier draft of this script incorrectly used "-window -w 800 -h 480" —
#   that flag style does not exist in RVGL and has been corrected throughout.)
#   The 800×480 touchscreen mode flag is in the desktop launcher as a commented
#   alternative Exec= line. User can swap to it if they prefer touchscreen gaming.
#   Default launcher uses no -window flag — game starts in its configured mode.
#
# ── INSTALL / UNINSTALL PATHS ────────────────────────────────────────────────
#   Game dir:    ~/.local/share/rvgl/
#   Desktop:     ~/.local/share/applications/rvgl.desktop
#   Rollback:    ~/.local/share/rvgl-manager/  (state files)
#   Marker:      ~/.local/share/rvgl-manager/installed
#   Deps marker: ~/.local/share/rvgl-manager/deps_installed
#   Backup:      ~/.local/share/rvgl-manager/rvgl_backup/ (previous game dir)
#
# ── DEPENDENCIES ─────────────────────────────────────────────────────────────
#   Runtime: libsdl2-2.0-0        (SDL2 for display/input)
#            libsdl2-image-2.0-0  (texture/UI image loading — REQUIRED, binary
#                                   will refuse to start without it: confirmed
#                                   via readelf NEEDED entries + an actual
#                                   "error while loading shared libraries:
#                                   libSDL2_image-2.0.so.0: cannot open shared
#                                   object file" launch failure during testing)
#            libgl1                (OpenGL — VideoCore VI via Mesa v3d)
#            libgles2              (GLES2 fallback)
#            unzip                 (download extraction)
#            curl                  (download)
#   The bundled libs (OpenAL, enet, unistring) are inside lib/libarm64/ — no apt.
#   Confirmed via readelf -d on the actual rvgl.64 binary: only libSDL2-2.0.so.0
#   and libSDL2_image-2.0.so.0 are real, non-bundled NEEDED entries beyond base
#   glibc (libc/libm/libdl/libgcc_s/ld-linux) — everything else ships in lib/.
#   NEVER remove these apt packages on uninstall — they are system dependencies
#   shared by many other applications.
#
# ── ONLINE FEATURES ──────────────────────────────────────────────────────────
#   RVGL supports online multiplayer via re-volt.io lobby.
#   To register for online play: ~/.local/share/rvgl/setup (interactive script)
#   Or use the in-game Network → Register menu.
#   This manager does NOT auto-register (avoids surprise network requests).
#
# ── KNOWN LIMITATIONS ────────────────────────────────────────────────────────
#   - Pi 4 VideoCore VI: OpenGL 3.1 (Mesa v3d). RVGL targets OpenGL 2.x/3.x
#     which is within range. Performance should be 30-60fps at 800×480.
#   - At 1080p HDMI output, expect ~20-30fps. 800×480 is the sweet spot.
#   - Controller support: SDL2 gamepad. XBox/PS controllers work via SDL2
#     mapping. The game has in-game control configuration.
#   - Touch input: NOT natively supported in RVGL. Touchscreen acts as mouse
#     which allows menu navigation but not racing controls. Use a controller
#     or keyboard for actual gameplay.
#
# ── VERSION HISTORY ──────────────────────────────────────────────────────────
#   v1.0.0 (2026-06-17) — Initial release. Binary-only install (no compile).
#                          Full game + soundtrack + assets. aarch64 binary.
#                          SDL2 Wayland mode. Custom desktop launcher.
#                          Rollback/crash recovery system.
#   v1.0.1 (2026-06-18) — Fixed set -e false-trip in check_not_root (bare
#                          [[ ]] && pattern killed the script silently for
#                          the normal non-root case — same pattern fixed in
#                          chmod loop and uninstall removal lines).
#                          Corrected -window flag syntax: RVGL uses positional
#                          "-window <w> <h>", not "-window -w <w> -h <h>"
#                          (verified against official docs + forum usage).
#                          Added -noshader legacy-renderer launch option and
#                          GL renderer log viewer for OpenGL troubleshooting
#                          on the Pi 4's V3D driver.
#                          REAL ROLLBACK BUG FOUND AND FIXED: main_menu() ran
#                          an unconditional "trap - ERR EXIT" at startup,
#                          which cleared the install-failure rollback trap
#                          before any install was ever attempted — rollback
#                          had never actually fired, including on the very
#                          first install. Removed that line. Also added -E
#                          (errtrace) to set -, since without it bash's ERR
#                          trap does not propagate into nested function
#                          calls at all (confirmed via isolated repro) —
#                          do_install -> download_and_extract -> error() is
#                          two calls deep, so this was required for rollback
#                          to fire on realistic failures (e.g. network drop
#                          mid-download). Verified end-to-end with a forced
#                          bad-URL failure: rollback now correctly removes
#                          the partial game dir and desktop file while
#                          leaving apt dependencies untouched.
#   v1.0.2 (2026-06-18) — Found via real launch testing (Xvfb + x86_64 binary
#                          as structural proxy — same SDL2/launcher code path
#                          as the aarch64 binary, different CPU target):
#                          libsdl2-image-2.0-0 was MISSING from DEPS. Binary
#                          refused to start with "error while loading shared
#                          libraries: libSDL2_image-2.0.so.0: cannot open
#                          shared object file" until this was added. Confirmed
#                          via readelf -d NEEDED entries — only libSDL2 and
#                          libSDL2_image are real non-bundled deps beyond
#                          base glibc. Added to DEPS array.
#                          Corrected log filename: official RVGL docs
#                          reference "profiles/re-volt.log" (Windows-context
#                          examples), but the actual file produced on this
#                          Linux build is "profiles/rvgl.log" — confirmed by
#                          inspecting the real file after a launch attempt.
#                          Fixed in both AI notes and the option 7 log viewer.
#                          Verified full install -> uninstall -> reinstall ->
#                          "uninstall when not installed" cycle end-to-end;
#                          dependencies confirmed surviving uninstall.
#   v1.0.3 (2026-06-19) — REAL HANG BUG, reported live by user on actual Pi
#                          hardware: setup_game() called the official
#                          fix_cases script via "bash ./fix_cases", which is
#                          INTERACTIVE — it calls `read -r -p "Are you sure?
#                          [y/N]"` then later `read -r -p "Press any key..."`.
#                          With stdin still attached to the terminal and no
#                          input fed, it silently blocked after printing the
#                          WARNING banner, with no visual indication it was
#                          waiting on input. User had to Ctrl+C, which
#                          correctly triggered rollback (proving the rollback
#                          fix from v1.0.1/1.0.2 genuinely works on real
#                          hardware) but left a broken-feeling UX. Root cause
#                          confirmed by reading the actual fix_cases source
#                          inside the zip — two read -r -p calls, exactly as
#                          observed. Fixed by piping "y\n\n" into fix_cases'
#                          stdin so it auto-confirms both prompts. Verified
#                          fix_cases still performs its real renaming work
#                          afterward (confirmed zero stray uppercase filenames
#                          remain outside the intentionally-excluded
#                          licenses/ folder, which fix_cases' own regex skips
#                          by design). Re-ran full install end-to-end with
#                          the live download URL: completes without hanging,
#                          exit code 0, "RVGL installed successfully!" shown.
#   v1.0.4 (2026-06-19) — Documentation update only, no code changes. User
#                          confirmed RVGL fully working on real Pi 4 + Trixie
#                          hardware: GL Vendor: Broadcom, GL Renderer: V3D
#                          4.2.14.0, GL Version: 3.1 Mesa 25.0.7-2+rpt4 (read
#                          via menu option 7 from the real rvgl.log). All
#                          graphics settings on High at 1080p, stable 60fps,
#                          AA off. This resolves the previously-unverified
#                          OpenGL-profile-vs-V3D-driver question: no GL4ES
#                          translation shim needed, native Mesa V3D driver
#                          handles RVGL's legacy OpenGL 3.1 fallback path
#                          natively and performantly on Trixie. Updated the
#                          AI reference notes section from "KNOWN UNVERIFIED
#                          RISK" to "CONFIRMED" to reflect this real result.
# =============================================================================

set -Eeuo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
SCRIPT_VERSION="1.0.4"
GAME_NAME="RVGL"
GAME_DIR="$HOME/.local/share/rvgl"
DESKTOP_FILE="$HOME/.local/share/applications/rvgl.desktop"
STATE_DIR="$HOME/.local/share/rvgl-manager"
MARKER_FILE="$STATE_DIR/installed"
DEPS_MARKER="$STATE_DIR/deps_installed"
BACKUP_DIR="$STATE_DIR/rvgl_backup"

# Official distribution URL (confirmed 2026-06-17)
DOWNLOAD_URL="https://distribute.re-volt.io/releases/rvgl_full_linux_original.zip"
DOWNLOAD_SIZE="~176 MB"

# Runtime dependencies (apt) — NEVER remove on uninstall
DEPS=(libsdl2-2.0-0 libsdl2-image-2.0-0 libgl1 libgles2 unzip curl)

# =============================================================================
# COLOURS
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# =============================================================================
# HELPERS
# =============================================================================
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}▶ $*${NC}"; }
hr()      { echo -e "${DIM}────────────────────────────────────────────────────────${NC}"; }

check_not_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        error "Do not run this script as root."
    fi
}

is_installed() {
    if [[ -f "$MARKER_FILE" ]]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# ROLLBACK / CRASH RECOVERY
# =============================================================================
_rollback_needed=false

setup_rollback() {
    mkdir -p "$STATE_DIR"
    if is_installed && [[ -d "$GAME_DIR" ]]; then
        info "Backing up existing install for rollback..."
        rm -rf "$BACKUP_DIR"
        cp -a "$GAME_DIR" "$BACKUP_DIR"
    fi
}

trigger_rollback() {
    warn "Installation failed — rolling back..."
    if [[ -d "$BACKUP_DIR" ]]; then
        rm -rf "$GAME_DIR"
        mv "$BACKUP_DIR" "$GAME_DIR"
        success "Rollback complete — previous install restored."
    else
        warn "No backup found — removing partial install."
        rm -rf "$GAME_DIR"
        rm -f "$MARKER_FILE"
        rm -f "$DESKTOP_FILE"
    fi
}

# Trap for unexpected exits during install
_in_install=false
trap '
    if [[ "$_in_install" == true ]]; then
        echo ""
        warn "Unexpected exit during installation."
        trigger_rollback
    fi
' ERR EXIT

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================
install_deps() {
    step "Checking runtime dependencies"
    local missing=()
    for pkg in "${DEPS[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        success "All dependencies already installed."
        touch "$DEPS_MARKER"
        return 0
    fi

    info "Installing: ${missing[*]}"
    sudo apt-get update -qq || error "apt update failed."
    sudo apt-get install -y "${missing[@]}" || error "apt install failed."
    touch "$DEPS_MARKER"
    success "Dependencies installed."
}

# =============================================================================
# DOWNLOAD & EXTRACT
# =============================================================================
download_and_extract() {
    step "Downloading RVGL Linux release"
    info "Source: $DOWNLOAD_URL"
    info "Size:   $DOWNLOAD_SIZE (one-time download)"
    echo ""

    local tmp_zip
    tmp_zip="$(mktemp /tmp/rvgl_XXXXXX.zip)"

    # Download with progress bar
    curl -L --progress-bar \
        --retry 3 \
        --retry-delay 2 \
        -o "$tmp_zip" \
        "$DOWNLOAD_URL" || error "Download failed. Check your internet connection."

    local actual_size
    actual_size=$(du -sh "$tmp_zip" | cut -f1)
    success "Downloaded ($actual_size)"

    step "Extracting game files"
    mkdir -p "$GAME_DIR"
    unzip -q -o "$tmp_zip" -d "$GAME_DIR" || error "Extraction failed."
    rm -f "$tmp_zip"
    success "Extracted to $GAME_DIR"
}

# =============================================================================
# POST-EXTRACT SETUP
# =============================================================================
setup_game() {
    step "Setting up RVGL"

    cd "$GAME_DIR"

    # Fix file permissions manually (mirrors what `setup` does, minus -register)
    # Fix filename cases for game data — fix_cases is INTERACTIVE (asks
    # "Are you sure? [y/N]" then "Press any key to continue" at the end).
    # Confirmed by reading the actual fix_cases script source: it calls
    # `read -r -p` twice. Without feeding it input, it silently blocks
    # waiting for a keypress with no visual indication — this caused a
    # real hang during testing (had to Ctrl+C, which correctly triggered
    # rollback, but the UX was broken). We auto-answer "y" to the first
    # prompt and feed a newline for the trailing "press any key" prompt.
    if [[ -x "./fix_cases" ]]; then
        info "Fixing game data filename cases (auto-confirming)..."
        printf 'y\n\n' | bash ./fix_cases 2>/dev/null || true
    fi

    # Clear stale lib symlinks
    find ./lib -maxdepth 1 -type l -delete 2>/dev/null || true

    # Set executable permissions on all binaries
    chmod +x rvgl rvgl.arm64 rvgl.armhf rvgl.64 rvgl.32 2>/dev/null || true
    chmod +x alsoft_log fix_cases setup 2>/dev/null || true

    # Set write permissions on game data dirs (profiles, replays, times, cache)
    for d in cache profiles replays times; do
        if [[ -d "./$d" ]]; then
            chmod -R ugo+rw "./$d"
        fi
    done
    chmod ugo+rw ./lib 2>/dev/null || true

    success "Game setup complete."
}

# =============================================================================
# DESKTOP LAUNCHER
# =============================================================================
write_desktop_file() {
    step "Installing desktop launcher"

    mkdir -p "$(dirname "$DESKTOP_FILE")"

    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.1
Type=Application
Name=RVGL
Comment=Re-Volt open-source racing game
# Default launch — SDL2 Wayland, game's own resolution config
Exec=env SDL_VIDEODRIVER=wayland ${GAME_DIR}/rvgl
# Touchscreen 800x480 windowed alternative (uncomment to use instead):
# Exec=env SDL_VIDEODRIVER=wayland ${GAME_DIR}/rvgl -window 800 480
Icon=${GAME_DIR}/icons/256x256/apps/rvgl.png
Terminal=false
Categories=Game;ArcadeGame;Racing;
Path=${GAME_DIR}
Keywords=racing;cars;revolt;rc;
EOF

    chmod +x "$DESKTOP_FILE"
    success "Desktop launcher installed."
    info "Icon: ${GAME_DIR}/icons/256x256/apps/rvgl.png"
}

# =============================================================================
# MARK INSTALLED
# =============================================================================
mark_installed() {
    mkdir -p "$STATE_DIR"
    cat > "$MARKER_FILE" << EOF
version=${SCRIPT_VERSION}
installed_at=$(date -Iseconds)
game_dir=${GAME_DIR}
EOF
    success "Install marker written."
}

# =============================================================================
# INSTALL
# =============================================================================
do_install() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  RVGL — Re-Volt for Linux — Installer${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    info "Script version: $SCRIPT_VERSION"
    info "Install path:   $GAME_DIR"
    info "Download:       $DOWNLOAD_SIZE"
    echo ""

    if is_installed; then
        warn "RVGL is already installed."
        echo ""
        read -rp "  Reinstall / update? This will re-download the full game. [y/N] " confirm
        [[ "${confirm,,}" =~ ^y ]] || { echo "Cancelled."; exit 0; }
        echo ""
    fi

    _in_install=true

    setup_rollback
    install_deps
    download_and_extract
    setup_game
    write_desktop_file
    mark_installed

    _in_install=false
    # Disable the ERR/EXIT trap now that install succeeded
    trap - ERR EXIT

    echo ""
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  RVGL installed successfully!${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Launch from: ${CYAN}Applications menu → Games → RVGL${NC}"
    echo -e "  Or run:      ${CYAN}${GAME_DIR}/rvgl${NC}"
    echo ""
    echo -e "  ${DIM}Tip: For touchscreen 800×480 mode, edit the desktop file and${NC}"
    echo -e "  ${DIM}uncomment the -window 800 480 Exec= line.${NC}"
    echo ""
    echo -e "  ${DIM}Tip: For online multiplayer, run:${NC}"
    echo -e "  ${DIM}  ${GAME_DIR}/setup${NC}"
    echo ""
}

# =============================================================================
# UNINSTALL
# =============================================================================
do_uninstall() {
    echo ""
    echo -e "${BOLD}${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  RVGL — Uninstaller${NC}"
    echo -e "${BOLD}${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if ! is_installed; then
        warn "RVGL does not appear to be installed (no marker file)."
        echo ""
        if [[ -d "$GAME_DIR" ]]; then
            warn "Game directory found at $GAME_DIR"
            read -rp "  Remove it anyway? [y/N] " confirm
            [[ "${confirm,,}" =~ ^y ]] || { echo "Cancelled."; exit 0; }
        else
            echo "Nothing to remove."
            exit 0
        fi
    fi

    echo -e "  ${BOLD}The following will be permanently removed:${NC}"
    echo ""
    echo -e "    ${RED}•${NC} $GAME_DIR  (game files, ~400 MB)"
    echo -e "    ${RED}•${NC} $DESKTOP_FILE"
    echo -e "    ${RED}•${NC} $STATE_DIR  (install state)"
    echo ""
    echo -e "  ${YELLOW}NOTE:${NC} Your game profiles and save data are inside"
    echo -e "  ${YELLOW}      ${GAME_DIR}/profiles/ and will also be removed.${NC}"
    echo -e "  ${DIM}  (Back them up first if you want to keep them)${NC}"
    echo ""
    echo -e "  ${DIM}Runtime dependencies (libsdl2, libgl1, etc.) are NOT removed.${NC}"
    echo ""

    read -rp "  Are you sure you want to uninstall RVGL? [y/N] " confirm
    [[ "${confirm,,}" =~ ^y ]] || { echo "Cancelled."; exit 0; }
    echo ""

    step "Removing RVGL"

    if [[ -d "$GAME_DIR" ]]; then
        rm -rf "$GAME_DIR"
        success "Removed game directory."
    fi
    if [[ -f "$DESKTOP_FILE" ]]; then
        rm -f "$DESKTOP_FILE"
        success "Removed desktop launcher."
    fi
    if [[ -d "$STATE_DIR" ]]; then
        rm -rf "$STATE_DIR"
        success "Removed install state."
    fi

    # Refresh desktop database
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

    echo ""
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  RVGL uninstalled cleanly.${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# =============================================================================
# STATUS
# =============================================================================
do_status() {
    echo ""
    echo -e "${BOLD}RVGL Manager — Status${NC}"
    hr
    if is_installed; then
        echo -e "  Status:    ${GREEN}Installed${NC}"
        grep "installed_at" "$MARKER_FILE" 2>/dev/null | sed 's/installed_at=/  Date:      /'
        grep "version" "$MARKER_FILE" 2>/dev/null | sed 's/version=/  Version:   /'
        if [[ -d "$GAME_DIR" ]]; then
            local size
            size=$(du -sh "$GAME_DIR" 2>/dev/null | cut -f1)
            echo -e "  Disk use:  ${size}"
        fi
        echo -e "  Game dir:  ${GAME_DIR}"
        echo -e "  Desktop:   ${DESKTOP_FILE}"
        [[ -f "$DESKTOP_FILE" ]] && echo -e "  Launcher:  ${GREEN}present${NC}" || echo -e "  Launcher:  ${YELLOW}missing${NC}"
    else
        echo -e "  Status:    ${YELLOW}Not installed${NC}"
    fi
    echo ""
}

# =============================================================================
# MAIN MENU
# =============================================================================
main_menu() {
    while true; do
        echo ""
        echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}  RVGL Manager  v${SCRIPT_VERSION}${NC}"
        echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""

        if is_installed; then
            echo -e "  Status: ${GREEN}● Installed${NC}"
        else
            echo -e "  Status: ${YELLOW}○ Not installed${NC}"
        fi

        echo ""
        echo -e "  ${BOLD}1)${NC} Install / Reinstall RVGL"
        echo -e "  ${BOLD}2)${NC} Uninstall RVGL"
        echo -e "  ${BOLD}3)${NC} Show status"
        echo -e "  ${BOLD}4)${NC} Launch RVGL"
        echo -e "  ${BOLD}5)${NC} Launch RVGL (touchscreen 800×480)"
        echo -e "  ${BOLD}6)${NC} Launch RVGL with legacy renderer (-noshader, if display issues occur)"
        echo -e "  ${BOLD}7)${NC} Show GL renderer info from last launch (troubleshooting)"
        echo -e "  ${BOLD}8)${NC} Open online setup (register for multiplayer)"
        echo -e "  ${BOLD}q)${NC} Quit"
        echo ""
        read -rp "  Choice: " choice

        case "$choice" in
            1) do_install ;;
            2) do_uninstall ;;
            3) do_status ;;
            4)
                if ! is_installed; then
                    warn "RVGL is not installed."
                else
                    info "Launching RVGL (Wayland)..."
                    env SDL_VIDEODRIVER=wayland "${GAME_DIR}/rvgl" &
                fi
                ;;
            5)
                if ! is_installed; then
                    warn "RVGL is not installed."
                else
                    info "Launching RVGL at 800×480 windowed (touchscreen)..."
                    env SDL_VIDEODRIVER=wayland "${GAME_DIR}/rvgl" -window 800 480 &
                fi
                ;;
            6)
                if ! is_installed; then
                    warn "RVGL is not installed."
                else
                    info "Launching RVGL with legacy fixed-pipeline renderer..."
                    info "(Use this if you see a black screen or GL context errors)"
                    env SDL_VIDEODRIVER=wayland "${GAME_DIR}/rvgl" -noshader &
                fi
                ;;
            7)
                if ! is_installed; then
                    warn "RVGL is not installed."
                else
                    local logfile="${GAME_DIR}/profiles/rvgl.log"
                    if [[ -f "$logfile" ]]; then
                        info "GL info from last launch (rvgl.log):"
                        echo ""
                        grep -i "GL Vendor\|GL Renderer\|GL Version\|profile" "$logfile" 2>/dev/null \
                            || warn "No GL info found in log — try launching the game at least once first."
                    else
                        warn "No log file found yet at: $logfile"
                        warn "Launch RVGL at least once first, then check here."
                    fi
                fi
                ;;
            8)
                if ! is_installed; then
                    warn "RVGL is not installed."
                else
                    info "Opening online setup script..."
                    x-terminal-emulator -e bash "${GAME_DIR}/setup" &
                fi
                ;;
            q|Q|quit|exit) echo ""; exit 0 ;;
            *) warn "Invalid choice." ;;
        esac
    done
}

# =============================================================================
# ENTRY POINT
# =============================================================================
check_not_root
main_menu
