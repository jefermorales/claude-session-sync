#!/usr/bin/env bash
# install.command — Setup interactivo de Claude Code (doble clic en Finder)
# Wizard con checkboxes navegables + auto-instalación + manejo de errores.

set -uo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────
GITHUB_REPO="jefermorales/claude-session-sync"
GITHUB_ISSUES_URL="https://github.com/$GITHUB_REPO/issues/new"
REPO_URL="https://github.com/$GITHUB_REPO.git"
REPO_DIR="$HOME/Developer/claude-session-sync"
LOG_FILE="$HOME/Library/Logs/claude-session-sync-install.log"
mkdir -p "$(dirname "$LOG_FILE")"

# ─── Colores ─────────────────────────────────────────────────────────────────
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
CYAN=$'\033[36m'

# ─── Helpers ─────────────────────────────────────────────────────────────────
log()  { echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"; }
say()  { echo ""; printf "${BOLD}${BLUE}━━━ %s ━━━${RESET}\n" "$*"; log "SAY: $*"; }
ok()   { printf "${GREEN}✓${RESET} %s\n" "$*"; log "OK: $*"; }
warn() { printf "${YELLOW}⚠${RESET} %s\n" "$*"; log "WARN: $*"; }
err()  { printf "${RED}✗${RESET} %s\n" "$*" >&2; log "ERR: $*"; }

check_dep() { command -v "$1" >/dev/null 2>&1; }

# ─── Item registry ───────────────────────────────────────────────────────────
declare -a ITEMS_LABEL=()
declare -a ITEMS_CHECKED=()
declare -a ITEMS_LOCKED=()
declare -a ITEMS_INSTALLED=()
declare -a ITEMS_DESC=()
declare -a ITEMS_KEY=()
declare -a ITEMS_VERSION=()

add_item() {
  ITEMS_LABEL+=("$1")
  ITEMS_CHECKED+=("$2")
  ITEMS_LOCKED+=("$3")
  ITEMS_INSTALLED+=("$4")
  ITEMS_DESC+=("$5")
  ITEMS_KEY+=("$6")
  ITEMS_VERSION+=("$7")
}

# Saltar items "instalados" con las flechas
next_selectable() {
  local cursor="$1" dir="$2" total="${#ITEMS_LABEL[@]}"
  local n=0
  while [ "$n" -lt "$total" ]; do
    cursor=$((cursor + dir))
    [ "$cursor" -lt 0 ] && cursor=$((total - 1))
    [ "$cursor" -ge "$total" ] && cursor=0
    if [ "${ITEMS_INSTALLED[$cursor]}" = "0" ]; then
      echo "$cursor"; return
    fi
    n=$((n + 1))
  done
  echo "$1"  # ninguno seleccionable, devolvemos el original
}

first_selectable() {
  local total="${#ITEMS_LABEL[@]}"
  for ((i=0; i<total; i++)); do
    if [ "${ITEMS_INSTALLED[$i]}" = "0" ]; then echo "$i"; return; fi
  done
  echo "-1"
}

# ─── Render del menú ─────────────────────────────────────────────────────────
render_menu() {
  local cursor="$1"
  clear
  cat <<EOF
${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗
║          Setup de Claude Code — claude-session-sync              ║
╚══════════════════════════════════════════════════════════════════╝${RESET}

Detecté qué hay instalado en tu Mac. Lo que ya está aparece
${DIM}deshabilitado${RESET}. Solo elegís entre lo que falta.

${DIM}↑/↓ (o W/S) navegar · ESPACIO marcar · ENTER continuar · Q cancelar${RESET}

EOF
  for i in "${!ITEMS_LABEL[@]}"; do
    local prefix="  "
    [ "$i" = "$cursor" ] && [ "${ITEMS_INSTALLED[$i]}" = "0" ] && prefix="${CYAN}▶ ${RESET}"
    local check=""
    local label_style=""
    local label_suffix=""

    if [ "${ITEMS_INSTALLED[$i]}" = "1" ]; then
      # Ya instalado: deshabilitado, check verde, texto dim
      check="${GREEN}✓${RESET}"
      label_style="${DIM}"
      label_suffix=" ${DIM}— ya instalado${RESET}"
      [ -n "${ITEMS_VERSION[$i]}" ] && label_suffix="$label_suffix ${DIM}(${ITEMS_VERSION[$i]})${RESET}"
    elif [ "${ITEMS_LOCKED[$i]}" = "1" ]; then
      check="${YELLOW}◉${RESET}"
      label_style="${BOLD}"
      [ "$i" = "$cursor" ] && label_style="${BOLD}${CYAN}"
    elif [ "${ITEMS_CHECKED[$i]}" = "1" ]; then
      check="${GREEN}☑${RESET}"
      [ "$i" = "$cursor" ] && label_style="${BOLD}${CYAN}"
    else
      check="${DIM}☐${RESET}"
      [ "$i" = "$cursor" ] && label_style="${BOLD}${CYAN}"
    fi

    printf "${prefix}${check} ${label_style}%s${RESET}${label_suffix}\n" "${ITEMS_LABEL[$i]}"
    # Descripción solo para el item donde está el cursor Y no está instalado
    if [ "$i" = "$cursor" ] && [ "${ITEMS_INSTALLED[$i]}" = "0" ]; then
      printf "    ${DIM}└─ %s${RESET}\n" "${ITEMS_DESC[$i]}"
    fi
  done
  echo ""
}

# ─── Loop del menú ───────────────────────────────────────────────────────────
run_menu() {
  local cursor
  cursor=$(first_selectable)
  # Si no hay nada para seleccionar (todo instalado), no entramos al menú
  if [ "$cursor" = "-1" ]; then
    clear
    cat <<EOF
${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════════╗
║         Todo lo necesario ya está instalado en tu Mac.           ║
╚══════════════════════════════════════════════════════════════════╝${RESET}

EOF
    for i in "${!ITEMS_LABEL[@]}"; do
      printf "  ${GREEN}✓${RESET} ${DIM}%s${RESET}" "${ITEMS_LABEL[$i]}"
      [ -n "${ITEMS_VERSION[$i]}" ] && printf " ${DIM}(%s)${RESET}" "${ITEMS_VERSION[$i]}"
      echo ""
    done
    echo ""
    echo "Vamos directo a verificar/reparar el setup multi-Mac..."
    sleep 2
    return 0
  fi

  while true; do
    render_menu "$cursor"
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        # Arrow keys: leemos byte por byte después del ESC hasta encontrar
        # la letra final (A/B/C/D) o que pasen 50ms sin más bytes. Cubre todos
        # los formatos: ESC[A, ESCOA, ESC[1;5A, etc.
        rest=""
        while IFS= read -rsn1 -t 0.05 c; do
          rest+="$c"
          case "$c" in A|B|C|D|~) break ;; esac
          [ ${#rest} -ge 8 ] && break
        done
        case "$rest" in
          *A) cursor=$(next_selectable "$cursor" -1) ;;  # arriba
          *B) cursor=$(next_selectable "$cursor" 1) ;;   # abajo
        esac
        ;;
      k|K|w|W) cursor=$(next_selectable "$cursor" -1) ;;
      j|J|s|S) cursor=$(next_selectable "$cursor" 1) ;;
      " ")
        if [ "${ITEMS_LOCKED[$cursor]}" = "0" ] && [ "${ITEMS_INSTALLED[$cursor]}" = "0" ]; then
          if [ "${ITEMS_CHECKED[$cursor]}" = "1" ]; then
            ITEMS_CHECKED[$cursor]=0
          else
            ITEMS_CHECKED[$cursor]=1
          fi
        fi
        ;;
      "")  return 0 ;;
      q|Q) echo ""; echo "Cancelado."; exit 0 ;;
    esac
  done
}

