(() => {
  "use strict";

  // ── Platform Detection ──────────────────────────────────────────────────

  function detectPlatform() {
    const host = location.hostname;
    if (host === "claude.ai") return "claude";
    if (host === "chatgpt.com" || host === "chat.openai.com") return "chatgpt";
    if (host === "gemini.google.com") return "gemini";
    return "generic";
  }

  // ── Conversation Extractors ─────────────────────────────────────────────

  // Extractors return an array of individual messages (newest last)
  // so we can pick just the recent ones for a focused search query.

  function extractClaude() {
    const turns = document.querySelectorAll(
      '[data-testid="conversation-turn"], .font-claude-message, .font-user-message'
    );
    if (turns.length > 0) {
      return Array.from(turns).map((el) => el.textContent?.trim()).filter(Boolean);
    }
    const msgs = document.querySelectorAll('[class*="Message"], [class*="message"]');
    return Array.from(msgs).map((el) => el.textContent?.trim()).filter(Boolean);
  }

  function extractChatGPT() {
    const turns = document.querySelectorAll("[data-message-author-role]");
    if (turns.length > 0) {
      return Array.from(turns)
        .map((el) => {
          const role = el.getAttribute("data-message-author-role");
          const text = el.textContent?.trim();
          return text ? `[${role}]: ${text}` : null;
        })
        .filter(Boolean);
    }
    const msgs = document.querySelectorAll('[class*="message"]');
    return Array.from(msgs).map((el) => el.textContent?.trim()).filter(Boolean);
  }

  function extractGemini() {
    const turns = document.querySelectorAll(
      ".conversation-container message-content, .model-response-text, .user-query-text, [data-message-id]"
    );
    if (turns.length > 0) {
      return Array.from(turns).map((el) => el.textContent?.trim()).filter(Boolean);
    }
    const msgs = document.querySelectorAll('[class*="response"], [class*="query"]');
    return Array.from(msgs).map((el) => el.textContent?.trim()).filter(Boolean);
  }

  function extractGeneric() {
    const active = document.activeElement;
    if (active instanceof HTMLTextAreaElement || active instanceof HTMLInputElement) {
      return [active.value || ""].filter(Boolean);
    }
    if (active?.getAttribute("contenteditable") === "true") {
      return [active.textContent || ""].filter(Boolean);
    }
    return [];
  }

  function extractMessages(platform) {
    switch (platform) {
      case "claude": return extractClaude();
      case "chatgpt": return extractChatGPT();
      case "gemini": return extractGemini();
      default: return extractGeneric();
    }
  }

  /**
   * Build a focused search query from the conversation.
   * Uses only the last 2-3 messages (typically the most recent user question
   * and the assistant's reply) rather than the entire conversation,
   * which would dilute BM25 keyword matching with irrelevant terms.
   */
  function buildSearchQuery(messages) {
    if (messages.length === 0) return "";

    // Take last 3 messages max
    const recent = messages.slice(-3);
    let query = recent.join("\n\n");

    // Cap at 1500 chars — enough for keyword extraction, not so much it's noise
    if (query.length > 1500) {
      query = query.slice(-1500);
    }

    return query;
  }

  // ── Input Box Detection ─────────────────────────────────────────────────

  function findInputBox(platform) {
    switch (platform) {
      case "claude":
        return (
          document.querySelector('div[contenteditable="true"].ProseMirror') ||
          document.querySelector('div[contenteditable="true"]') ||
          document.querySelector("textarea")
        );
      case "chatgpt":
        return (
          document.querySelector("textarea#prompt-textarea") ||
          document.querySelector('div[contenteditable="true"]#prompt-textarea') ||
          document.querySelector('div[contenteditable="true"]') ||
          document.querySelector("textarea")
        );
      case "gemini":
        return (
          document.querySelector(".ql-editor") ||
          document.querySelector('div[contenteditable="true"]') ||
          document.querySelector("textarea")
        );
      default: {
        const active = document.activeElement;
        if (
          active instanceof HTMLTextAreaElement ||
          active instanceof HTMLInputElement ||
          active?.getAttribute("contenteditable") === "true"
        ) {
          return active;
        }
        return document.querySelector("textarea") || document.querySelector('div[contenteditable="true"]');
      }
    }
  }

  // ── Context Injection ───────────────────────────────────────────────────

  function formatContext(results) {
    if (!results || results.length === 0) return "";

    const lines = ["<context from=\"sidecar\">"];
    for (const r of results) {
      lines.push(`## ${r.title} (score: ${r.score.toFixed(2)})`);
      if (r.summary) lines.push(r.summary);
      if (r.snippet) lines.push(r.snippet);
      if (r.topics?.length > 0) lines.push(`Topics: ${r.topics.join(", ")}`);
      lines.push(`Source: ${r.file}`);
      lines.push("");
    }
    lines.push("</context>");
    lines.push("");
    return lines.join("\n");
  }

  function injectIntoInput(inputBox, contextText) {
    if (!inputBox || !contextText) return false;

    if (inputBox instanceof HTMLTextAreaElement || inputBox instanceof HTMLInputElement) {
      const current = inputBox.value;
      inputBox.value = contextText + current;
      inputBox.dispatchEvent(new Event("input", { bubbles: true }));
      return true;
    }

    if (inputBox.getAttribute("contenteditable") === "true") {
      // For contenteditable, prepend as text node
      const textNode = document.createTextNode(contextText);
      if (inputBox.firstChild) {
        // Create a new paragraph for the context
        const p = document.createElement("p");
        p.textContent = contextText;
        inputBox.insertBefore(p, inputBox.firstChild);
      } else {
        inputBox.appendChild(document.createTextNode(contextText));
      }
      inputBox.dispatchEvent(new Event("input", { bubbles: true }));
      return true;
    }

    return false;
  }

  // ── Toast Notification ──────────────────────────────────────────────────

  function showToast(message, isError = false) {
    const existing = document.getElementById("sidecar-toast");
    if (existing) existing.remove();

    const toast = document.createElement("div");
    toast.id = "sidecar-toast";
    toast.textContent = message;
    Object.assign(toast.style, {
      position: "fixed",
      bottom: "20px",
      right: "20px",
      padding: "12px 20px",
      borderRadius: "8px",
      backgroundColor: isError ? "#dc2626" : "#16a34a",
      color: "white",
      fontSize: "14px",
      fontFamily: "system-ui, -apple-system, sans-serif",
      zIndex: "999999",
      boxShadow: "0 4px 12px rgba(0,0,0,0.3)",
      transition: "opacity 0.3s ease",
      opacity: "1",
    });

    document.body.appendChild(toast);

    setTimeout(() => {
      toast.style.opacity = "0";
      setTimeout(() => toast.remove(), 300);
    }, 3000);
  }

  // ── Main Flow ───────────────────────────────────────────────────────────

  async function injectContext() {
    const platform = detectPlatform();
    const messages = extractMessages(platform);

    if (!messages || messages.length === 0) {
      showToast("No conversation text found", true);
      return;
    }

    // Build full conversation for AI analysis
    let conversation = messages.join("\n\n");

    // Strip any previously injected sidecar context blocks
    conversation = conversation
      .replace(/<company_context>[\s\S]*?<\/company_context>/g, "")
      .replace(/<context from="sidecar">[\s\S]*?<\/context>/g, "")
      .trim();

    if (conversation.length > 8000) {
      conversation = conversation.slice(-8000);
    }

    // Also include whatever is currently in the input box
    const inputBox = findInputBox(platform);
    if (inputBox) {
      const inputText = inputBox instanceof HTMLTextAreaElement || inputBox instanceof HTMLInputElement
        ? inputBox.value
        : inputBox.textContent;
      if (inputText?.trim()) {
        conversation += "\n\n[Current user input]: " + inputText.trim();
      }
    }

    showToast("Analyzing conversation...");

    try {
      const response = await chrome.runtime.sendMessage({
        type: "smart-search",
        conversation,
        maxResults: 5,
      });

      if (response.type === "error") {
        showToast(`Error: ${response.error}`, true);
        return;
      }

      const results = response.results || [];
      if (results.length === 0) {
        showToast("No matching documents found", true);
        return;
      }

      const contextText = formatContext(results);
      const inputBox = findInputBox(platform);

      if (!inputBox) {
        showToast("Could not find input box", true);
        return;
      }

      const injected = injectIntoInput(inputBox, contextText);
      if (injected) {
        showToast(`Injected context from ${results.length} document(s)`);
      } else {
        showToast("Failed to inject context", true);
      }
    } catch (err) {
      showToast(`Error: ${err.message}`, true);
    }
  }

  // ── Keyboard Shortcut (fallback if commands API doesn't work) ───────────

  document.addEventListener("keydown", (e) => {
    // Cmd+J (or Ctrl+J on non-Mac)
    if ((e.ctrlKey || e.metaKey) && !e.shiftKey && (e.key === "j" || e.key === "J")) {
      e.preventDefault();
      injectContext();
    }
  });

  // Listen for trigger from background script (via commands API)
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === "trigger-inject") {
      injectContext();
    }
  });
})();
