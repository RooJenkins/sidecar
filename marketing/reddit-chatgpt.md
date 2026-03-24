# I built a tool that lets ChatGPT (and Claude, Gemini) actually see your local files

**r/ChatGPT**

---

You know how ChatGPT can't access your local files? You have to upload them one by one, hit file size limits, and lose context between conversations?

I built **Sidecar** to fix this.

It scans your documents — PDFs, Word docs, spreadsheets, basically anything — and creates searchable summaries on your machine. Then when you're chatting with an AI, you press **Cmd+J** and it finds the most relevant documents based on your conversation and drops them right into the chat.

**How it works**:

1. Install it: `npm install -g uplo-sidecar`
2. Point it at your documents: `sidecar scan ~/Documents`
3. Build a search index: `sidecar index ~/Documents`
4. Use Cmd+J in any AI chat to search and attach docs

It works with ChatGPT, Claude, and Gemini through a Chrome extension. There's also a macOS menu bar app that works system-wide.

**The key thing**: your documents stay on your machine. Sidecar creates small markdown summary files locally and searches through them when you need context. You're not uploading your entire filing cabinet to the cloud.

It handles PDFs, DOCX, XLSX, and over 1,400 other file types. No more screenshotting spreadsheets or copy-pasting from PDFs.

Free and open source (MIT license).

GitHub: https://github.com/RooJenkins/sidecar

Website: https://uplo.ai/sidecar