# ─── Reintentos automáticos ──────────────────────────────────────────────────
retry() {
  local max="$1"; shift
  local desc="$1"; shift
  local n=0
  while [ "$n" -lt "$max" ]; do
    n=$((n+1))
    if "$@" >> "$LOG_FILE" 2>&1; then
      return 0
    fi
    [ "$n" -lt "$max" ] && warn "$desc falló (intento $n/$max), reintento en 3s..." && sleep 3
  done
  err "$desc falló tras $max intentos. Ver: $LOG_FILE"
  return 1
}

# ─── Instaladores ────────────────────────────────────────────────────────────
install_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then ok "Xcode CLT ya instalado"; return 0; fi
  say "Instalando Xcode Command Line Tools..."
  xcode-select --install >/dev/null 2>&1 || true
  warn "Se abrió un instalador de macOS. Por favor:"
  warn "  1. Aceptá la instalación en la ventana emergente"
  warn "  2. Esperá a que termine (~5-10 min)"
  printf "\nPresioná ENTER cuando termine: "
  read -r _
  if ! xcode-select -p >/dev/null 2>&1; then
    err "Xcode CLT no se detecta."
    return 1
  fi
  ok "Xcode CLT listo"
}

install_homebrew() {
  if check_dep brew; then ok "Homebrew ya instalado"; return 0; fi
  say "Instalando Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    >> "$LOG_FILE" 2>&1 || return 1
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$p" ] && eval "$($p shellenv)" && break
  done
  check_dep brew && ok "Homebrew listo" && return 0
  return 1
}

