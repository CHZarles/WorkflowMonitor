const DEFAULTS = {
  enabled: true,
  serverUrl: "http://127.0.0.1:17600",
  sendTitle: false,
  trackBackgroundAudio: true,
  keepAlive: true,
  heartbeatSeconds: 60
};

function byId(id) {
  const el = document.getElementById(id);
  if (!el) throw new Error(`missing_${id}`);
  return el;
}

async function load() {
  const settings = await chrome.storage.sync.get(DEFAULTS);
  byId("enabled").checked = !!settings.enabled;
  byId("sendTitle").checked = !!settings.sendTitle;
  byId("trackBgAudio").checked = settings.trackBackgroundAudio !== false;
  byId("keepAlive").checked = settings.keepAlive !== false;
  byId("serverUrl").value = settings.serverUrl || DEFAULTS.serverUrl;

  const { status } = await chrome.storage.local.get("status");
  renderStatus(status);

  // Best-effort: when the popup opens, force one emit so the status reflects the current tab/audio.
  forceEmit();
}

function renderStatus(status) {
  const line = byId("statusLine");
  const diag = byId("diagLine");
  if (!status) {
    line.textContent = "(no data yet)";
    diag.textContent = "";
    return;
  }

  const lastOk = typeof status.lastOkTs === "string" ? status.lastOkTs : "";
  const lastAttempt = typeof status.lastAttemptTs === "string" ? status.lastAttemptTs : "";
  const consecutiveErrors =
    typeof status.consecutiveErrors === "number" && Number.isFinite(status.consecutiveErrors)
      ? status.consecutiveErrors
      : 0;

  if (status.ok) {
    const last = status.lastSent || {};
    const parts = [];
    if (last.event) parts.push(`event=${last.event}`);
    if (last.activity) parts.push(`activity=${last.activity}`);
    if (last.domain) parts.push(`domain=${last.domain}`);
    const title = typeof last.title === "string" ? last.title.trim() : "";
    if (title) {
      const t = title.length > 48 ? title.slice(0, 45) + "…" : title;
      parts.push(`title=${t}`);
    }

    const extra = [];
    if (lastOk) extra.push(`last_ok=${lastOk}`);
    if (consecutiveErrors > 0) extra.push(`errors=${consecutiveErrors}`);
    line.textContent = `${status.ts}  |  sent  |  ${parts.length ? parts.join("  ") : "ok"}${
      extra.length ? `  |  ${extra.join("  ")}` : ""
    }`;
  } else {
    const err = status.error || status.lastError || "unknown";
    const extra = [];
    if (consecutiveErrors > 0) extra.push(`errors=${consecutiveErrors}`);
    if (lastAttempt) extra.push(`last_try=${lastAttempt}`);
    if (lastOk) extra.push(`last_ok=${lastOk}`);
    line.textContent = `${status.ts}  |  error  |  ${err}${extra.length ? `  |  ${extra.join("  ")}` : ""}`;
  }

  const off = status.offscreen || {};
  if (typeof off.supported === "boolean") {
    const parts = [];
    parts.push(`keepAlive=${byId("keepAlive").checked ? "on" : "off"}`);
    if (!off.supported) {
      parts.push("offscreen=unsupported");
    } else {
      const desired = off.desired === true ? "on" : "off";
      const has = off.hasDocument === true ? "active" : "inactive";
      parts.push(`offscreen=${desired}/${has}`);
    }
    diag.textContent = parts.join("  |  ");
  } else {
    diag.textContent = "";
  }
}

async function save() {
  const enabled = byId("enabled").checked;
  const sendTitle = byId("sendTitle").checked;
  const trackBackgroundAudio = byId("trackBgAudio").checked;
  const keepAlive = byId("keepAlive").checked;
  const serverUrl = byId("serverUrl").value.trim() || DEFAULTS.serverUrl;
  await chrome.storage.sync.set({ enabled, sendTitle, trackBackgroundAudio, keepAlive, serverUrl });
}

async function testHealth() {
  const serverUrl = byId("serverUrl").value.trim() || DEFAULTS.serverUrl;
  const target = serverUrl.replace(/\/$/, "") + "/health";
  const el = byId("healthResult");
  el.textContent = "…";
  try {
    const res = await fetch(target);
    if (!res.ok) {
      el.textContent = `HTTP ${res.status}`;
      return;
    }
    try {
      const j = await res.json();
      const svc = j?.data?.service || j?.service;
      const ver = j?.data?.version || j?.version;
      el.textContent = svc ? (ver ? `${svc} ${ver}` : `${svc}`) : "OK";
    } catch {
      el.textContent = "OK";
    }
  } catch (e) {
    el.textContent = "ERR";
  }
}

async function forceEmit() {
  try {
    await chrome.runtime.sendMessage({ type: "forceEmit" });
  } catch {
    // ignore
  }
}

async function repair() {
  const btn = byId("repair");
  btn.disabled = true;
  try {
    await chrome.runtime.sendMessage({ type: "repair" });
    await forceEmit();
  } catch {
    // ignore
  } finally {
    setTimeout(() => (btn.disabled = false), 400);
  }
}

byId("enabled").addEventListener("change", save);
byId("sendTitle").addEventListener("change", save);
byId("trackBgAudio").addEventListener("change", save);
byId("keepAlive").addEventListener("change", save);
byId("serverUrl").addEventListener("change", save);
byId("testHealth").addEventListener("click", testHealth);
byId("forceEmit").addEventListener("click", forceEmit);
byId("repair").addEventListener("click", repair);

chrome.storage.local.onChanged.addListener((changes) => {
  if (changes.status) renderStatus(changes.status.newValue);
});

load();
