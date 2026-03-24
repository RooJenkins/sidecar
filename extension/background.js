const HOST_NAME = "com.sidecar.menu";

function callNativeHost(message) {
  return new Promise((resolve) => {
    try {
      chrome.runtime.sendNativeMessage(HOST_NAME, message, (response) => {
        if (chrome.runtime.lastError) {
          resolve({ type: "error", error: chrome.runtime.lastError.message });
        } else {
          resolve(response || { type: "error", error: "Empty response" });
        }
      });
    } catch (err) {
      resolve({ type: "error", error: err.message });
    }
  });
}

// Handle messages from content scripts and popup
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === "search" || msg.type === "smart-search" || msg.type === "status") {
    callNativeHost(msg).then(sendResponse);
    return true; // keep channel open for async response
  }
});

// Handle keyboard shortcut command
chrome.commands.onCommand.addListener(async (command) => {
  if (command === "inject-context") {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id) return;

    // Ensure content script is injected (handles pages opened before extension load)
    try {
      await chrome.scripting.executeScript({
        target: { tabId: tab.id },
        files: ["content.js"],
      });
    } catch {
      // Already injected or not allowed on this page
    }

    try {
      await chrome.tabs.sendMessage(tab.id, { type: "trigger-inject" });
    } catch {
      // Content script not reachable on this page
    }
  }
});
