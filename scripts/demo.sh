#!/usr/bin/env bash
#
# demo.sh — A terminal demo of sidecar for screen recording (asciinema, etc.)
#
# Usage:
#   ./scripts/demo.sh
#
# Assumes `sidecar` is installed globally (npm i -g uplo-sidecar)
# or available via `npx uplo-sidecar`. Set SIDECAR_CMD to override.
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SIDECAR_CMD="${SIDECAR_CMD:-sidecar}"
DEMO_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sidecar-demo.XXXXXX")
PAUSE=${PAUSE:-2}          # seconds between steps (set PAUSE=0 for fast mode)

# ---------------------------------------------------------------------------
# Colors & helpers
# ---------------------------------------------------------------------------

BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
MAGENTA="\033[35m"
BLUE="\033[34m"

banner() {
  echo ""
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}${CYAN}  $1${RESET}"
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
  sleep "$PAUSE"
}

step() {
  echo -e "${BOLD}${GREEN}▸ $1${RESET}"
  echo ""
  sleep 1
}

info() {
  echo -e "  ${DIM}$1${RESET}"
}

run_cmd() {
  echo -e "  ${YELLOW}\$ $1${RESET}"
  echo ""
  sleep 1
  eval "$1"
  echo ""
  sleep "$PAUSE"
}

# ---------------------------------------------------------------------------
# Cleanup on exit
# ---------------------------------------------------------------------------

