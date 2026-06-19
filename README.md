# Claude Code Sync

> Usá [Claude Code](https://docs.anthropic.com/en/docs/claude-code) en cualquier
> Mac con la **misma experiencia**: chats, skills, agents, memoria y settings
> sincronizados entre máquinas vía Google Drive — sin basura, sin paths
> hardcodeados, con auto-reparación.

```
 ┌──────────────────────────────────────────────────────────────────┐
 │  Drive sincroniza lo que importa.   Local guarda lo que se       │
 │  regenera.   Auto-cleanup en cada sesión.   Cero acción manual.  │
 └──────────────────────────────────────────────────────────────────┘
```

---

## Instalación en una Mac nueva

**Solo dos pasos manuales. Lo demás lo hace el wizard.**

### Paso 1 — Configurar Google Drive (~5 min)

1. Descargá Google Drive Desktop: <https://www.google.com/drive/download/>
2. Iniciá sesión con tu cuenta de Google.
3. En el ícono de Drive (barra de menú) → ⚙ Preferencias → **Mi unidad** →
   activá **"Replicar archivos"**.
4. Esperá a que Drive sincronice (~1-3 min la primera vez).

> Por qué Replicar: en modo "Transmitir" los archivos están en la nube y
> Claude Code da timeout al leerlos. Necesitamos los archivos en disco real.

### Paso 2 — Descargar y abrir el wizard

**Descargá el zip desde Releases:**

<https://github.com/jefermorales/claude-session-sync/releases/latest>

1. Descargá `Claude-Code-Sync.zip` (vas a verlo en "Assets")
2. **Doble clic en el ZIP** → macOS lo descomprime y aparece la carpeta
   **"Claude Code Sync"**
3. Entrá a esa carpeta y hacé **doble clic en `launch.command`**

> ⚠️ **La primera vez, macOS bloquea** (Gatekeeper). Una vez y nunca más:
>
> - **Click derecho** sobre `launch.command` → **Abrir** → en el diálogo,
>   apretá **Abrir** otra vez.
> - Si en Sequoia no ves "Abrir" en el diálogo:
>   → **Configuración del sistema → Privacidad y seguridad → Seguridad →
>   "Abrir de todos modos"**.

### Qué pasa al hacer doble clic

- Por **~1 segundo** se ve una terminal arrancando Python
- Después se abre **Safari automáticamente** con el wizard en
  `http://127.0.0.1:8765/`
- Vas a ver una UI nativa macOS con:
  - **Bienvenida**
  - **Verificación de Drive** (debe estar instalado + modo Replicar)
  - **Componentes** — checkboxes nativos, items ya instalados aparecen
    deshabilitados con su versión
  - **Instalando** — progreso en vivo con cada paso
  - **Listo** — comando para arrancar Claude

### Después de instalar

```bash
cd "$HOME/Mi unidad"     # o donde guardes tus proyectos
claude --resume
```

Ves todos tus chats, skills, agents y settings sincronizados.

---

## Reparar / actualizar — el mismo wizard

**Un solo archivo, una sola app.** El `launch.command` que usaste para
instalar es el mismo que usás para reparar o actualizar.

Cuando algo se rompa (rarísimo) o querás verificar el estado:
**doble clic en `launch.command`**.

- Detecta qué hay instalado y qué falta
- Items ya instalados aparecen ✓ con su versión actual
- Solo elegís entre lo que falte
- Si TODO está instalado, salta el menú y va directo a reparar/verificar
- Si la reparación falla, abre GitHub Issues con el log al portapapeles

---

## Alternativa para usuarios de terminal

Si preferís un instalador estilo CLI con checkboxes navegables por teclado:

```bash
bash install.command
```

Hace exactamente lo mismo pero en terminal. Útil para SSH o entornos donde
no hay browser disponible.

---

## Cómo funciona

**Filosofía:** Drive sincroniza lo que afecta tu experiencia. Local guarda
lo regenerable.

| Vive en Drive (portable) | Vive en `~/.claude-local/` (no sync) |
|---|---|
| `projects/` (chats) | `plugins/marketplaces/` (.git pesado) |
| `skills/` | `plugins/cache/` |
| `agents/` | `plugins/data/` |
| `memory/` | `file-history/`, `shell-snapshots/` |
| `plans/` | `paste-cache/`, `image-cache/` |
| `settings.json` + `settings.local.json` | `cache/`, `chrome/`, `daemon/` |
| `installed_plugins.json` (la lista) | `tasks/`, `jobs/`, `sessions/` |
| `known_marketplaces.json` (la lista) | `backups/`, `ide/`, `session-env/` |

Cuando cambiás de Mac, los plugins se **re-clonan automáticamente** desde
GitHub usando `known_marketplaces.json`. Nunca subís un `.git/` a Drive.

### Qué hace el bootstrap

1. **Detecta Google Drive** (locale es/en, paths nuevos y viejos)
2. **Symlinkea** `~/.claude` → `Mi unidad/.claude`
3. **Adapta paths al usuario** (`-Users-{viejo}-…` → `-Users-{nuevo}-…`)
4. **Adapta locale** (`Mi-unidad` ↔ `My-Drive` en los paths)
5. **Mueve a `~/.claude-local`** todo lo regenerable/pesado/.git
6. **Re-clona marketplaces** desde GitHub a local (lee `known_marketplaces.json`)
7. **Limpia basura acumulada** (`.DS_Store`, duplicados `(2)`, `.tmp.driveupload/*`)
8. **Instala hooks** de cleanup + lock multi-Mac en `settings.json`
9. **Reporta** qué hizo

### Limpieza automática (hooks SessionStart + SessionEnd)

Cada vez que **abrís** Claude Code (`SessionStart`) y cada vez que **cerrás**
una sesión (`SessionEnd`), el script corre cleanup:

- Borra `.DS_Store` recursivos
- Borra duplicados `(2)`, `(3)` en `marketplaces/`
- Limpia `.tmp.driveupload/`, `.tmp.drivedownload/` (>1 día = basura)
- Borra archivos con sufijo `"Conflicted copy"` (conflictos de Drive)
- Renombra carpetas si cambiaste el `$USER` de la Mac
- Borra caches viejas (image, paste, shell, file-history)
- En `SessionEnd`: libera el lock multi-Mac
- Loguea cada corrida en `~/.claude-local/cleanup.log`

**Resultado:** la basura nunca se acumula. Drive nunca recibe lo que no debe.

### Refuerzo extra: xattr `com.google.drivefs.ignore`

El bootstrap marca los symlinks de `plugins/marketplaces/`, `plugins/cache/` y
`plugins/data/` con el atributo extendido `com.google.drivefs.ignore`. Esto le
dice a Drive **a nivel de sistema** que NUNCA suba esas rutas — aunque algo se
cuele por error, Drive las ignora.

### Tolerante a cambio de nombre de usuario

Cero paths absolutos hardcodeados:

- **Hooks en `settings.json`** usan `$HOME` (no `/Users/{nombre}/...`). Si
  renombrás el usuario, `$HOME` cambia y el hook se resuelve al nuevo path.
- **El cleanup auto-repara** el symlink `~/.claude` si quedó roto.
- **El cleanup re-copia** el script desde el repo clonado si desapareció de
  `~/.claude-local/`.
- **El cleanup renombra** las carpetas `-Users-{viejo}-...` →
  `-Users-{nuevo}-...` cuando detecta que `$USER` cambió.

En la primera apertura de Claude tras un cambio de usuario, el hook
`SessionStart` repara todo solo. **Sin acción manual.**

### Detección multi-Mac

Si abrís Claude en otra Mac mientras una sesión está activa (<5 min), te avisa:

```
⚠ Claude Code parece activo en 'MacBook-Air' (hace 47s).
  Drive puede generar conflictos si usás ambas Macs a la vez.
```

Es un warning, no un bloqueo. Usa el lock file `.claude/.active-session.json`.

> Drive Mirror no soporta concurrencia segura. Para uso simultáneo real
> habría que migrar a un repo Git. Por ahora: una Mac a la vez.

---

## Stack técnico

El wizard es lo más liviano que puede ser sin caer en Electron:

| Pieza | Tecnología | Tamaño |
|---|---|---|
| Backend | Python 3 stdlib (sin pip) | 15 KB |
| Frontend | HTML + CSS + JS vanilla (sin frameworks) | 26 KB |
| Launcher | bash | 2 KB |
| **Total** | — | **~50 KB descomprimido** |

- Sin Apple Developer cert (gratis, sin $99/año)
- Sin npm, sin Electron, sin dependencies
- Python viene preinstalado con Xcode CLT
- HTML/CSS/JS lo renderiza Safari o tu browser por default

---

## Comandos

```bash
# Wizard web (recomendado)
open "Claude Code Sync/launch.command"

# Wizard de terminal (alternativa CLI)
bash install.command

# Bootstrap directo (sin wizard, asumiendo deps instaladas)
bash bootstrap-claude.sh                 # Setup completo (idempotente)
bash bootstrap-claude.sh --cleanup       # Cleanup (hook SessionStart)
bash bootstrap-claude.sh --session-end   # Cleanup + libera lock (hook SessionEnd)
bash bootstrap-claude.sh --lock-check    # Lock-check (hook SessionStart)
bash bootstrap-claude.sh --help          # Ayuda
```

---

## Troubleshooting

### El wizard no se abre — "Apple no pudo verificar..."

Gatekeeper de macOS. Una vez:

- **Click derecho** sobre `launch.command` → **Abrir** → **Abrir**
- Si en Sequoia no aparece "Abrir": **Configuración → Privacidad y seguridad
  → "Abrir de todos modos"**

### El wizard se abre pero el browser no carga

Andá manualmente a <http://127.0.0.1:8765/>. Si tampoco carga: hay otro
proceso ocupando el puerto. Cerrá cualquier instancia anterior del wizard
con `pkill -f "wizard/server.py"`.

### `claude --resume` no muestra mis chats

1. Confirmá que estás en el directorio correcto
   (ej: `cd "$HOME/Mi unidad"`).
2. Confirmá que Drive terminó de sincronizar:
   `du -sh "$HOME/Mi unidad/.claude/"` debe ser >50 MB.
3. Doble clic en `launch.command` para verificar/reparar.

### Drive sigue acumulando errores

Doble clic en `launch.command`. Re-correr limpia basura y rearma symlinks.
Si persiste: salí de Drive (ícono → Salir), reabrilo. Eso fuerza un
re-escaneo del filesystem y limpia su cola fantasma.

### Quiero borrar `~/.claude-local` y empezar de cero

Lo podés hacer. El wizard regenera todo en la próxima corrida (caches
vacías, marketplaces re-clonados). Solo perdés caches efímeros — **tus
chats, skills y settings están en Drive, no se tocan**.

---

## Para forkear

Si querés hostear tu propia versión:

1. Fork desde GitHub
2. En `wizard/server.py`, cambiá:
   ```python
   subprocess.run(f"git clone https://github.com/jefermorales/claude-session-sync.git ...")
   ```
   por tu repo.
3. En `wizard/launch.command`, cambiá la URL del clone.
4. Push.

---

## Qué NO se porta automáticamente

- **`~/.claude.json`** (config de runtime). Se regenera sola en cada Mac.
- **Node.js, npm, Claude Code CLI**: binarios del sistema. El wizard
  los pone en cada Mac.

---

## Licencia

MIT.
