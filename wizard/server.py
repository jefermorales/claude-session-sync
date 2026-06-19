#!/usr/bin/env python3
"""
Claude Code Sync — wizard backend.
Mini servidor HTTP local (stdlib pura, sin pip) que sirve la página del wizard
y endpoints que detectan el estado del sistema e instalan dependencias.
"""

import http.server
import socketserver
import json
import os
import subprocess
import threading
import time
import webbrowser
import shutil
import sys
import signal
import re as _re_ansi
from pathlib import Path
from urllib.parse import urlparse


HERE = Path(__file__).resolve().parent
REPO_DIR_DEFAULT = str(Path.home() / "Developer" / "claude-session-sync")
LOG_FILE = str(Path.home() / "Library" / "Logs" / "claude-code-sync.log")
HOST = "127.0.0.1"
PORT = 8765


def log(msg: str) -> None:
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(f"[{time.strftime('%F %T')}] {msg}\n")


def run(cmd: str, env: dict = None) -> tuple[int, str]:
    """Run a shell command, capture combined output."""
    full_env = os.environ.copy()
    full_env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + full_env.get("PATH", "")
    if env:
        full_env.update(env)
    proc = subprocess.run(
        cmd, shell=True, capture_output=True, text=True, env=full_env, timeout=900
    )
    out = (proc.stdout or "") + (proc.stderr or "")
    log(f"$ {cmd}\n{out}\nexit={proc.returncode}")
    return proc.returncode, out.strip()


_ANSI_RE = _re_ansi.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07")


def _strip_ansi(s: str) -> str:
    return _ANSI_RE.sub("", s).replace("\x0e", "").replace("\x0f", "")


def stream_run(cmd: str):
    """Yield lines as a shell command runs (for SSE).
    Wraps in `script -q /dev/null` so the subprocess thinks stdout is a
    terminal and line-buffers its output (bash block-buffers when piped)."""
    full_env = os.environ.copy()
    full_env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + full_env.get("PATH", "")

    wrapped = f"script -q /dev/null {cmd}"
    proc = subprocess.Popen(
        wrapped, shell=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        bufsize=0, env=full_env,
    )
    for raw in iter(proc.stdout.readline, b""):
        try:
            text = raw.decode("utf-8", errors="replace")
        except Exception:
            continue
        text = _strip_ansi(text).rstrip("\r\n").lstrip("\x04")  # ^D que mete `script`
        if text:
            yield text
    proc.stdout.close()
    proc.wait()
    yield f"__EXIT__:{proc.returncode}"


def has(cmd: str) -> bool:
    return shutil.which(cmd) is not None


def detect_drive() -> tuple[bool, str]:
    candidates = [
        Path.home() / "Mi unidad",
        Path.home() / "My Drive",
    ]
    cloud = Path.home() / "Library" / "CloudStorage"
    if cloud.is_dir():
        for p in cloud.iterdir():
            if p.name.startswith("GoogleDrive-"):
                for sub in ("Mi unidad", "My Drive"):
                    cand = p / sub
                    if cand.is_dir():
                        candidates.append(cand)
    for c in candidates:
        if c.is_dir():
            return True, str(c)
    return False, ""


def detect_drive_replicating(drive_path: str) -> bool:
    """Drive in 'Replicate' mode has real files. 'Stream' mode has metadata only."""
    if not drive_path:
        return False
    claude = Path(drive_path) / ".claude"
    if not claude.is_dir():
        # No .claude yet — first run? OK as long as folder is real
        return True
    try:
        total = sum(p.stat().st_size for p in claude.rglob("*") if p.is_file())
        return total > 5 * 1024 * 1024  # >5MB = files exist on disk
    except Exception:
        return True


def detect_state() -> dict:
    """Detect every dependency. Return both 'installed' and 'version' strings."""
    state = {}
    # Xcode CLT
    rc, out = run("xcode-select -p 2>/dev/null")
    state["xcode"] = {"installed": rc == 0, "version": out if rc == 0 else ""}
    # Homebrew
    if has("brew"):
        _, ver = run("brew --version | head -1 | awk '{print $2}'")
        state["brew"] = {"installed": True, "version": ver}
    else:
        state["brew"] = {"installed": False, "version": ""}
    # Node
    if has("node"):
        _, ver = run("node --version")
        state["node"] = {"installed": True, "version": ver}
    else:
        state["node"] = {"installed": False, "version": ""}
    # Claude Code
    if has("claude"):
        _, ver = run("claude --version 2>/dev/null | head -1 | awk '{print $1}'")
        state["claude"] = {"installed": True, "version": ver}
    else:
        state["claude"] = {"installed": False, "version": ""}
    # jq
    if has("jq"):
        _, ver = run("jq --version")
        state["jq"] = {"installed": True, "version": ver}
    else:
        state["jq"] = {"installed": False, "version": ""}
    # Drive
    drive_found, drive_path = detect_drive()
    state["drive"] = {
        "installed": drive_found,
        "path": drive_path,
        "replicating": detect_drive_replicating(drive_path) if drive_found else False,
    }
    return state


