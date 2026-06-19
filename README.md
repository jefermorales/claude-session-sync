# claude-session-sync

Usá [Claude Code](https://docs.anthropic.com/en/docs/claude-code) en cualquier
Mac con la **misma experiencia**: tus chats, skills, agents, memoria y
configuración te siguen entre máquinas vía Google Drive.

- Solo lo portable viaja a Drive (chats, skills, settings).
- Lo regenerable/pesado (`.git/` de plugins, caches) vive local y **nunca** sube.
- Auto-limpieza en cada sesión: nunca acumulás basura.
- Tolerante a cambio de nombre de usuario sin acción manual.
- Wizard interactivo: detecta qué tenés instalado, instala lo que falta.

---

## Filosofía

**Drive sincroniza lo que afecta tu experiencia. Local guarda lo que se regenera.**

| Vive en Drive (portable) | Vive en `~/.claude-local/` (no sync) |
|---|---|
| `projects/` (chats) | `plugins/marketplaces/` (`.git` pesado) |
| `skills/` | `plugins/cache/` |
| `agents/` | `plugins/data/` |
| `memory/` | `file-history/`, `shell-snapshots/` |
| `plans/` | `paste-cache/`, `image-cache/` |
| `settings.json` + `settings.local.json` | `cache/`, `chrome/`, `daemon/` |
| `installed_plugins.json` (la lista) | `tasks/`, `jobs/`, `sessions/` |
| `known_marketplaces.json` (la lista) | `backups/`, `ide/`, `session-env/` |

Cuando cambiás de Mac, los plugins se **re-clonan automáticamente** desde GitHub
usando la lista. Nunca subís un `.git/` a Drive.

---

## Setup en una Mac nueva

**Solo 2 cosas manuales. Lo demás lo hace todo el wizard.**

### Paso 1 — Google Drive (~5 min, manual inevitable)

1. Descargá Drive Desktop: <https://www.google.com/drive/download/>
2. Iniciá sesión con **tu cuenta de Google**
3. Ícono de Drive → ⚙ Preferencias → Mi unidad → **Replicar archivos**
4. Esperá a que sincronice (`Mi unidad/.claude/` debe pesar >50 MB después
   de haber usado Claude Code al menos una vez en alguna Mac)

> Por qué: en modo Transmitir los archivos no están en disco; Claude Code da timeout.

### Paso 2 — Descargar y ejecutar el instalador

**Abrí Safari y descargá este archivo:**

<https://raw.githubusercontent.com/jefermorales/claude-session-sync/main/install.command>

Click derecho en el link → **"Guardar enlace como..."** → guardalo en Descargas.

**Doble clic en `install.command`** (en la carpeta Descargas).

> **La primera vez, Gatekeeper de macOS bloquea.** Solución:
> click derecho en `install.command` → **Abrir** → **Abrir** en el diálogo.
> Solo la primera vez.

### Lo que el wizard hace solo (sin que toques nada)

- ✅ Detecta qué dependencias ya tenés (no las reinstala)
- ✅ Instala Xcode Command Line Tools (incluye git)
- ✅ Instala Homebrew
- ✅ Instala Node.js + npm
- ✅ Instala Claude Code CLI
- ✅ Instala jq (opcional)
- ✅ Clona este repo en `~/Developer/claude-session-sync`
- ✅ Corre el bootstrap completo (symlinks, split Drive/local, hooks)
- ✅ Si algo falla: copia el log al portapapeles, abre un Issue en GitHub solo

### Cuando termina

```bash
cd "$HOME/Mi unidad"     # o donde guardes tus proyectos
claude --resume
```

Ves todos tus chats, skills, agents y settings.

### Modo avanzado (sin wizard)

Si ya tenés todo instalado y solo querés re-aplicar el setup:

```bash
bash ~/Developer/claude-session-sync/bootstrap-claude.sh
```

Idempotente — corré las veces que quieras.

---

## Qué hace el bootstrap

1. **Detecta Google Drive** (locale es/en, paths nuevos y viejos)
2. **Symlinkea** `~/.claude` → `Mi unidad/.claude`
3. **Adapta paths al usuario** (`-Users-{viejo}-…` → `-Users-{nuevo}-…`)
4. **Adapta locale** (`Mi-unidad` ↔ `My-Drive` en los paths)
5. **Mueve a `~/.claude-local`** todo lo regenerable/pesado/.git
6. **Re-clona marketplaces** desde GitHub a local (lee `known_marketplaces.json`)
7. **Limpia basura acumulada** (`.DS_Store`, duplicados `(2)`, `.tmp.driveupload/*`)
8. **Instala hooks** de cleanup + lock multi-Mac en `settings.json`
9. **Reporta** qué hizo

---

## Limpieza automática (hooks SessionStart + SessionEnd)

Cada vez que **abrís** Claude Code (`SessionStart`) y cada vez que **cerrás**
una sesión (`SessionEnd`), el script corre cleanup:

- Borra `.DS_Store` recursivos
- Borra duplicados `(2)`, `(3)` en `marketplaces/`
- Limpia `.tmp.driveupload/`, `.tmp.drivedownload/` (>1 día = basura)
- Borra archivos con sufijo `"Conflicted copy"` (conflictos de Drive)
- Renombra carpetas si cambiaste el `$USER` de la Mac
- Borra caches viejas:
  - `image-cache/` >30 días
  - `paste-cache/`, `shell-snapshots/` >7 días
  - `file-history/` >60 días
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
  renombrás el usuario, `$HOME` cambia y el hook se resuelve solo al nuevo path.
- **El cleanup auto-repara** el symlink `~/.claude` si quedó roto.
- **El cleanup re-copia** el script desde el repo clonado si desapareció de
  `~/.claude-local/`.
- **El cleanup renombra** las carpetas `-Users-{viejo}-...` →
  `-Users-{nuevo}-...` cuando detecta que `$USER` cambió.

En la primera apertura de Claude tras el cambio de usuario, el hook
`SessionStart` repara todo solo. **No tenés que correr nada manual.**

### Si algo falla — el mismo `install.command`

**Una sola app, un solo archivo.** El `install.command` que usaste para
instalar es el mismo que usás para reparar.

Cuando algo se rompa (rarísimo): **doble clic en `install.command`**.

- Detecta qué hay instalado y qué falta
- Items ya instalados aparecen **deshabilitados** con su versión actual
- Solo elegís entre lo que falta
- Si TODO está instalado: salta el menú y va directo a verificar/reparar el setup multi-Mac

Si la reparación falla: te abre la página de GitHub Issues con el log
ya copiado al portapapeles. Pegás (Cmd+V) y reportás.

---

## Detección multi-Mac (hook SessionStart)

Si abrís Claude en otra Mac mientras una sesión está activa (<5 min), te avisa:

```
⚠ Claude Code parece activo en 'MacBook-Air' (hace 47s).
  Drive puede generar conflictos si usás ambas Macs a la vez.
```

Es un **warning**, no un bloqueo. Usa el lock file `.claude/.active-session.json`.

> Para uso simultáneo real (sin warning) habría que migrar a un repo Git en lugar
> de Drive — Drive Mirror no soporta concurrencia segura. Por ahora: una Mac a la vez.

---

## Comandos

```bash
# Wizard interactivo (recomendado para Mac nueva)
open install.command                     # o doble clic en Finder

# Setup directo (sin wizard)
bash bootstrap-claude.sh                 # Setup completo (idempotente)
bash bootstrap-claude.sh --cleanup       # Cleanup (hook SessionStart)
bash bootstrap-claude.sh --session-end   # Cleanup + libera lock (hook SessionEnd)
bash bootstrap-claude.sh --lock-check    # Lock-check (hook SessionStart)
bash bootstrap-claude.sh --help          # Ayuda
```

---

## Lo que NO se porta automáticamente

- **`~/.claude.json`** (config de runtime). Se regenera sola en cada Mac.
- **Node.js / npm / Claude Code CLI**: hay que instalarlos en cada Mac
  (el wizard lo hace por vos).

---

## Troubleshooting

### `claude --resume` no muestra conversaciones

1. Confirmá que estás en el directorio correcto:
   `cd "$HOME/Mi unidad"` (o donde guardes tus proyectos).
2. Confirmá que Drive terminó de sincronizar:
   `du -sh "$HOME/Mi unidad/.claude/"` debe ser >50 MB.
3. Volvé a correr el bootstrap:
   `bash ~/Developer/claude-session-sync/bootstrap-claude.sh`.

### Conversación específica no aparece

```bash
claude --resume <uuid-de-la-conversación>
```

El listador puede saltarse conversaciones muy grandes (>20 MB).

### Dos Macs abiertas a la vez

El hook `--lock-check` te avisa, pero **Drive Mirror no es seguro para uso
concurrente**. Cerrá Claude en una Mac antes de abrirlo en otra.

### Drive sigue acumulando errores

Doble clic en `install.command` (o desde terminal:
`bash ~/Developer/claude-session-sync/bootstrap-claude.sh`).

Re-correr limpia basura y rearma symlinks. Si persiste, pausá Drive,
corré el bootstrap, y reactivá Drive.

### Quiero borrar `~/.claude-local` y empezar de cero

Sí, podés. El bootstrap lo regenera todo en la próxima corrida (caches vacías,
marketplaces re-clonados). Solo perdés caches efímeros — tus chats, skills,
settings están en Drive, no se tocan.

---

## Para forkear este repo

Si querés hostear tu propia versión:

1. Fork desde GitHub
2. En `install.command`, cambiá la línea:
   ```bash
   GITHUB_REPO="jefermorales/claude-session-sync"
   ```
   por tu repo (`tuusuario/tu-fork`).
3. Push.

Ahora `install.command` clona tu fork.

---

## Licencia

MIT.
