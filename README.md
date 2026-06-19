# claude-session-sync

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

**Solo dos pasos. Lo demás es automático.**

### Paso 1 — Configurar Google Drive (~5 min)

1. Descargá Google Drive Desktop: <https://www.google.com/drive/download/>
2. Iniciá sesión con tu cuenta de Google.
3. En el ícono de Drive (barra de menú) → ⚙ Preferencias → **Mi unidad** →
   activá **"Replicar archivos"**.
4. Esperá a que Drive sincronice (~1-3 min la primera vez).

> Por qué Replicar: en modo "Transmitir" los archivos están en la nube y
> Claude Code da timeout al leerlos. Necesitamos los archivos en disco real.

### Paso 2 — Descargar y ejecutar el instalador

**Descargá el archivo desde acá:**

<https://raw.githubusercontent.com/jefermorales/claude-session-sync/main/install.command>

> ⚠️ Si al abrir el link ves **código de texto en pantalla**, no copies. Es
> normal — Safari muestra el contenido. Para descargarlo:
>
> - **Click derecho** sobre el link de arriba → **"Guardar enlace como..."**
> - Guardalo en **Descargas**.

Después, **doble clic** en `install.command` desde la carpeta Descargas.

### ⚠️ Si te aparece "Apple no pudo verificar..."

Esto es **Gatekeeper de macOS** bloqueando el archivo descargado de internet.
Solo pasa la primera vez. Tenés 2 formas de pasarlo:

**Camino 1 — Click derecho (más rápido):**

1. En Finder, andá a la carpeta **Descargas**
2. **Click derecho** (o Control + clic) sobre `install.command`
3. En el menú que aparece, elegí **"Abrir"**
4. Aparece un diálogo **distinto** al del doble clic — ese sí tiene el botón
   **"Abrir"** (gris pero clicable)
5. Apretá **Abrir** → arranca el wizard

**Camino 2 — System Settings (si el camino 1 no aparece):**

1. Cerrá el diálogo del error con "Listo"
2. **Menú Apple () → Configuración del sistema → Privacidad y seguridad**
3. Bajá hasta la sección **"Seguridad"**
4. Vas a ver: *"install.command fue bloqueado para protegerlo..."*
5. Apretá **"Abrir de todos modos"**
6. Te pide tu contraseña de la Mac → la metés
7. Doble clic en `install.command` → ahora abre sin problemas

> Después de hacer esto **una vez**, todos los doble clic futuros funcionan
> sin warnings.

### Lo que el instalador hace solo

Sin tocar nada:

- 🔍 Detecta qué dependencias ya tenés (no las reinstala)
- 📦 Instala lo que falta: Xcode CLT (git), Homebrew, Node.js + npm,
  Claude Code CLI, jq
- 📂 Clona este repo en `~/Developer/claude-session-sync`
- ⚙️ Corre el setup multi-Mac (`bootstrap-claude.sh`)
- 🔁 Configura los hooks de auto-cleanup y lock multi-Mac
- 🛠️ Si algo falla: copia el log al portapapeles y abre un Issue en GitHub
  con todo precargado

### Después de instalar

```bash
cd "$HOME/Mi unidad"          # o donde guardes tus proyectos
claude --resume
```

Ves todos tus chats, skills, agents y settings sincronizados.

---

## Reparar / verificar / actualizar

**Una sola app, un solo archivo.** El `install.command` es a la vez instalador,
reparador y verificador.

Si algo se rompe (cambio de nombre de usuario, basura acumulada, conflicto raro
de Drive): **doble clic en `install.command`**.

Lo que pasa:
- Los items ya instalados aparecen ✓ deshabilitados con su versión actual
- Solo elegís entre lo que falte
- Si todo está OK, salta el menú y va directo a verificar/reparar el setup
- Si la reparación falla, abre GitHub Issues con el log ya copiado al
  portapapeles — solo pegás (Cmd+V) y reportás

---

## Cómo funciona

**Filosofía:** Drive sincroniza lo que afecta tu experiencia. Local guarda lo
regenerable.

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

### Limpieza automática

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

## Comandos avanzados

```bash
# Wizard interactivo (recomendado siempre)
open install.command                     # o doble clic en Finder

# Setup directo (sin wizard, asumiendo deps instaladas)
bash bootstrap-claude.sh                 # Setup completo (idempotente)
bash bootstrap-claude.sh --cleanup       # Cleanup manual
bash bootstrap-claude.sh --session-end   # Cleanup + libera lock
bash bootstrap-claude.sh --lock-check    # Lock-check manual
bash bootstrap-claude.sh --help          # Ayuda completa
```

---

## Troubleshooting

### El instalador no se abre — "no se puede verificar el desarrollador"

Click derecho en `install.command` → **Abrir** → en el diálogo, **Abrir** otra
vez. Es Gatekeeper, solo la primera vez.

### `claude --resume` no muestra mis chats

1. Confirmá que estás en el directorio correcto
   (ej: `cd "$HOME/Mi unidad"`).
2. Confirmá que Drive terminó de sincronizar:
   `du -sh "$HOME/Mi unidad/.claude/"` debe ser >50 MB.
3. Doble clic en `install.command` para verificar/reparar.

### Conversación específica no aparece en la lista

```bash
claude --resume <uuid-de-la-conversación>
```

El listador puede saltarse conversaciones muy grandes (>20 MB).

### Drive sigue acumulando errores

Doble clic en `install.command`. Re-correr limpia basura y rearma symlinks.
Si persiste: pausá Drive desde el ícono de la barra, doble clic en
`install.command`, y reactivá Drive.

### Quiero borrar `~/.claude-local` y empezar de cero

Lo podés hacer. El instalador lo regenera todo (caches vacías, marketplaces
re-clonados). Solo perdés caches efímeros — **tus chats, skills y settings
están en Drive, no se tocan**.

---

## Para forkear

Si querés hostear tu propia versión:

1. Fork desde GitHub
2. En `install.command`, cambiá:
   ```bash
   GITHUB_REPO="jefermorales/claude-session-sync"
   ```
   por `tuusuario/tu-fork`.
3. Push.

Ahora `install.command` clona tu fork.

---

## Qué NO se porta automáticamente

- **`~/.claude.json`** (config de runtime). Se regenera sola en cada Mac.
- **Node.js, npm, Claude Code CLI**: binarios del sistema. El instalador
  los pone en cada Mac.

---

## Licencia

MIT.