# ────────────────────────────────────────────────────────────────────────────
# HTTP handler
# ────────────────────────────────────────────────────────────────────────────

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(HERE), **kwargs)

    def log_message(self, *args, **kwargs):
        pass  # silence

    def _json(self, payload: dict, status: int = 200):
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/" or path == "":
            return self._serve_static("index.html")
        if path == "/api/state":
            return self._json(detect_state())
        if path == "/api/exit":
            self._json({"ok": True})
            # Non-daemon: que el proceso espere a que esto corra
            threading.Thread(target=shutdown_soon, daemon=False).start()
            return
        # static files (style.css, app.js, etc.)
        return super().do_GET()

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/install":
            return self._handle_install_sse()
        return self._json({"error": "not found"}, 404)

    def _serve_static(self, name: str):
        try:
            f = (HERE / name).read_bytes()
            self.send_response(200)
            ct = "text/html; charset=utf-8" if name.endswith(".html") else "application/octet-stream"
            if name.endswith(".css"): ct = "text/css; charset=utf-8"
            if name.endswith(".js"): ct = "application/javascript; charset=utf-8"
            self.send_header("Content-Type", ct)
            self.send_header("Content-Length", str(len(f)))
            self.end_headers()
            self.wfile.write(f)
        except FileNotFoundError:
            self.send_error(404)

    def _handle_install_sse(self):
        """Server-Sent Events: stream the install progress."""
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode("utf-8") if length else "{}"
            req = json.loads(body)
        except Exception:
            req = {}

        # TCP_NODELAY → cada evento SSE sale inmediato (sin Nagle)
        try:
            import socket as _socket
            self.connection.setsockopt(_socket.IPPROTO_TCP, _socket.TCP_NODELAY, 1)
        except Exception:
            pass

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "keep-alive")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()

        def send(event: str, data):
            payload = json.dumps(data)
            self.wfile.write(f"event: {event}\ndata: {payload}\n\n".encode("utf-8"))
            self.wfile.flush()

        try:
            install_flow(req, send)
        except Exception as e:
            log(f"install error: {e}")
            send("error", {"message": str(e)})
        finally:
            send("done", {})


# ────────────────────────────────────────────────────────────────────────────
# Install flow
# ────────────────────────────────────────────────────────────────────────────

def install_flow(req: dict, send):
    """
    req = {
      "install": ["xcode","brew","node","claude","jq"],   # what to install
      "hooks": ["session_end","lock"]                      # what to enable
    }
    """
    steps = []
    requested = set(req.get("install", []))
    hooks = req.get("hooks", [])

    state = detect_state()

    # Build step list
    if "xcode" in requested and not state["xcode"]["installed"]:
        steps.append(("Xcode Command Line Tools", install_xcode))
    if "brew" in requested and not state["brew"]["installed"]:
        steps.append(("Homebrew", install_brew))
    if "node" in requested and not state["node"]["installed"]:
        steps.append(("Node.js + npm", install_node))
    if "claude" in requested and not state["claude"]["installed"]:
        steps.append(("Claude Code CLI", install_claude))
    if "jq" in requested and not state["jq"]["installed"]:
        steps.append(("jq", install_jq))

    # Always: clone repo + bootstrap
    steps.append(("Clonando repo", clone_repo))
    steps.append(("Configurando setup multi-Mac", run_bootstrap))

    total = len(steps)
    send("plan", {"steps": [s[0] for s in steps], "total": total})

    for i, (label, fn) in enumerate(steps):
        send("step_start", {"index": i, "label": label, "total": total})
        try:
            for line in fn():
                send("log", {"text": line})
            send("step_done", {"index": i, "label": label, "ok": True})
        except Exception as e:
            send("step_done", {"index": i, "label": label, "ok": False, "error": str(e)})
            send("fatal", {"step": label, "error": str(e), "log_file": LOG_FILE})
            return

    send("success", {"log_file": LOG_FILE})