cleanup() {
  if [[ -d "$DEMO_DIR" ]]; then
    rm -rf "$DEMO_DIR"
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Intro
# ---------------------------------------------------------------------------

clear
echo ""
echo -e "${BOLD}${MAGENTA}"
echo "   ┌─────────────────────────────────────────────────┐"
echo "   │                                                 │"
echo "   │   sidecar                                       │"
echo "   │   Your files. Agent-readable. In seconds.       │"
echo "   │                                                 │"
echo "   │   github.com/RooJenkins/sidecar                 │"
echo "   │                                                 │"
echo "   └─────────────────────────────────────────────────┘"
echo -e "${RESET}"
echo ""
sleep 3

# ---------------------------------------------------------------------------
# Step 1 — Create sample files
# ---------------------------------------------------------------------------

banner "Step 1: Create some sample documents"

step "Setting up a project folder with a few files..."
info "Directory: $DEMO_DIR"
echo ""

# --- meeting-notes.md ---
cat > "$DEMO_DIR/meeting-notes.md" << 'NOTES'
# Product Sync — March 2026

## Attendees
Sarah Chen (PM), Alex Rivera (Eng Lead), Jamie Okafor (Design)

## Agenda
1. Q2 roadmap review
2. Platform migration timeline
3. Design system update

## Discussion

### Q2 Roadmap
- **Search v2** launches April 15 — full-text search with semantic ranking
- **Dashboard redesign** scheduled for May, pending design review
- Mobile app beta pushed to June due to staffing

### Platform Migration
- Moving from Heroku to AWS ECS by end of Q2
- Alex estimates 3 weeks of eng effort for infra work
- Staging environment should be ready by April 1

### Design System
- Jamie presented new component library (Figma link shared in Slack)
- Button, input, and modal components are ready
- Typography scale approved — switching to Inter font family

## Action Items
- [ ] Sarah: Draft Q2 OKRs by Friday
- [ ] Alex: Spike on ECS task definitions
- [ ] Jamie: Ship button component to npm
NOTES

# --- project-proposal.txt ---
cat > "$DEMO_DIR/project-proposal.txt" << 'PROPOSAL'
PROJECT PROPOSAL: Customer Analytics Platform
==============================================

Prepared by: Alex Rivera, Engineering Lead
Date: March 10, 2026

EXECUTIVE SUMMARY

We propose building an internal analytics platform to replace our current
mix of Mixpanel, Google Analytics, and custom SQL dashboards. The unified
platform will reduce costs by ~40% and give every team self-serve access
to customer behavior data.

PROJECT TIMELINE

  Phase 1 (April):    Data pipeline — ingest events from all product surfaces
  Phase 2 (May):      Query engine — SQL interface over the event lake
  Phase 3 (June):     Dashboard builder — drag-and-drop visualizations
  Phase 4 (July):     Self-serve rollout to all teams

BUDGET

  Infrastructure:     $2,400/month (AWS — Kinesis, S3, Athena)
  Engineering:        3 engineers x 4 months
  Total:              ~$180,000

RISKS

  1. Data quality — legacy systems have inconsistent event schemas
  2. Adoption — teams may resist switching from familiar tools
  3. Timeline — Phase 1 depends on API team shipping v2 endpoints

REQUESTED DECISION

  Approve budget and allocate 3 engineers starting April 1.
PROPOSAL

# --- quarterly-report.txt (simulating a dense document like a PDF) ---
cat > "$DEMO_DIR/quarterly-report.txt" << 'REPORT'
QUARTERLY BUSINESS REVIEW — Q1 2026
====================================

Confidential — Internal Use Only

FINANCIAL HIGHLIGHTS

  Revenue:        $4.2M  (+18% YoY)
  ARR:            $16.8M
  Gross Margin:   72%
  Net Retention:  115%
  Customers:      340 (+45 new in Q1)

PRODUCT METRICS

  Monthly Active Users:    28,400 (+12% QoQ)
  API Calls/Day:           1.2M
  P95 Latency:             142ms (down from 210ms)
  Uptime:                  99.97%

KEY WINS

  - Closed Enterprise deal with Meridian Corp ($320K ARR)
  - Launched AI-powered search feature (adopted by 62% of users in 3 weeks)
  - Reduced infrastructure costs by 22% via K8s migration
  - Hired 8 engineers (team now at 32)

CHALLENGES

  - Churn in SMB segment (4 accounts, $38K ARR lost)
  - Mobile app launch delayed — rescheduled to Q2
  - Support ticket volume up 30% — hiring 2 more support engineers

Q2 PRIORITIES

  1. Platform migration to AWS ECS
  2. Launch mobile app beta
  3. Expand into EU market (GDPR compliance work)
  4. Build customer analytics platform (see separate proposal)
REPORT

step "Created 3 files:"
echo -e "  ${BLUE}meeting-notes.md${RESET}       — Product team sync notes"
echo -e "  ${BLUE}project-proposal.txt${RESET}   — Analytics platform proposal"
echo -e "  ${BLUE}quarterly-report.txt${RESET}   — Q1 2026 business review"
echo ""
sleep "$PAUSE"

# ---------------------------------------------------------------------------
# Step 2 — Scan
# ---------------------------------------------------------------------------

banner "Step 2: Scan — extract and structure your documents"

step "Running sidecar scan to generate .sidecar.md companion files..."
info "Each file gets a structured markdown companion with metadata and content."
echo ""

run_cmd "$SIDECAR_CMD scan \"$DEMO_DIR\""

# ---------------------------------------------------------------------------
# Step 3 — Show a generated sidecar file
# ---------------------------------------------------------------------------

banner "Step 3: See what sidecar generated"

step "Let's peek at one of the generated .sidecar.md files:"
echo ""

# Pick whichever sidecar file exists
SIDECAR_FILE=""
for candidate in "$DEMO_DIR/project-proposal.txt.sidecar.md" \
                 "$DEMO_DIR/meeting-notes.md.sidecar.md" \
                 "$DEMO_DIR/quarterly-report.txt.sidecar.md"; do
  if [[ -f "$candidate" ]]; then
    SIDECAR_FILE="$candidate"
    break
  fi
done

if [[ -n "$SIDECAR_FILE" ]]; then
  echo -e "  ${YELLOW}\$ head -30 $(basename "$SIDECAR_FILE")${RESET}"
  echo ""
  head -30 "$SIDECAR_FILE"
  echo -e "  ${DIM}... (truncated)${RESET}"
  echo ""
  sleep "$PAUSE"
else
  echo -e "  ${DIM}(No sidecar files found — scan may have been a dry run)${RESET}"
  echo ""
fi

# Show the directory index too
if [[ -f "$DEMO_DIR/SIDECAR.md" ]]; then
  step "Sidecar also generates a directory index — SIDECAR.md:"
  echo ""
  echo -e "  ${YELLOW}\$ head -25 SIDECAR.md${RESET}"
  echo ""
  head -25 "$DEMO_DIR/SIDECAR.md"
  echo -e "  ${DIM}... (truncated)${RESET}"
  echo ""
  sleep "$PAUSE"
fi

# ---------------------------------------------------------------------------
# Step 4 — Index
# ---------------------------------------------------------------------------

banner "Step 4: Index — build a searchable knowledge base"

step "Building a search index from the sidecar files..."
info "This creates a local BM25 index for fast keyword search."
echo ""

run_cmd "$SIDECAR_CMD index \"$DEMO_DIR\""

# ---------------------------------------------------------------------------
# Step 5 — Search
# ---------------------------------------------------------------------------

banner "Step 5: Search — find relevant documents instantly"

step "Searching for \"project timeline\"..."
echo ""
run_cmd "$SIDECAR_CMD search \"project timeline\" --path \"$DEMO_DIR\""

step "Searching for \"revenue customers\"..."
echo ""
run_cmd "$SIDECAR_CMD search \"revenue customers\" --path \"$DEMO_DIR\""

step "Searching for \"ECS migration\"..."
echo ""
run_cmd "$SIDECAR_CMD search \"ECS migration\" --path \"$DEMO_DIR\""

# ---------------------------------------------------------------------------
# Step 6 — Status
# ---------------------------------------------------------------------------

banner "Step 6: Status — see what's tracked"

run_cmd "$SIDECAR_CMD status \"$DEMO_DIR\""

# ---------------------------------------------------------------------------
# Outro
# ---------------------------------------------------------------------------

banner "Done!"

echo -e "  ${BOLD}What just happened:${RESET}"
echo ""
echo -e "    1. We created 3 sample documents"
echo -e "    2. ${CYAN}sidecar scan${RESET}   generated structured .sidecar.md companions"
echo -e "    3. ${CYAN}sidecar index${RESET}  built a local search index"
echo -e "    4. ${CYAN}sidecar search${RESET} found relevant docs by keyword"
echo ""
echo -e "  ${BOLD}Your files never left your machine.${RESET}"
echo ""
echo -e "  ${DIM}Install:  npm install -g uplo-sidecar${RESET}"
echo -e "  ${DIM}Docs:     https://github.com/RooJenkins/sidecar${RESET}"
echo ""
echo -e "${BOLD}${MAGENTA}  Thanks for watching!${RESET}"
echo ""

# Cleanup happens automatically via the EXIT trap.
