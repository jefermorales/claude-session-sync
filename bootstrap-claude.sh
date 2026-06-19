#!/usr/bin/env bash
# bootstrap-claude.sh — Setup completo de Claude Code multi-Mac vía Google Drive.
#
# Filosofía:
#   - Lo "portable" vive en Drive (chats, skills, settings, agents, memoria).
#   - Lo "regenerable/pesado/.git" vive en ~/.claude-local (no se sube a Drive).
#   - Filtros y limpieza automática para que la basura nunca llegue a la nube.
#
# Modos:
#   bash bootstrap-claude.sh                  → setup completo (idempotente)
#   bash bootstrap-claude.sh --cleanup        → limpieza rápida (hook SessionStart)
#   bash bootstrap-claude.sh --lock-check     → check de Mac activa (hook SessionStart)
#   bash bootstrap-claude.sh --help

set -euo pipefail

# ─── Helpers ─────────────────────────────────────────────────────────────────
say()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m ✓\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m ⚠\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m ✗\033[0m %s\n" "$*" >&2; exit 1; }

LOCAL="$HOME/.claude-local"
SCRIPT_PATH_INSTALLED="$LOCAL/bootstrap-claude.sh"

# ─── Detección de Drive ──────────────────────────────────────────────────────
detect_drive() {
  DRIVE=""
  for p in "$HOME/Mi unidad" "$HOME/My Drive"; do
    [ -d "$p" ] && DRIVE="$p" && return 0
  done
  for p in "$HOME/Library/CloudStorage"/GoogleDrive-*/"Mi unidad" \
           "$HOME/Library/CloudStorage"/GoogleDrive-*/"My Drive"; do
    [ -d "$p" ] && DRIVE="$p" && return 0
  done
  return 1
}

# ═══════════════════════════════════════════════════════════════════════════
# MODO: --cleanup  (limpieza rápida, se invoca como hook SessionStart)
# ═══════════════════════════════════════════════════════════════════════════
cleanup_mode() {
  # Tolerante a errores: si algo falla, no rompemos la sesión de Claude.
  set +e
  detect_drive || exit 0
  CLAUDE_DIR="$DRIVE/.claude"
  [ -d "$CLAUDE_DIR" ] || exit 0
  mkdir -p "$LOCAL"

  local removed=0
  local renamed=0
  local repaired=0
  local release_lock="${1:-keep-lock}"

  # 0. AUTO-REPAIR: detectar paths rotos por cambio de usuario y repararlos
  # Symlink ~/.claude roto o ausente
  if [ -L "$HOME/.claude" ] && [ ! -e "$HOME/.claude" ]; then
    rm -f "$HOME/.claude"
    ln -s "$CLAUDE_DIR" "$HOME/.claude"
    repaired=$((repaired+1))
  elif [ ! -e "$HOME/.claude" ]; then
    ln -s "$CLAUDE_DIR" "$HOME/.claude" 2>/dev/null && repaired=$((repaired+1))
  fi

  # Script local desaparecido: re-copiar desde el repo si existe
  local self_path="$LOCAL/bootstrap-claude.sh"
  if [ ! -f "$self_path" ]; then
    for candidate in "$HOME/Developer/claude-session-sync/bootstrap-claude.sh" \
                     "$HOME/claude-session-sync/bootstrap-claude.sh"; do
      if [ -f "$candidate" ]; then
        cp "$candidate" "$self_path"
        chmod +x "$self_path"
        repaired=$((repaired+1))
        break
      fi
    done
  fi

  # 1. Basura de macOS dentro de .claude/
  while IFS= read -r f; do rm -f "$f" && removed=$((removed+1)); done \
    < <(find "$CLAUDE_DIR" -name ".DS_Store" 2>/dev/null)
  while IFS= read -r f; do rm -f "$f" && removed=$((removed+1)); done \
    < <(find "$CLAUDE_DIR" -name 'Icon?' 2>/dev/null)

  # 2. Duplicados (2), (3)... en marketplaces/ (basura de conflictos Drive)
  while IFS= read -r d; do rm -rf "$d" && removed=$((removed+1)); done \
    < <(find "$CLAUDE_DIR/plugins/marketplaces" -maxdepth 1 -type d -name "* (*)" 2>/dev/null)

  # 3. Carpetas temporales de Drive en CUALQUIER subcarpeta (>1 día = basura)
  find "$DRIVE" -maxdepth 3 -type d \( -name ".tmp.driveupload" -o -name ".tmp.drivedownload" \) \
    -exec find {} -mindepth 1 -mtime +1 -delete \; 2>/dev/null

  # 4. Caches locales viejas (no afectan UX, se regeneran)
  find "$LOCAL/image-cache" -type f -mtime +30 -delete 2>/dev/null
  find "$LOCAL/paste-cache" -type f -mtime +7 -delete 2>/dev/null
  find "$LOCAL/shell-snapshots" -type f -mtime +7 -delete 2>/dev/null
  find "$LOCAL/file-history" -type f -mtime +60 -delete 2>/dev/null

  # 5. NUEVO: Archivos "Conflicted copy" que Drive crea ante conflictos de sync
  while IFS= read -r f; do rm -f "$f" && removed=$((removed+1)); done \
    < <(find "$CLAUDE_DIR" -iname "*conflicted copy*" 2>/dev/null)
  while IFS= read -r f; do rm -f "$f" && removed=$((removed+1)); done \
    < <(find "$DRIVE" -maxdepth 3 -iname "*conflicted copy*" 2>/dev/null)

  # 6. NUEVO: Auto-rename si el $USER cambió desde la última corrida
  if [ -d "$CLAUDE_DIR/projects" ]; then
    pushd "$CLAUDE_DIR/projects" >/dev/null 2>&1 || true
    for d in -Users-*/; do
      [ -d "$d" ] || continue
      local dname="${d%/}"
      local old_user; old_user=$(echo "$dname" | cut -d- -f3)
      [ -z "$old_user" ] && continue
      if [ "$old_user" != "$USER" ]; then
        local new_dname; new_dname=$(echo "$dname" | sed "s/^-Users-${old_user}-/-Users-${USER}-/")
        if [ ! -d "$new_dname" ]; then
          mv -- "$dname" "$new_dname" 2>/dev/null && renamed=$((renamed+1))
        fi
      fi
    done
    popd >/dev/null 2>&1 || true
  fi

  # 7. SessionEnd: liberar el lock multi-Mac
  if [ "$release_lock" = "release-lock" ]; then
    rm -f "$CLAUDE_DIR/.active-session.json" 2>/dev/null
  fi

  # 8. Log al cleanup.log local
  printf "[%s] cleanup: %d removed, %d renamed, %d repaired (mode=%s)\n" \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$removed" "$renamed" "$repaired" "$release_lock" >> "$LOCAL/cleanup.log"

  exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
# MODO: --session-end  (cleanup + libera el lock al cerrar Claude)
# ═══════════════════════════════════════════════════════════════════════════
session_end_mode() {
  cleanup_mode "release-lock"
}

# ═══════════════════════════════════════════════════════════════════════════
# MODO: --lock-check  (warning si Claude está abierto en otra Mac)
# ═══════════════════════════════════════════════════════════════════════════
lock_check_mode() {
  set +e
  detect_drive || exit 0
  CLAUDE_DIR="$DRIVE/.claude"
  local lock="$CLAUDE_DIR/.active-session.json"
  local my_host; my_host=$(hostname -s)
  local now; now=$(date +%s)

  # Si hay lock existente, ver si es de OTRA máquina y reciente (<5 min)
  if [ -f "$lock" ]; then
    local other_host other_ts age
    other_host=$(python3 -c "import json,sys; print(json.load(open('$lock'))['hostname'])" 2>/dev/null || echo "")
    other_ts=$(python3 -c "import json,sys; print(json.load(open('$lock'))['timestamp'])" 2>/dev/null || echo "0")
    age=$((now - other_ts))
    if [ -n "$other_host" ] && [ "$other_host" != "$my_host" ] && [ "$age" -lt 300 ]; then
      printf "\033[1;33m⚠ Claude Code parece activo en '%s' (hace %ds).\033[0m\n" "$other_host" "$age" >&2
      printf "\033[1;33m  Drive puede generar conflictos si usás ambas Macs a la vez.\033[0m\n" >&2
    fi
  fi

  # Escribir/refrescar lock con MIS datos
  printf '{"hostname":"%s","pid":%d,"timestamp":%d}\n' "$my_host" "$$" "$now" > "$lock" 2>/dev/null
  exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
# MODO: --help
# ═══════════════════════════════════════════════════════════════════════════
help_mode() {
  cat <<EOF
bootstrap-claude.sh — Setup multi-Mac de Claude Code vía Google Drive

USO:
  bash bootstrap-claude.sh                 Setup completo (idempotente)
  bash bootstrap-claude.sh --cleanup       Limpieza rápida (hook SessionStart)
  bash bootstrap-claude.sh --session-end   Cleanup + libera lock (hook SessionEnd)
  bash bootstrap-claude.sh --lock-check    Check de Mac activa (hook SessionStart)
  bash bootstrap-claude.sh --help          Esta ayuda

QUÉ HACE EL SETUP:
  1. Detecta Google Drive (es/en, paths nuevos y viejos)
  2. Symlinkea ~/.claude → Drive
  3. Adapta paths de conversaciones al usuario actual de la Mac
  4. Adapta el locale (Mi unidad ↔ My Drive)
  5. Mueve a ~/.claude-local todo lo regenerable/pesado/.git
  6. Re-clona marketplaces de plugins desde GitHub a local
  7. Limpia basura acumulada (.DS_Store, duplicados, tmp de Drive)
  8. Instala los hooks de cleanup + lock multi-Mac
  9. Reporta qué hizo

PORTABLE (en Drive):
  projects/ skills/ agents/ memory/ plans/ settings.json
  installed_plugins.json known_marketplaces.json

LOCAL (NO se sube a Drive):
  plugins/marketplaces/  plugins/cache/  plugins/data/
  file-history/ shell-snapshots/ paste-cache/ image-cache/
  cache/ chrome/ daemon/ tasks/ jobs/ sessions/ backups/
  ide/ session-env/ __pycache__/
EOF
  exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
# MODO: setup completo (default)
# ═══════════════════════════════════════════════════════════════════════════

full_bootstrap() {

# ─── 1) Detectar Google Drive ────────────────────────────────────────────────
say "Detectando Google Drive..."
detect_drive || die "No encontré Google Drive. Instalalo, iniciá sesión y activá modo 'Replicar archivos'."
ok "Drive en: $DRIVE"
CLAUDE_DIR="$DRIVE/.claude"

# ─── 2) Validar modo "Replicar archivos" ─────────────────────────────────────
[ -d "$CLAUDE_DIR" ] || die "$CLAUDE_DIR no existe. Esperá a que Drive sincronice."
size_mb=$(du -sm "$CLAUDE_DIR" 2>/dev/null | cut -f1 || echo 0)
if [ "$size_mb" -lt 50 ]; then
  warn ".claude/ pesa solo ${size_mb} MB — probablemente Drive en modo Transmitir."
  warn "Cambialo a 'Replicar archivos' (Preferencias → tu cuenta → Mi unidad → Replicar)."
  printf "   ¿Continuar igual? [y/N]: "; read -r c
  [ "${c:-N}" = "y" ] || exit 1
else
  ok ".claude/ pesa ${size_mb} MB (sincronizado)"
fi

# ─── 3) Symlink ~/.claude → Drive ────────────────────────────────────────────
say "Configurando ~/.claude..."
if [ -L "$HOME/.claude" ]; then
  current=$(readlink "$HOME/.claude")
  if [ "$current" = "$CLAUDE_DIR" ]; then
    ok "~/.claude ya apunta a Drive"
  else
    bak="$HOME/.claude.symlink-backup-$(date +%s)"
    mv "$HOME/.claude" "$bak"
    ln -s "$CLAUDE_DIR" "$HOME/.claude"
    ok "symlink redirigido (backup: $bak)"
  fi
elif [ -e "$HOME/.claude" ]; then
  bak="$HOME/.claude.local-backup-$(date +%s)"
  mv "$HOME/.claude" "$bak"
  ln -s "$CLAUDE_DIR" "$HOME/.claude"
  ok "~/.claude local movido a $bak; symlink creado"
else
  ln -s "$CLAUDE_DIR" "$HOME/.claude"
  ok "symlink creado"
fi

# ─── 4) Adaptar projects/ al $USER actual ────────────────────────────────────
say "Adaptando project folders al usuario '$USER'..."
cd "$CLAUDE_DIR/projects" 2>/dev/null || { warn "No hay carpeta projects/"; }
renamed=0
if [ "$(pwd)" = "$CLAUDE_DIR/projects" ]; then
  for d in -Users-*/; do
    [ -d "$d" ] || continue
    dname="${d%/}"
    old_user=$(echo "$dname" | cut -d- -f3)
    [ -z "$old_user" ] && continue
    if [ "$old_user" != "$USER" ]; then
      new_dname=$(echo "$dname" | sed "s/^-Users-${old_user}-/-Users-${USER}-/")
      if [ -d "$new_dname" ]; then
        warn "$new_dname ya existe; salto $dname"
      else
        mv -- "$dname" "$new_dname"
        echo "   $dname  →  $new_dname"
        renamed=$((renamed+1))
      fi
    fi
  done
fi
ok "$renamed carpetas renombradas por usuario"

# ─── 5) Adaptar locale (Mi unidad ↔ My Drive) ────────────────────────────────
drive_basename=$(basename "$DRIVE")
drive_segment=$(echo "$drive_basename" | sed 's/ /-/g')
other_segments=("Mi-unidad" "My-Drive")
locale_renamed=0
for other in "${other_segments[@]}"; do
  [ "$other" = "$drive_segment" ] && continue
  for d in -Users-*/; do
    [ -d "$d" ] || continue
    dname="${d%/}"
    [[ "$dname" == *-${other}* ]] || continue
    new_dname=$(echo "$dname" | sed "s/-${other}/-${drive_segment}/g")
    if [ ! -d "$new_dname" ]; then
      mv -- "$dname" "$new_dname"
      echo "   (locale) $dname  →  $new_dname"
      locale_renamed=$((locale_renamed+1))
    fi
  done
done
[ "$locale_renamed" -gt 0 ] && ok "$locale_renamed adaptadas al locale '$drive_basename'" \
                            || ok "locale '$drive_basename' ya coincide"

# ─── 6) Split Drive vs Local: mover cosas regenerables/pesadas fuera ─────────
say "Higiene de sync: regenerable/pesado fuera de Drive..."
mkdir -p "$LOCAL"

# Carpetas que NO deben sincronizarse a Drive
JUNK=(
  file-history shell-snapshots paste-cache image-cache cache
  __pycache__ chrome daemon tasks jobs sessions
  nexus-venv nexus-trash
  backups ide session-env
)

relocate() {
  local rel="$1"
  local src="$CLAUDE_DIR/$rel"
  local dst="$LOCAL/$rel"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$src" ]; then
    if [ -e "$src" ] && [ "$(readlink "$src")" = "$dst" ]; then
      # Ya está bien — solo reaplicamos el xattr por si acaso
      xattr -w com.google.drivefs.ignore "" "$src" 2>/dev/null || true
      return
    fi
    rm -f "$src"; mkdir -p "$dst"; ln -s "$dst" "$src"
  elif [ -d "$src" ]; then
    if [ -d "$dst" ]; then rm -rf "$src"; else mv "$src" "$dst"; fi
    ln -s "$dst" "$src"
  else
    mkdir -p "$dst"; ln -s "$dst" "$src"
  fi
  # xattr para que Drive ignore el symlink (refuerzo: ni siquiera lo intenta)
  xattr -w com.google.drivefs.ignore "" "$src" 2>/dev/null || true
}

moved=0
for j in "${JUNK[@]}"; do
  was_real=$([ -e "$CLAUDE_DIR/$j" ] && [ ! -L "$CLAUDE_DIR/$j" ] && echo 1 || echo 0)
  relocate "$j"
  [ "$was_real" = "1" ] && moved=$((moved+1))
done

# Split de plugins/: la lista SE QUEDA en Drive, los repos van LOCAL
say "Split de plugins/ (lista en Drive, marketplaces/cache/data en local)..."
mkdir -p "$LOCAL/plugins"

# Mover marketplaces, cache, data a local
for sub in marketplaces cache data; do
  was_real=$([ -e "$CLAUDE_DIR/plugins/$sub" ] && [ ! -L "$CLAUDE_DIR/plugins/$sub" ] && echo 1 || echo 0)
  relocate "plugins/$sub"
  [ "$was_real" = "1" ] && moved=$((moved+1))
done

ok "Higiene aplicada ($moved carpetas movidas a $LOCAL)"

# ─── 7) Re-clonar marketplaces desde GitHub (a local) ────────────────────────
say "Re-clonando marketplaces de plugins (a local)..."
KM="$CLAUDE_DIR/plugins/known_marketplaces.json"
if [ -f "$KM" ] && command -v python3 >/dev/null 2>&1; then
  python3 - "$KM" "$LOCAL/plugins/marketplaces" <<'PYEOF'
import json, os, subprocess, sys
km_path, dest_root = sys.argv[1], sys.argv[2]
os.makedirs(dest_root, exist_ok=True)
try:
    with open(km_path) as f: km = json.load(f)
except Exception as e:
    print(f"   (no se pudo leer known_marketplaces.json: {e})"); sys.exit(0)
cloned = 0
for name, meta in km.items():
    src = meta.get("source", {})
    if src.get("source") != "github": continue
    repo = src.get("repo")
    if not repo: continue
    dest = os.path.join(dest_root, name)
    if os.path.exists(os.path.join(dest, ".git")):
        # ya clonado: pull
        subprocess.run(["git", "-C", dest, "pull", "--quiet"], check=False)
        print(f"   ✓ {name} actualizado")
    else:
        os.makedirs(dest, exist_ok=True)
        r = subprocess.run(["git", "clone", "--quiet", f"https://github.com/{repo}.git", dest])
        if r.returncode == 0:
            print(f"   ✓ {name} clonado desde {repo}")
            cloned += 1
        else:
            print(f"   ✗ falló clone de {repo}")
print(f"   total nuevos: {cloned}")
PYEOF
  ok "Marketplaces sincronizados"
else
  warn "No hay known_marketplaces.json o falta python3 — saltando re-clone."
fi

# ─── 8) Limpieza profunda de basura existente ────────────────────────────────
say "Limpiando basura acumulada..."

# .DS_Store recursivos en .claude
n=$(find "$CLAUDE_DIR" -name ".DS_Store" 2>/dev/null | wc -l | tr -d ' ')
find "$CLAUDE_DIR" -name ".DS_Store" -delete 2>/dev/null
[ "$n" -gt 0 ] && ok "$n .DS_Store borrados"

# Icon\r
find "$CLAUDE_DIR" -name 'Icon?' -delete 2>/dev/null

# Duplicados (2), (3) en marketplaces
n=$(find "$CLAUDE_DIR/plugins/marketplaces" -maxdepth 1 -type d -name "* (*)" 2>/dev/null | wc -l | tr -d ' ')
find "$CLAUDE_DIR/plugins/marketplaces" -maxdepth 1 -type d -name "* (*)" -exec rm -rf {} + 2>/dev/null
[ "$n" -gt 0 ] && ok "$n duplicados de marketplaces borrados"

# .tmp.driveupload y .tmp.drivedownload en cualquier subcarpeta (basura atascada)
total=0
while IFS= read -r tmp; do
  n=$(ls -A "$tmp" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n" -gt 0 ]; then
    find "$tmp" -mindepth 1 -delete 2>/dev/null
    total=$((total + n))
  fi
done < <(find "$DRIVE" -maxdepth 3 -type d \( -name ".tmp.driveupload" -o -name ".tmp.drivedownload" \) 2>/dev/null)
[ "$total" -gt 0 ] && ok "$total items borrados de carpetas .tmp.drive* de Drive"

# ─── 9) Auto-copia del script a ~/.claude-local (para los hooks) ─────────────
# Los hooks usan $HOME/.claude-local/bootstrap-claude.sh — sin paths absolutos.
# Si el $USER cambia, $HOME apunta al nuevo home y todo sigue funcionando.
say "Instalando script en ubicación estable..."
SCRIPT_SRC="${BASH_SOURCE[0]}"
[ -f "$SCRIPT_SRC" ] || SCRIPT_SRC="$0"
if [ -f "$SCRIPT_SRC" ] && [ "$(realpath "$SCRIPT_SRC" 2>/dev/null || echo "$SCRIPT_SRC")" != "$(realpath "$SCRIPT_PATH_INSTALLED" 2>/dev/null || echo "$SCRIPT_PATH_INSTALLED")" ]; then
  cp "$SCRIPT_SRC" "$SCRIPT_PATH_INSTALLED"
  chmod +x "$SCRIPT_PATH_INSTALLED"
  ok "Script copiado a \$HOME/.claude-local/bootstrap-claude.sh"
else
  ok "Script ya está en \$HOME/.claude-local/ (no se sobreescribe)"
fi

# ─── 10) Configurar hooks (cleanup + lock-check) en settings.json ────────────
say "Configurando hooks (SessionStart)..."
SETTINGS="$CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1; then
  python3 - "$SETTINGS" <<'PYEOF'
import json, sys
settings_path = sys.argv[1]
with open(settings_path) as f: s = json.load(f)

# Usamos $HOME para que cada Mac resuelva su propio home al ejecutar el hook.
# Esto sobrevive a cambios de nombre de usuario sin necesidad de regenerar settings.
SCRIPT = '"$HOME/.claude-local/bootstrap-claude.sh"'
cleanup_cmd     = f"bash {SCRIPT} --cleanup"
lock_cmd        = f"bash {SCRIPT} --lock-check"
session_end_cmd = f"bash {SCRIPT} --session-end"

hooks = s.setdefault("hooks", {})

def upsert_block(event_name, hook_cmds):
    bucket = hooks.setdefault(event_name, [])
    for block in bucket:
        if isinstance(block, dict) and block.get("matcher") == "claude-session-sync":
            block["hooks"] = [{"type": "command", "command": c} for c in hook_cmds]
            return
    bucket.append({
        "matcher": "claude-session-sync",
        "hooks": [{"type": "command", "command": c} for c in hook_cmds],
    })

# SessionStart: cleanup + lock-check
upsert_block("SessionStart", [cleanup_cmd, lock_cmd])
# SessionEnd: cleanup + libera el lock al cerrar
upsert_block("SessionEnd", [session_end_cmd])

with open(settings_path, "w") as f: json.dump(s, f, indent=2)
print(f"   SessionStart → {cleanup_cmd}")
print(f"                  {lock_cmd}")
print(f"   SessionEnd   → {session_end_cmd}")
PYEOF
  ok "Hooks instalados en settings.json"
else
  warn "Sin settings.json o python3 — saltando configuración de hooks"
fi

# ─── 11) Reporte final ───────────────────────────────────────────────────────
total=$(ls -d "$CLAUDE_DIR"/projects/-Users-*/ 2>/dev/null | wc -l | tr -d ' ')
local_size=$(du -sh "$LOCAL" 2>/dev/null | cut -f1)
drive_size=$(du -sh "$CLAUDE_DIR" 2>/dev/null | cut -f1)

echo ""
say "Setup completo."
echo "   📊 Resumen:"
echo "      $total carpetas de proyecto (chats)"
echo "      Drive (.claude):  $drive_size"
echo "      Local (.claude-local): $local_size"
echo ""
echo "   ✅ Portable en Drive: projects, skills, agents, memory, settings, listas de plugins"
echo "   📦 Local (no sync):   marketplaces/.git, caches, file-history, shell-snapshots"
echo "   🔁 Hooks activos:     cleanup + lock-check en cada SessionStart"
echo ""
echo "   Próximo paso:"
echo "      cd \"$DRIVE\"   # o donde guardes tus proyectos"
echo "      claude --resume"
echo ""
}

# ─── Argparsing ──────────────────────────────────────────────────────────────
case "${1:-}" in
  --cleanup)      cleanup_mode "keep-lock" ;;
  --session-end)  session_end_mode ;;
  --lock-check)   lock_check_mode ;;
  --help|-h)      help_mode ;;
  "")             full_bootstrap ;;
  *)              die "Flag desconocido: $1 (usá --help)" ;;
esac
