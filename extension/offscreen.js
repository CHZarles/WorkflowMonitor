// Keep-alive helper for MV3 service worker stability.
//
// The offscreen document can run timers even when the service worker is suspended.
// Sending a runtime message periodically wakes the worker so alarms/status updates remain reliable.

function ping() {
  try {
    chrome.runtime.sendMessage({ type: "keepAlivePing", ts: Date.now() }).catch(() => {});
  } catch {
    // ignore
  }
}

// Staggered + periodic.
setTimeout(ping, 500);
setInterval(ping, 25_000);