install_node() {
  if check_dep node; then ok "Node.js ya instalado ($(node --version))"; return 0; fi
  say "Instalando Node.js + npm..."
  if ! check_dep brew; then
    err "Homebrew no está. Activá 'Homebrew' en el menú anterior."
    return 1
  fi
  retry 3 "brew install node" brew install node || return 1
  ok "Node.js listo ($(node --version 2>/dev/null))"
}

install_claude_code() {
  if check_dep claude; then ok "Claude Code CLI ya instalado"; return 0; fi
  say "Instalando Claude Code CLI..."
  if ! check_dep npm; then
    err "npm no está. Node.js debe instalarse primero."
    return 1
  fi
  retry 3 "npm install -g @anthropic-ai/claude-code" \
    npm install -g @anthropic-ai/claude-code || return 1
  ok "Claude Code listo"
}

install_jq() {
  if check_dep jq; then ok "jq ya instalado"; return 0; fi
  say "Instalando jq..."
  if ! check_dep brew; then
    warn "Homebrew no está — salteo jq (no es bloqueante)."
    return 0
  fi
  retry 3 "brew install jq" brew install jq || return 1
  ok "jq listo"
}

clone_repo() {
  if [ -d "$REPO_DIR/.git" ]; then
    say "Actualizando claude-session-sync..."
    git -C "$REPO_DIR" pull --quiet >> "$LOG_FILE" 2>&1 || true
    ok "Repo actualizado en $REPO_DIR"
    return 0
  fi
  say "Clonando claude-session-sync..."
  mkdir -p "$(dirname "$REPO_DIR")"
  retry 3 "git clone" git clone --quiet "$REPO_URL" "$REPO_DIR" || return 1
  ok "Repo clonado en $REPO_DIR"
}

# ─── Manejo de errores ───────────────────────────────────────────────────────
handle_error() {
  local step="$1"
  echo ""
  echo "${BOLD}${RED}╔══════════════════════════════════════════════════════════════════╗${RESET}"
  echo "${BOLD}${RED}║                Hubo un error en la instalación                   ║${RESET}"
  echo "${BOLD}${RED}╚══════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  err "Falló en: ${BOLD}$step${RESET}"
  echo ""
  echo "${BOLD}Qué hacer:${RESET}"
  echo "  1. Abrí un issue en GitHub:"
  echo "     ${BOLD}${CYAN}${GITHUB_ISSUES_URL}${RESET}"
  echo "  2. Pegá el log en el issue (ya lo copiamos a tu portapapeles)"
  echo ""
  echo "${DIM}Log completo en: $LOG_FILE${RESET}"

  if pbcopy < "$LOG_FILE" 2>/dev/null; then
    ok "Log copiado al portapapeles — pegalo en el issue con Cmd+V"
  fi

  # Abrir directamente la página de GitHub Issues
  open "$GITHUB_ISSUES_URL" 2>/dev/null || true

  echo ""
  printf "Presioná ENTER para cerrar: "
  read -r _
  exit 1
}

