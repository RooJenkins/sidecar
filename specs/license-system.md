## Goal
Implement a license key system with Stripe payments for Sidecar Pro features.

## Context
- CLI is currently MIT, all features free
- Need to gate advanced features behind a paid license
- License validation should work offline (signed keys)

## Pro Features (gated)
- AI summarization (`--summarize`)
- Smart search (AI-powered relevance filtering)
- Watch mode (`--watch`)
- MCP server

## Free Features (always available)
- `sidecar scan` (extraction, no AI summary)
- `sidecar index`
- `sidecar search` (BM25 keyword search)
- `sidecar status`
- `sidecar clean`
- `sidecar init`

## Architecture
1. **License keys**: Ed25519-signed JWT containing `email`, `plan`, `expiresAt`
2. **Validation**: Offline — public key baked into CLI verifies signature
3. **Storage**: `~/.sidecar/license.key`
4. **Activation**: `sidecar activate <key>` writes the file
5. **Check**: `isProLicensed()` function, called at feature entry points
6. **Purchase flow**: Stripe Checkout → webhook → generate key → email to user

## Commands
- `sidecar activate <key>` — Store license key
- `sidecar license` — Show license status
- `sidecar deactivate` — Remove license

## Stripe Setup
- Product: "Sidecar Pro"
- Pricing: $9/month or $79/year
- Webhook endpoint on uplo.ai/api/sidecar/webhook
- Key generation service on uplo.ai/api/sidecar/activate

## Acceptance Criteria
- [ ] License key generation (Ed25519 signed JWT)
- [ ] CLI activate/deactivate/status commands
- [ ] Pro feature gating with helpful upgrade message
- [ ] Stripe Checkout integration
- [ ] Webhook → key generation → email delivery
- [ ] Landing page pricing section
