#!/usr/bin/env bash
# Claude Code Sync — launcher.
# Doble clic en este archivo. Arranca el wizard web local y abre tu browser.
# La terminal se ve por ~1 segundo y se minimiza/oculta.

set -uo pipefail

# Resolver dónde está este script (puede haberlo descargado el usuario suelto
# o estar dentro de un repo clonado).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIZARD_DIR="$SCRIPT_DIR"
[ -f "$WIZARD_DIR/server.py" ] || WIZARD_DIR="$HOME/Developer/claude-session-sync/wizard"

LOG="$HOME/Library/Logs/claude-code-sync.log"
mkdir -p "$(dirname "$LOG")"

echo "Claude Code Sync — iniciando wizard…"
echo "Si Safari no se abre solo, andá a http://127.0.0.1:8765/"
echo ""

# Si no encontramos el wizard local (descarga suelta), clonamos el repo.
if [ ! -f "$WIZARD_DIR/server.py" ]; then
  echo "Bajando recursos del wizard…"
  TMP="$HOME/Library/Caches/claude-code-sync"
  mkdir -p "$TMP"
  if ! command -v git >/dev/null 2>&1; then
    osascript -e 'display dialog "Necesito git para bajar el wizard. Abrí Terminal y ejecutá: xcode-select --install. Después cerrá y volvé a abrir este archivo." buttons {"OK"} default button "OK" with title "Claude Code Sync" with icon caution'
    exit 1
  fi
  if [ -d "$TMP/repo/.git" ]; then
    git -C "$TMP/repo" pull --quiet
  else
    rm -rf "$TMP/repo"
    git clone --quiet https://github.com/jefermorales/claude-session-sync.git "$TMP/repo"
  fi
  WIZARD_DIR="$TMP/repo/wizard"
fi

if ! command -v python3 >/dev/null 2>&1; then
  osascript -e 'display dialog "Necesito Python 3, que normalmente viene con macOS. Abrí Terminal y ejecutá: xcode-select --install. Después cerrá y volvé a abrir este archivo." buttons {"OK"} default button "OK" with title "Claude Code Sync" with icon caution'
  exit 1
fi

# Lanzamos el server (sirve la página y abre el browser solo).
exec python3 "$WIZARD_DIR/server.py" 2>&1 | tee -a "$LOG"
