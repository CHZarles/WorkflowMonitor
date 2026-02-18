const DEFAULTS = {
  enabled: true,
  serverUrl: "http://127.0.0.1:17600",
  sendTitle: false,
  trackBackgroundAudio: true,
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
  byId("serverUrl").value = settings.serverUrl || DEFAULTS.serverUrl;

  const { status } = await chrome.storage.local.get("status");
  renderStatus(status);

  // Best-effort: when the popup opens, force one emit so the status reflects the current tab/audio.
  forceEmit();
}

function renderStatus(status) {
  const line = byId("statusLine");
  if (!status) {
    line.textContent = "(no data yet)";
    return;
  }
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
    line.textContent = `${status.ts}  |  sent  |  ${parts.length ? parts.join("  ") : "ok"}`;
  } else {
    line.textContent = `${status.ts}  |  error  |  ${status.error || "unknown"}`;
  }
}

async function save() {
  const enabled = byId("enabled").checked;
  const sendTitle = byId("sendTitle").checked;
  const trackBackgroundAudio = byId("trackBgAudio").checked;
  const serverUrl = byId("serverUrl").value.trim() || DEFAULTS.serverUrl;
  await chrome.storage.sync.set({ enabled, sendTitle, trackBackgroundAudio, serverUrl });
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

byId("enabled").addEventListener("change", save);
byId("sendTitle").addEventListener("change", save);
byId("trackBgAudio").addEventListener("change", save);
byId("serverUrl").addEventListener("change", save);
byId("testHealth").addEventListener("click", testHealth);
byId("forceEmit").addEventListener("click", forceEmit);

chrome.storage.local.onChanged.addListener((changes) => {
  if (changes.status) renderStatus(changes.status.newValue);
});

load();
