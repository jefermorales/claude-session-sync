// Claude Code Sync — wizard frontend.
// Vanilla JS, sin frameworks. Maneja navegación, fetch al backend y SSE.

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => Array.from(document.querySelectorAll(sel));

const REQUIRED = [
  { key: "xcode",  name: "Xcode Command Line Tools",     blurb: "Incluye git, necesario para descargar plugins." },
  { key: "brew",   name: "Homebrew",                     blurb: "Gestor de paquetes; instala Node, jq, etc." },
  { key: "node",   name: "Node.js + npm",                blurb: "Claude Code está hecho con Node." },
  { key: "claude", name: "Claude Code CLI",              blurb: "El programa principal." },
];
const OPTIONAL = [
  { key: "jq",     name: "jq",                           blurb: "Procesa JSON; hace cleanup más rápido." },
];

const state = {
  current: 1,
  drive: { installed: false, replicating: false, path: "" },
  deps: {},          // detect_state() output
  toInstall: {},     // { key: true/false }
  hooks: { session_end: true, lock: true },
  errorLog: "",
};

// ─── Navegación ──────────────────────────────────────────────────────────────
function goto(n) {
  state.current = n;
  $$(".screen").forEach((el) => el.classList.add("hidden"));
  const screen = (n === "error")
    ? document.querySelector('[data-screen="error"]')
    : document.querySelector(`[data-screen="${n}"]`);
  if (screen) screen.classList.remove("hidden");
  updateSteps(n);
}

function updateSteps(n) {
  const numeric = typeof n === "number" ? n : 0;
  $$("#steps li").forEach((li) => {
    const s = parseInt(li.dataset.step, 10);
    li.classList.toggle("active", s === numeric);
    li.classList.toggle("done", numeric > s);
  });
}

// ─── Bienvenida ──────────────────────────────────────────────────────────────
$("#btn-go-2").addEventListener("click", async () => {
  goto(2);
  await refreshDrive();
});
$("#btn-cancel-1").addEventListener("click", () => exitWizard());

// ─── Drive ───────────────────────────────────────────────────────────────────
async function refreshDrive() {
  const checks = $("#drive-checks");
  checks.querySelectorAll(".check").forEach((c) => {
    c.classList.remove("good", "bad");
    c.classList.add("busy");
  });
  try {
    const data = await api("/api/state");
    state.deps = data;
    state.drive = data.drive;
    setCheck("installed",  data.drive.installed);
    setCheck("replicating", data.drive.installed && data.drive.replicating);

    const allOK = data.drive.installed && data.drive.replicating;
    $("#btn-go-3").disabled = !allOK;
    $("#drive-help").hidden = allOK;
  } catch (e) {
    setCheck("installed", false);
    setCheck("replicating", false);
    $("#btn-go-3").disabled = true;
    $("#drive-help").hidden = false;
  }
}
function setCheck(key, good) {
  const el = document.querySelector(`[data-key="${key}"]`);
  if (!el) return;
  el.classList.remove("busy", "good", "bad");
  el.classList.add(good ? "good" : "bad");
}
$("#btn-back-1").addEventListener("click", () => goto(1));
$("#btn-recheck").addEventListener("click", refreshDrive);
$("#btn-go-3").addEventListener("click", () => buildDepsScreen());

// ─── Componentes ─────────────────────────────────────────────────────────────
function buildDepsScreen() {
  const list = $("#deps-required");
  list.innerHTML = "";
  REQUIRED.forEach((d) => {
    const info = state.deps[d.key] || { installed: false, version: "" };
    state.toInstall[d.key] = !info.installed; // pre-select if missing
    const li = document.createElement("li");
    li.className = "dep " + (info.installed ? "installed" : "missing");
    li.innerHTML = `
      <span class="dep-icon">${info.installed ? "✓" : "!"}</span>
      <div>
        <span class="dep-name">${d.name}</span>
        <span class="dep-meta">${info.version ? info.version + " — " : ""}${d.blurb}</span>
      </div>
    `;
    list.appendChild(li);
  });

  // Pre-select optional 'jq' if missing
  const jq = state.deps.jq || { installed: false };
  const jqLi = document.createElement("li");
  jqLi.className = "dep " + (jq.installed ? "installed" : "");
  if (!jq.installed) {
    jqLi.innerHTML = `
      <label>
        <input type="checkbox" data-opt-dep="jq" ${jq.installed ? "" : "checked"}>
        <span class="dep-name">jq</span>
        <span class="dep-meta">Procesa JSON; hace cleanup más rápido.</span>
      </label>
    `;
  } else {
    jqLi.innerHTML = `
      <span class="dep-icon">✓</span>
      <div>
        <span class="dep-name">jq</span>
        <span class="dep-meta">${jq.version} — Ya instalado.</span>
      </div>
    `;
  }
  $("#deps-optional").prepend(jqLi);

  goto(3);
}
$("#btn-back-2").addEventListener("click", () => goto(2));
$("#btn-go-4").addEventListener("click", () => startInstall());

