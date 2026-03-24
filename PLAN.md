# Sidecar Launch Plan

## Phase 1 — Polish & Quality (DONE)
- [x] 1.1 Branding (uplo-sidecar)
- [x] 1.2 README rewrite
- [x] 1.3 Code cleanup
- [x] 1.4 Tests (51 passing)
- [x] 1.5 Bug fixes (toast, attach queue, icon, cliPath)

## Phase 2 — Distribution (DONE)
- [x] 2.1 npm publish (uplo-sidecar@0.1.0)
- [x] 2.2 GitHub Actions (CI + Release workflows)
- [x] 2.3 LICENSE (MIT)
- [x] 2.4 Push to GitHub (RooJenkins/sidecar)
- [x] 2.5 Homebrew formula (RooJenkins/homebrew-tap)

## Phase 3 — Web Presence (DONE)
- [x] 3.1 Landing page at uplo.ai/sidecar
- [x] 3.2 Chrome Web Store — zip ready at /tmp/sidecar-extension-v0.1.0.zip (manual upload needed)

## Phase 4 — Monetization (DONE)
- [x] 4.1 License key system (Ed25519 signed, CLI activate/deactivate/license)
- [x] 4.2 Stripe integration (checkout + webhook on UPLO website)
- [x] 4.3 Pro features gate (requirePro() helper, feature list defined)

## Phase 5 — Advanced Features (DONE)
- [x] 5.1 MCP server (4 tools: search, smart_search, read, status)
- [x] 5.3 VS Code extension (scaffolded with search, smart-search, scan, status)
- [ ] 5.2 Team/shared indexes (future — needs spec)

## Remaining Manual Steps
- [ ] Upload Chrome extension zip to Chrome Web Store Developer Dashboard
- [ ] Create Stripe products + prices and set env vars on Vercel
- [ ] Generate Ed25519 keypair, set SIDECAR_LICENSE_PRIVATE_KEY on Vercel, set SIDECAR_LICENSE_PUBLIC_KEY in CLI
- [ ] npm publish v0.2.0 with MCP + license features
- [ ] Publish VS Code extension to marketplace
