const statusDot = document.getElementById("status-dot");
const statusText = document.getElementById("status-text");
const versionEl = document.getElementById("version");
const maxResultsInput = document.getElementById("max-results");
const maxResultsValue = document.getElementById("max-results-value");

// Load saved settings
chrome.storage.sync.get({ maxResults: 5 }, (items) => {
  maxResultsInput.value = items.maxResults;
  maxResultsValue.textContent = items.maxResults;
});

// Save settings on change
maxResultsInput.addEventListener("input", () => {
  const val = parseInt(maxResultsInput.value, 10);
  maxResultsValue.textContent = val;
  chrome.storage.sync.set({ maxResults: val });
});

// Check native host status
// Use a port connection to ensure we get a response
function checkStatus() {
  let port;
  const timeout = setTimeout(() => {
    statusDot.className = "status-dot disconnected";
    statusText.textContent = "Timeout";
    versionEl.textContent = "No response from native host";
    try { port?.disconnect(); } catch {}
  }, 5000);

  try {
    port = chrome.runtime.connectNative("com.sidecar.menu");

    port.onMessage.addListener((response) => {
      clearTimeout(timeout);
      if (response && response.available) {
        statusDot.className = "status-dot connected";
        statusText.textContent = "Connected";
        versionEl.textContent = response.version ? `CLI: ${response.version}` : "";
      } else {
        statusDot.className = "status-dot disconnected";
        statusText.textContent = "Disconnected";
        versionEl.textContent = response?.error || "CLI not found";
      }
      port.disconnect();
    });

    port.onDisconnect.addListener(() => {
      clearTimeout(timeout);
      const err = chrome.runtime.lastError?.message || "";
      if (statusText.textContent === "Checking...") {
        statusDot.className = "status-dot disconnected";
        statusText.textContent = "Disconnected";
        versionEl.textContent = err || "Native host exited";
      }
    });

    port.postMessage({ type: "status" });
  } catch (err) {
    clearTimeout(timeout);
    statusDot.className = "status-dot disconnected";
    statusText.textContent = "Error";
    versionEl.textContent = err.message;
  }
}

checkStatus();
