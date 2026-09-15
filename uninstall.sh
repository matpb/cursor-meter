#!/usr/bin/env bash
# Cursor Meter — uninstaller.
set -uo pipefail
ID="org.mat.cursormeter"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

say "Removing the plasmoid…"
kpackagetool6 -t Plasma/Applet -r "$ID" 2>/dev/null \
    || rm -rf "$HOME/.local/share/plasma/plasmoids/$ID"
kbuildsycoca6 >/dev/null 2>&1 || true

say "Removed. A usage snapshot may remain at ~/.config/cursor-meter/last.json; delete that dir if you want."
say "Remove the widget from your panel by right-clicking it → Remove."
say "Restart the shell to fully unload it:  kquitapp6 plasmashell && kstart plasmashell"
