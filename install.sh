#!/usr/bin/env bash
# Cursor Meter — installer for KDE Plasma 6.
set -euo pipefail

ID="org.mat.cursormeter"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$HERE/plasmoid/$ID"
DEST="$HOME/.local/share/plasma/plasmoids/$ID"
AUTH="${CURSOR_CONFIG_HOME:-$HOME/.config/cursor}/auth.json"
STATE_DB="${CURSOR_STATE_DB:-$HOME/.config/Cursor/User/globalStorage/state.vscdb}"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m  %s\n' "$*"; }

say "Checking dependencies…"
missing=()
for c in jq curl; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
command -v kpackagetool6 >/dev/null 2>&1 || missing+=("kpackagetool6")
if [ "${#missing[@]}" -gt 0 ]; then
    warn "Missing: ${missing[*]}"
    warn "Install them with your package manager, e.g.:"
    warn "  Fedora/KDE : sudo dnf install jq curl kf6-kpackage sqlite"
    warn "  Arch       : sudo pacman -S jq curl sqlite"
    warn "  openSUSE   : sudo zypper install jq curl sqlite3"
    echo
    read -r -p "Continue anyway? [y/N] " a; [ "${a,,}" = "y" ] || exit 1
fi

if [ ! -s "$AUTH" ] && ! { [ -s "$STATE_DB" ] && command -v sqlite3 >/dev/null 2>&1 \
    && sqlite3 -readonly "$STATE_DB" "SELECT 1 FROM ItemTable WHERE key='cursorAuth/accessToken' LIMIT 1;" 2>/dev/null | grep -q 1; }; then
    warn "No Cursor credentials found."
    warn "Sign in to the Cursor IDE or run 'cursor-agent login' first."
    echo
fi

say "Installing the plasmoid ($ID)…"
if kpackagetool6 -t Plasma/Applet -s "$ID" >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet -u "$PKG"
else
    kpackagetool6 -t Plasma/Applet -i "$PKG" 2>/dev/null || {
        warn "kpackagetool install failed; copying files directly."
        mkdir -p "$DEST"; cp -rT "$PKG" "$DEST"
    }
fi
kbuildsycoca6 >/dev/null 2>&1 || true
say "Installed."

echo
read -r -p "Add 'Cursor Meter' to your top panel now? [Y/n] " a
if [ "${a,,}" != "n" ]; then
    Q=$(command -v qdbus-qt6 || command -v qdbus6 || true)
    if [ -n "$Q" ]; then
        "$Q" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
            var ps = panels(); var target = ps.find(p => p.location == "top") || ps[0];
            if (target) { target.addWidget("org.mat.cursormeter"); }
        ' >/dev/null 2>&1 && say "Added to your panel." \
          || warn "Could not add automatically — right-click your panel → Add Widgets → Cursor Meter."
    else
        warn "qdbus not found — right-click your panel → Add Widgets → Cursor Meter."
    fi
fi

echo
say "Done. If the widget doesn't appear or update, run:  kquitapp6 plasmashell && kstart plasmashell"
say "It reads your live Cursor usage using the token Cursor already stored on disk."
