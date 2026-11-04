#!/usr/bin/env bash
# Builds psu_service, psu (CLI) and psu_ui and installs them for the current user.
#
#   deploy/install.sh            # install everything into ~/.local
#   deploy/install.sh --systemd  # additionally install + enable the user unit
#   deploy/install.sh --no-ui    # skip the Flutter build
#   PREFIX=/opt/psu deploy/install.sh
#
# Layout:
#   $PREFIX/bin/psu_service          compiled daemon
#   $PREFIX/bin/psu                  compiled CLI
#   $PREFIX/bin/psu_ui               symlink into the Flutter bundle
#   $PREFIX/share/psu_control/ui/    Flutter bundle
#   $PREFIX/share/applications/psu-control.desktop
#   $PREFIX/share/icons/hicolor/*/apps/psu-control.{png,svg}
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
WITH_UI=1
WITH_SYSTEMD=0
for arg in "$@"; do
  case "$arg" in
    --no-ui) WITH_UI=0 ;;
    --systemd) WITH_SYSTEMD=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$PREFIX/bin"
SHARE="$PREFIX/share/psu_control"

command -v dart >/dev/null || { echo "dart not found in PATH" >&2; exit 1; }
if [ "$WITH_UI" = 1 ]; then
  command -v flutter >/dev/null || { echo "flutter not found in PATH (use --no-ui to skip the UI)" >&2; exit 1; }
fi

echo "==> Resolving dependencies"
(cd "$ROOT" && dart pub get >/dev/null)

mkdir -p "$BIN" "$SHARE"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

echo "==> Compiling psu_service"
dart compile exe "$ROOT/packages/psu_service/bin/psu_service.dart" -o "$BUILD/psu_service" >/dev/null
echo "==> Compiling psu (CLI)"
dart compile exe "$ROOT/packages/psu_cli/bin/psu_cli.dart" -o "$BUILD/psu" >/dev/null
install -m 755 "$BUILD/psu_service" "$BIN/psu_service"
install -m 755 "$BUILD/psu" "$BIN/psu"

if [ "$WITH_UI" = 1 ]; then
  echo "==> Building psu_ui (Flutter, release)"
  (cd "$ROOT/apps/psu_ui" && flutter build linux --release --no-tree-shake-icons >/dev/null)
  rm -rf "$SHARE/ui"
  cp -r "$ROOT/apps/psu_ui/build/linux/x64/release/bundle" "$SHARE/ui" >/dev/null
  ln -sfn "$SHARE/ui/psu_ui" "$BIN/psu_ui"

  echo "==> Installing icons and desktop entry"
  for png in "$ROOT"/apps/psu_ui/linux/icon/psu-control-*.png; do
    size="$(basename "$png" .png)"; size="${size##*-}"
    install -Dm644 "$png" "$PREFIX/share/icons/hicolor/${size}x${size}/apps/psu-control.png"
  done
  install -Dm644 "$ROOT/apps/psu_ui/linux/icon/psu-control.svg" "$PREFIX/share/icons/hicolor/scalable/apps/psu-control.svg"
  command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t -f "$PREFIX/share/icons/hicolor" 2>/dev/null || true

  mkdir -p "$PREFIX/share/applications"
  sed "s|@BIN@|$BIN|g" "$ROOT/deploy/psu-control.desktop.in" > "$PREFIX/share/applications/psu-control.desktop"
  command -v update-desktop-database >/dev/null && update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
fi

if [ "$WITH_SYSTEMD" = 1 ]; then
  echo "==> Installing systemd user unit"
  UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$UNIT_DIR"
  sed "s|@BIN@|$BIN|g" "$ROOT/deploy/psu_service.service.in" > "$UNIT_DIR/psu_service.service"
  systemctl --user daemon-reload
  systemctl --user enable --now psu_service
  systemctl --user --no-pager status psu_service | head -5 || true
fi

echo
echo "Installed:"
echo "  $BIN/psu_service"
echo "  $BIN/psu"
[ "$WITH_UI" = 1 ] && echo "  $BIN/psu_ui  ->  $SHARE/ui/"
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo; echo "NOTE: $BIN is not in your PATH. Add to your shell rc:"; echo "  export PATH=\"$BIN:\$PATH\"" ;;
esac
