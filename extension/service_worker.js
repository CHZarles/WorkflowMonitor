const DEFAULTS = {
  enabled: true,
  serverUrl: "http://127.0.0.1:17600",
  sendTitle: false,
  trackBackgroundAudio: true,
  heartbeatSeconds: 60
};

const STATE = {
  lastDomain: null,
  lastTabId: null,
  lastWindowId: null,
  lastActivity: null,
  lastSentAtMs: 0,
  lastAttemptAtMs: 0,
  lastOkAtMs: 0,
  consecutiveErrors: 0,
  lastError: null,
  lastErrorAtMs: 0
};

function nowIso() {
  return new Date().toISOString();
}

function msToIso(ms) {
  if (!ms || ms <= 0) return null;
  try {
    return new Date(ms).toISOString();
  } catch {
    return null;
  }
}

function getLastFocusedWindow() {
  return new Promise((resolve) => {
    try {
      chrome.windows.getLastFocused({ populate: false }, (w) => resolve(w ?? null));
    } catch {
      resolve(null);
    }
  });
}

async function isBrowserFocused() {
  const w = await getLastFocusedWindow();
  // If API isn't available, keep old behavior (best effort).
  if (w == null) return true;
  return Boolean(w.focused);
}

function detectBrowser() {
  const ua = self.navigator?.userAgent || "";
  if (ua.includes("Edg/")) return "edge";
  if (ua.includes("Chrome/")) return "chrome";
  return "unknown";
}

function safeHostname(url) {
  try {
    const u = new URL(url);
    if (u.protocol === "http:" || u.protocol === "https:") return u.hostname;
    return null; // ignore file://, chrome://, edge://, etc.
  } catch {
    return null;
  }
}

async function getSettings() {
  const stored = await chrome.storage.sync.get(DEFAULTS);
  return { ...DEFAULTS, ...stored };
}

async function setStatus(partial) {
  const base = {
    ts: nowIso(),
    lastAttemptTs: msToIso(STATE.lastAttemptAtMs),
    lastOkTs: msToIso(STATE.lastOkAtMs),
    lastErrorTs: msToIso(STATE.lastErrorAtMs),
    consecutiveErrors: STATE.consecutiveErrors,
    lastError: STATE.lastError
  };

  await chrome.storage.local.set({ status: { ...base, ...partial } });
}

async function postEvent(serverUrl, payload) {
  const endpoint = serverUrl.replace(/\/$/, "") + "/event";
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5500);
  try {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
      signal: controller.signal
    });
    if (!res.ok) {
      throw new Error(`http_${res.status}`);
    }
  } catch (e) {
    if (e && typeof e === "object" && e.name === "AbortError") {
      throw new Error("timeout");
    }
    throw e;
  } finally {
    clearTimeout(timeout);
  }
}

async function ensureHeartbeatAlarm() {
  try {
    await chrome.alarms.create("heartbeat", { periodInMinutes: 1 });
  } catch {
    // ignore
  }
}

async function maybeEmitAudioStop(settings, reason) {
  if (STATE.lastActivity !== "audio") return;
  if (!STATE.lastDomain) return;

  const payload = {
    v: 1,
    ts: nowIso(),
    source: "browser_extension",
    event: "tab_audio_stop",
    activity: "audio",
    browser: detectBrowser(),
    domain: STATE.lastDomain,
    ...(typeof STATE.lastWindowId === "number" ? { windowId: STATE.lastWindowId } : {}),
    ...(typeof STATE.lastTabId === "number" ? { tabId: STATE.lastTabId } : {}),
    reason
  };

  try {
    STATE.lastAttemptAtMs = Date.now();
    await postEvent(settings.serverUrl, payload);
    STATE.lastDomain = null;
    STATE.lastTabId = null;
    STATE.lastWindowId = null;
    STATE.lastActivity = null;
    STATE.lastSentAtMs = Date.now();
    STATE.lastOkAtMs = Date.now();
    STATE.consecutiveErrors = 0;
    STATE.lastError = null;
    STATE.lastErrorAtMs = 0;
    await setStatus({ ok: true, lastSent: payload, error: null });
  } catch (e) {
    STATE.consecutiveErrors += 1;
    STATE.lastError = String(e);
    STATE.lastErrorAtMs = Date.now();
    await setStatus({ ok: false, error: String(e) });
  }
}