# ─── Pre-flight checks ───────────────────────────────────────────────────────
preflight() {
  # Drive instalado?
  local has_drive=0
  for p in "$HOME/Mi unidad" "$HOME/My Drive" \
           "$HOME/Library/CloudStorage"/GoogleDrive-*; do
    [ -d "$p" ] && has_drive=1 && break
  done
  if [ "$has_drive" = "0" ]; then
    clear
    echo "${BOLD}${YELLOW}Google Drive Desktop no detectado.${RESET}"
    echo ""
    echo "Antes de continuar necesitás:"
    echo "  1. Descargar Drive desde: ${CYAN}https://www.google.com/drive/download/${RESET}"
    echo "  2. Instalarlo e iniciar sesión con ${BOLD}tu cuenta de Google${RESET}"
    echo "  3. Cambiar a modo 'Replicar archivos' en Preferencias"
    echo "  4. Esperá a que sincronice"
    echo "  5. Volvé a abrir este instalador"
    echo ""
    printf "Presioná ENTER para cerrar: "
    read -r _
    exit 0
  fi
}

# ─── MAIN ────────────────────────────────────────────────────────────────────
main() {
  clear
  log "═══ Instalación iniciada por $USER en $(hostname) ═══"

  # Bienvenida
  cat <<EOF
${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗
║          Setup de Claude Code — claude-session-sync              ║
╚══════════════════════════════════════════════════════════════════╝${RESET}

Hola ${BOLD}$USER${RESET}.

Esto va a configurar tu Mac para usar Claude Code con tus chats, skills,
agents y settings sincronizados entre máquinas vía Google Drive.

${BOLD}Antes de continuar, asegurate de:${RESET}
  ✓ Tener Google Drive Desktop instalado y sincronizando
  ✓ Estar logueado con ${BOLD}tu cuenta de Google${RESET}
  ✓ Tener Drive en modo ${BOLD}"Replicar archivos"${RESET}

${DIM}Si no tenés algo de eso: cerrá esto, configurá Drive, y volvé.${RESET}

EOF
  printf "Presioná ENTER para continuar (o Q para cancelar): "
  IFS= read -rsn1 key
  echo ""
  case "$key" in q|Q) echo "Cancelado."; exit 0 ;; esac

  preflight

  # Detectar qué está instalado + versión
  local xcode_installed=0 brew_installed=0 node_installed=0 claude_installed=0 jq_installed=0
  local xcode_ver="" brew_ver="" node_ver="" claude_ver="" jq_ver=""
  xcode-select -p >/dev/null 2>&1 && xcode_installed=1 && xcode_ver="$(xcode-select -p 2>/dev/null)"
  check_dep brew    && brew_installed=1    && brew_ver="$(brew --version 2>/dev/null | head -1 | awk '{print $2}')"
  check_dep node    && node_installed=1    && node_ver="$(node --version 2>/dev/null)"
  check_dep claude  && claude_installed=1  && claude_ver="$(claude --version 2>/dev/null | head -1 | awk '{print $1}')"
  check_dep jq      && jq_installed=1      && jq_ver="$(jq --version 2>/dev/null)"

  # Registrar items: label, checked, locked, installed, desc, key, version
  add_item "Xcode Command Line Tools (git incluido)" \
           "1" "1" "$xcode_installed" \
           "OBLIGATORIO — git se necesita para descargar plugins desde GitHub." \
           "xcode_clt" "$xcode_ver"
  add_item "Homebrew" \
           "1" "1" "$brew_installed" \
           "OBLIGATORIO — gestor de paquetes para Mac. Sin esto no podemos instalar Node automáticamente." \
           "brew" "$brew_ver"
  add_item "Node.js + npm" \
           "1" "1" "$node_installed" \
           "OBLIGATORIO — Claude Code está hecho con Node." \
           "node" "$node_ver"
  add_item "Claude Code CLI" \
           "1" "1" "$claude_installed" \
           "OBLIGATORIO — el programa principal que vas a usar." \
           "claude_code" "$claude_ver"
  add_item "jq (procesador de JSON)" \
           "1" "0" "$jq_installed" \
           "Recomendado. Hace el cleanup más rápido. Si no lo instalás, se usa python3 (más lento, igual funciona)." \
           "jq" "$jq_ver"
  add_item "Cleanup al cerrar Claude (SessionEnd hook)" \
           "1" "0" "0" \
           "Recomendado. Limpia basura también al cerrar Claude (no solo al abrir)." \
           "session_end" ""
  add_item "Lock multi-Mac (warning si abierto en otra Mac)" \
           "1" "0" "0" \
           "Recomendado. Te avisa si abrís Claude desde 2 Macs simultáneamente." \
           "lock" ""

  # Menú interactivo
  run_menu

  # Resumen + confirmación (solo items pendientes; los instalados se saltan)
  clear
  echo "${BOLD}Vamos a hacer esto:${RESET}"
  echo ""
  local count=0 skipped=0
  for i in "${!ITEMS_LABEL[@]}"; do
    if [ "${ITEMS_INSTALLED[$i]}" = "1" ]; then
      skipped=$((skipped+1))
      continue
    fi
    if [ "${ITEMS_CHECKED[$i]}" = "1" ] || [ "${ITEMS_LOCKED[$i]}" = "1" ]; then
      printf "  ${GREEN}+${RESET} Instalar %s\n" "${ITEMS_LABEL[$i]}"
      count=$((count+1))
    fi
  done
  [ "$skipped" -gt 0 ] && printf "  ${DIM}(%d ya instalados, se saltan)${RESET}\n" "$skipped"
  echo ""
  if [ "$count" = "0" ]; then
    echo "${BOLD}${GREEN}Nada nuevo que instalar.${RESET}"
    echo "Voy a verificar y reparar el setup multi-Mac igual."
    echo ""
    sleep 2
  else
    printf "¿Procedemos? [Y/n]: "
    IFS= read -rsn1 key
    echo ""
    case "$key" in n|N) echo "Cancelado."; exit 0 ;; esac
  fi

  # Ejecutar solo lo NO instalado
  echo ""
  for i in "${!ITEMS_LABEL[@]}"; do
    [ "${ITEMS_INSTALLED[$i]}" = "1" ] && continue
    if [ "${ITEMS_CHECKED[$i]}" != "1" ] && [ "${ITEMS_LOCKED[$i]}" != "1" ]; then continue; fi
    case "${ITEMS_KEY[$i]}" in
      xcode_clt)    install_xcode_clt    || handle_error "Xcode CLT" ;;
      brew)         install_homebrew     || handle_error "Homebrew" ;;
      node)         install_node         || handle_error "Node.js" ;;
      claude_code)  install_claude_code  || handle_error "Claude Code CLI" ;;
      jq)           install_jq           || handle_error "jq" ;;
      session_end|lock)  : ;;  # se configuran via bootstrap
    esac
  done

  # Clonar repo
  clone_repo || handle_error "git clone del repo"

  # Bootstrap
  say "Ejecutando setup multi-Mac (bootstrap)..."
  if ! bash "$REPO_DIR/bootstrap-claude.sh" 2>&1 | tee -a "$LOG_FILE"; then
    handle_error "bootstrap-claude.sh"
  fi

  # Final
  clear
  cat <<EOF
${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════════╗
║                       ¡Setup completo!                           ║
╚══════════════════════════════════════════════════════════════════╝${RESET}

${BOLD}Próximos pasos:${RESET}
  1. Abrí una nueva terminal
  2. Ejecutá:
     ${CYAN}cd "\$HOME/Mi unidad"${RESET}    ${DIM}# (o donde guardes tus proyectos)${RESET}
     ${CYAN}claude --resume${RESET}

Vas a ver todos tus chats, skills, agents y settings sincronizados.

${BOLD}Si algo falla en el futuro:${RESET}
  Doble clic en este mismo archivo (${BOLD}install.command${RESET}).
  → Detecta qué hay, qué falta y qué está roto. Repara todo solo.

${DIM}Log de esta instalación: $LOG_FILE${RESET}
${DIM}Setup multi-Mac: $REPO_DIR${RESET}

EOF
  printf "Presioná ENTER para cerrar: "
  read -r _
  log "═══ Instalación finalizada con éxito ═══"
}

main "$@"