def install_xcode():
    yield "Verificando Xcode Command Line Tools..."
    rc, _ = run("xcode-select -p")
    if rc == 0:
        yield "Ya estaba instalado."
        return
    yield "Lanzando instalador de macOS (puede aparecer una ventana)..."
    run("xcode-select --install")
    # Esperamos a que el usuario lo termine
    for _ in range(180):  # 30 min max
        time.sleep(10)
        rc, _ = run("xcode-select -p")
        if rc == 0:
            yield "Xcode CLT instalado."
            return
        yield "Esperando a que termine la instalación..."
    raise RuntimeError("Xcode CLT no se completó. Cerrá y volvé a abrir.")


def install_brew():
    yield "Descargando e instalando Homebrew..."
    rc, out = run(
        '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null'
    )
    if rc != 0:
        raise RuntimeError(f"Falló install de Homebrew: {out[:300]}")
    yield "Homebrew instalado."


def install_node():
    yield "Instalando Node.js via Homebrew..."
    rc, out = run("brew install node")
    if rc != 0:
        raise RuntimeError(f"Falló brew install node: {out[:300]}")
    yield "Node.js instalado."


def install_claude():
    yield "Instalando Claude Code CLI..."
    rc, out = run("npm install -g @anthropic-ai/claude-code")
    if rc != 0:
        raise RuntimeError(f"Falló npm install: {out[:300]}")
    yield "Claude Code CLI instalado."


def install_jq():
    yield "Instalando jq..."
    rc, out = run("brew install jq")
    if rc != 0:
        raise RuntimeError(f"Falló brew install jq: {out[:300]}")
    yield "jq instalado."


def clone_repo():
    repo_dir = REPO_DIR_DEFAULT
    if os.path.isdir(os.path.join(repo_dir, ".git")):
        yield f"Repo ya está en {repo_dir} — actualizando..."
        run(f"git -C {repo_dir!r} pull --quiet")
    else:
        yield f"Clonando en {repo_dir}..."
        os.makedirs(os.path.dirname(repo_dir), exist_ok=True)
        rc, out = run(
            f"git clone --quiet https://github.com/jefermorales/claude-session-sync.git {repo_dir!r}"
        )
        if rc != 0:
            raise RuntimeError(f"Falló git clone: {out[:300]}")
    yield "Repo listo."


def run_bootstrap():
    repo_dir = REPO_DIR_DEFAULT
    script = os.path.join(repo_dir, "bootstrap-claude.sh")
    if not os.path.isfile(script):
        raise RuntimeError(f"No encuentro {script}")
    yield "Corriendo bootstrap-claude.sh..."
    for line in stream_run(f"bash {script!r}"):
        if line.startswith("__EXIT__:"):
            code = int(line.split(":")[1])
            if code != 0:
                raise RuntimeError(f"Bootstrap salió con código {code}")
            continue
        if line.strip():
            yield line.strip()
    yield "Bootstrap completo."


# ────────────────────────────────────────────────────────────────────────────
# Lifecycle
# ────────────────────────────────────────────────────────────────────────────

_server_ref = {"srv": None}


def shutdown_soon():
    # No-daemon thread: damos tiempo a que el response salga, después matamos.
    time.sleep(0.5)
    log("Exit requested, shutting down server")
    if _server_ref["srv"]:
        try:
            _server_ref["srv"].shutdown()
        except Exception:
            pass
    # Backstop por si shutdown() no cierra serve_forever a tiempo
    os._exit(0)


def main():
    log("=== Wizard started ===")
    try:
        srv = socketserver.ThreadingTCPServer((HOST, PORT), Handler)
        srv.allow_reuse_address = True
    except OSError as e:
        print(f"Puerto {PORT} en uso. Cerrá la otra instancia.", file=sys.stderr)
        log(f"PORT busy: {e}")
        sys.exit(1)

    _server_ref["srv"] = srv

    def handle_sigterm(*_):
        srv.shutdown()
    signal.signal(signal.SIGTERM, handle_sigterm)
    signal.signal(signal.SIGINT, handle_sigterm)

    # Browser launch shortly after server is up
    def open_browser():
        time.sleep(0.3)
        webbrowser.open(f"http://{HOST}:{PORT}/")
    threading.Thread(target=open_browser, daemon=True).start()

    print(f"Claude Code Sync wizard on http://{HOST}:{PORT}/")
    log(f"Server ready on {HOST}:{PORT}")
    srv.serve_forever()
    log("Server shutdown")


if __name__ == "__main__":
    main()
