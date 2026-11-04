#!/usr/bin/env bash
# Removes what deploy/install.sh installed (same PREFIX).
set -euo pipefail
PREFIX="${PREFIX:-$HOME/.local}"
UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/psu_service.service"

if [ -f "$UNIT" ]; then
  systemctl --user disable --now psu_service 2>/dev/null || true
  rm -f "$UNIT"
  systemctl --user daemon-reload
fi
rm -f "$PREFIX/bin/psu_service" "$PREFIX/bin/psu" "$PREFIX/bin/psu_ui"
rm -rf "$PREFIX/share/psu_control"
rm -f "$PREFIX/share/applications/psu-control.desktop"
rm -f "$PREFIX"/share/icons/hicolor/*/apps/psu-control.png "$PREFIX/share/icons/hicolor/scalable/apps/psu-control.svg"
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t -f "$PREFIX/share/icons/hicolor" 2>/dev/null || true
echo "removed psu_control from $PREFIX"