// ─── Instalación ─────────────────────────────────────────────────────────────
function gatherChoices() {
  // Required: instalo lo faltante
  const install = REQUIRED.filter((d) => !state.deps[d.key].installed).map((d) => d.key);
  // Opcional jq: depende del checkbox
  const jqCb = document.querySelector("[data-opt-dep='jq']");
  if (jqCb && jqCb.checked) install.push("jq");
  // Hooks
  const hooks = [];
  ["session_end", "lock"].forEach((k) => {
    const cb = document.querySelector(`[data-opt="${k}"]`);
    if (cb && cb.checked) hooks.push(k);
  });
  return { install, hooks };
}

async function startInstall() {
  goto(4);
  $("#install-steps").innerHTML = "";
  $("#install-log").textContent = "";
  const choices = gatherChoices();

  const resp = await fetch("/api/install", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(choices),
  });

  // SSE parser manual
  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    let idx;
    while ((idx = buf.indexOf("\n\n")) !== -1) {
      const raw = buf.slice(0, idx);
      buf = buf.slice(idx + 2);
      handleSseEvent(raw);
    }
  }
}

function handleSseEvent(raw) {
  let event = "message";
  let dataStr = "";
  raw.split("\n").forEach((l) => {
    if (l.startsWith("event:")) event = l.slice(6).trim();
    else if (l.startsWith("data:")) dataStr += l.slice(5).trim();
  });
  let data;
  try { data = JSON.parse(dataStr); } catch { data = dataStr; }
  switch (event) {
    case "plan":
      renderPlan(data.steps);
      break;
    case "step_start":
      markStep(data.index, "busy");
      $("#install-hint").textContent = `Trabajando en: ${data.label}`;
      break;
    case "step_done":
      markStep(data.index, data.ok ? "ok" : "fail");
      break;
    case "log":
      appendLog(data.text);
      break;
    case "fatal":
      state.errorLog = $("#install-log").textContent + "\n[FATAL] " + (data.error || "");
      $("#error-msg").textContent = `Falló en: ${data.step}\n${data.error || ""}`;
      $("#error-log").textContent = state.errorLog;
      goto("error");
      break;
    case "success":
      $("#install-hint").textContent = "Listo.";
      goto(5);
      break;
    case "error":
      state.errorLog += "\n" + (data.message || "");
      break;
  }
}

function renderPlan(steps) {
  const ol = $("#install-steps");
  ol.innerHTML = "";
  steps.forEach((label) => {
    const li = document.createElement("li");
    li.textContent = label;
    ol.appendChild(li);
  });
}

function markStep(i, klass) {
  const li = $("#install-steps").children[i];
  if (!li) return;
  li.classList.remove("busy", "ok", "fail");
  li.classList.add(klass);
}

function appendLog(text) {
  const pre = $("#install-log");
  pre.textContent += (pre.textContent ? "\n" : "") + text;
  pre.scrollTop = pre.scrollHeight;
}

// ─── Listo ───────────────────────────────────────────────────────────────────
$("#copy-cmd").addEventListener("click", () => {
  const text = $("#next-cmd").textContent;
  navigator.clipboard.writeText(text);
  $("#copy-cmd").textContent = "¡Copiado!";
  setTimeout(() => ($("#copy-cmd").textContent = "Copiar"), 1500);
});
$("#btn-close").addEventListener("click", () => exitWizard());

// ─── Error ───────────────────────────────────────────────────────────────────
$("#btn-copy-log").addEventListener("click", () => {
  navigator.clipboard.writeText(state.errorLog || "");
  $("#btn-copy-log").textContent = "¡Copiado!";
  setTimeout(() => ($("#btn-copy-log").textContent = "Copiar log"), 1500);
});
$("#btn-report").addEventListener("click", () => {
  navigator.clipboard.writeText(state.errorLog || "");
  window.open("https://github.com/jefermorales/claude-session-sync/issues/new", "_blank");
});

// ─── Helpers ─────────────────────────────────────────────────────────────────
async function api(path, opts = {}) {
  const r = await fetch(path, opts);
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const ct = r.headers.get("content-type") || "";
  if (ct.includes("application/json")) return r.json();
  return r.text();
}

function exitWizard() {
  fetch("/api/exit").catch(() => {});
  setTimeout(() => window.close(), 200);
}

// Init
updateSteps(1);