async function emitActiveTabEvent({ force = false } = {}) {
  const settings = await getSettings();
  if (!settings.enabled) return;

  await ensureHeartbeatAlarm();

  const browserFocused = await isBrowserFocused();

  let tab = null;
  let activity = "focus";

  if (browserFocused) {
    // If the browser comes to foreground, background-audio usage ends at this moment.
    await maybeEmitAudioStop(settings, "browser_focused");

    const tabs = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    tab = tabs && tabs.length ? tabs[0] : null;
  } else if (settings.trackBackgroundAudio !== false) {
    // If browser isn't focused but something is actively "used" (audible tab), track it as background usage.
    // This avoids listing all open tabs; we only record the one that is actually producing audio.
    const audibleTabs = await chrome.tabs.query({ audible: true });
    const candidates = (audibleTabs || []).filter((t) => safeHostname(t.url || ""));
    if (!candidates.length) {
      // Audible stopped (or no longer detectable). Emit an explicit stop marker so Core/UI can end background usage immediately.
      await maybeEmitAudioStop(settings, "no_audible_tabs");
      return;
    }

    // Prefer previously tracked tab if still audible; otherwise pick the most recently accessed audible tab.
    if (typeof STATE.lastTabId === "number") {
      const same = candidates.find((t) => t.id === STATE.lastTabId);
      if (same) tab = same;
    }
    if (!tab) {
      candidates.sort((a, b) => (b.lastAccessed || 0) - (a.lastAccessed || 0));
      tab = candidates[0];
    }
    activity = "audio";
  } else {
    return;
  }

  if (!tab || typeof tab.id !== "number" || typeof tab.windowId !== "number") return;

  const domain = safeHostname(tab.url || "");
  if (!domain) return;

  const changed =
    activity !== STATE.lastActivity ||
    domain !== STATE.lastDomain ||
    tab.id !== STATE.lastTabId ||
    tab.windowId !== STATE.lastWindowId;

  const heartbeatDue =
    Date.now() - STATE.lastSentAtMs >= (settings.heartbeatSeconds ?? DEFAULTS.heartbeatSeconds) * 1000;

  if (!force && !changed && !heartbeatDue) return;

  const payload = {
    v: 1,
    ts: nowIso(),
    source: "browser_extension",
    event: "tab_active",
    activity,
    browser: detectBrowser(),
    domain,
    ...(settings.sendTitle && typeof tab.title === "string" ? { title: tab.title } : {}),
    windowId: tab.windowId,
    tabId: tab.id
  };

  try {
    STATE.lastAttemptAtMs = Date.now();
    await postEvent(settings.serverUrl, payload);
    STATE.lastDomain = domain;
    STATE.lastTabId = tab.id;
    STATE.lastWindowId = tab.windowId;
    STATE.lastActivity = activity;
    STATE.lastSentAtMs = Date.now();
    STATE.lastOkAtMs = Date.now();
    STATE.consecutiveErrors = 0;
    STATE.lastError = null;
    STATE.lastErrorAtMs = 0;
    await setStatus({ ok: true, lastSent: payload, error: null });
  } catch (e) {
    STATE.consecutiveErrors += 1;
    STATE.lastError = String(e);
    STATE.lastErrorAtMs = Date.now();
    await setStatus({ ok: false, error: String(e) });
  }
}

async function emitActiveTabEventSafe(opts) {
  try {
    await emitActiveTabEvent(opts);
  } catch (e) {
    try {
      await setStatus({ ok: false, error: String(e) });
    } catch {
      // ignore
    }
  }
}

chrome.runtime.onInstalled.addListener(async () => {
  const stored = await chrome.storage.sync.get(null);
  if (!stored || Object.keys(stored).length === 0) {
    await chrome.storage.sync.set(DEFAULTS);
  }
  await chrome.alarms.create("heartbeat", { periodInMinutes: 1 });
  await setStatus({ ok: true, info: "installed" });
  await emitActiveTabEventSafe({ force: true });
});

chrome.runtime.onStartup?.addListener(async () => {
  try {
    await chrome.alarms.create("heartbeat", { periodInMinutes: 1 });
    await emitActiveTabEventSafe({ force: true });
  } catch {
    // ignore
  }
});

chrome.tabs.onActivated.addListener(async () => {
  await emitActiveTabEventSafe();
});

chrome.windows.onFocusChanged.addListener(async (windowId) => {
  // WINDOW_ID_NONE means focus moved away from the browser. If background-audio tracking is enabled,
  // emit immediately so we don't wait for the next heartbeat.
  await emitActiveTabEventSafe({ force: true });
});

chrome.tabs.onUpdated.addListener(async (_tabId, changeInfo) => {
  if (
    changeInfo.status === "complete" ||
    changeInfo.url ||
    changeInfo.title ||
    typeof changeInfo.audible === "boolean"
  ) {
    await emitActiveTabEventSafe();
  }
});

chrome.tabs.onRemoved.addListener(async (tabId) => {
  // Closing an audible tab should end background-audio attribution quickly.
  if (STATE.lastActivity !== "audio") return;
  if (typeof STATE.lastTabId === "number" && tabId !== STATE.lastTabId) return;
  await emitActiveTabEventSafe({ force: true });
});

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name !== "heartbeat") return;
  await emitActiveTabEventSafe();
});

chrome.storage.onChanged.addListener(async (changes, areaName) => {
  if (areaName !== "sync") return;
  if (
    changes.enabled ||
    changes.serverUrl ||
    changes.sendTitle ||
    changes.trackBackgroundAudio ||
    changes.heartbeatSeconds
  ) {
    await emitActiveTabEventSafe({ force: true });
  }
});

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  const type = msg && typeof msg === "object" ? msg.type : null;
  if (type !== "forceEmit") return;

  emitActiveTabEventSafe({ force: true })
    .then(() => sendResponse({ ok: true }))
    .catch((e) => sendResponse({ ok: false, error: String(e) }));
  return true;
});

// Best-effort: re-create the heartbeat alarm whenever the service worker wakes up.
// This helps recover from edge cases where alarms are cleared or the worker was suspended for long periods.
try {
  chrome.alarms.create("heartbeat", { periodInMinutes: 1 });
} catch {
  // ignore
}
