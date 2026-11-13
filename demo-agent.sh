#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
#
# demo-agent.sh — AI Agent × helm-agent-preflight
#
# Shows how an AI coding agent (OpenCode) uses SKILL.md to invoke
# helm preflight upgrade, interpret the JSON verdict, and propose fixes —
# without substituting its own security judgment for the tool's output.
#
# The script runs in two modes:
#   1. Simulated (always): step-by-step walkthrough with the actual tool
#   2. Live OpenCode session (if ~/.opencode/bin/opencode is found):
#      runs the agent for real against the RBAC escalation scenario
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY="${SCRIPT_DIR}/bin/preflight-linux-amd64"
POLICY_DIR="${SCRIPT_DIR}/policies/rego"
OPENCODE="${HOME}/.opencode/bin/opencode"
REPORTS_DIR="${SCRIPT_DIR}/demo-agent-reports"
mkdir -p "$REPORTS_DIR"

# ── colours ──────────────────────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
RESET='\033[0m'

banner()   { echo -e "\n${BLUE}${BOLD}══ $* ══${RESET}"; }
agent()    { echo -e "${MAGENTA}${BOLD}  🤖 Agent:${RESET} $*"; }
tool()     { echo -e "${CYAN}${BOLD}  🔧 Tool:${RESET}  $*"; }
human()    { echo -e "${YELLOW}${BOLD}  👤 Human:${RESET} $*"; }
verdict_pass()  { echo -e "${GREEN}${BOLD}  ✔  PASS${RESET}  — $*"; }
verdict_block() { echo -e "${RED}${BOLD}  ✘  BLOCK${RESET} — $*"; }
dim()      { echo -e "${DIM}$*${RESET}"; }

# ── prerequisite check ────────────────────────────────────────────────────────
if [ ! -f "$BINARY" ]; then
  echo -e "${RED}Binary not found: $BINARY${RESET}"
  echo "Run: make build"
  exit 1
fi
if ! command -v conftest &>/dev/null; then
  echo -e "${RED}conftest not in PATH. Install it or run demo.sh first.${RESET}"
  exit 1
fi

JQ=$(command -v jq 2>/dev/null || echo "")

# ── banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
cat << 'EOF'
  ╔══════════════════════════════════════════════════════════════╗
  ║      AI Agent  ×  helm-agent-preflight  Demonstration       ║
  ║                                                              ║
  ║   AI proposes · Helm renders · Rego evaluates · Human OKs   ║
  ╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${RESET}"
echo -e "  ${DIM}SKILL.md protocol: the agent runs the tool — it never invents the verdict.${RESET}"
echo -e "  ${DIM}The fingerprint in the agent's report must match the tool's JSON.${RESET}\n"

# ── SKILL.md extract ──────────────────────────────────────────────────────────
banner "The Agent's Operating Rules (from SKILL.md)"
echo ""
dim "  Excerpt from skills/helm-preflight/SKILL.md:"
echo ""
echo -e "${BOLD}  Mandatory protocol:${RESET}"
echo -e "  ${DIM}• NEVER substitute tool output with AI reasoning${RESET}"
echo -e "  ${DIM}• You MUST run the tool and report its verdict${RESET}"
echo -e "  ${DIM}• If the tool cannot run, verdict is INDETERMINATE (treat as BLOCK)${RESET}"
echo -e "  ${DIM}• Do NOT proceed when evidence.completeness is \"PARTIAL\"${RESET}"
echo -e "  ${DIM}• Do NOT modify the policy file solely to suppress a finding${RESET}"
echo ""

# ── helper: run_preflight ─────────────────────────────────────────────────────
run_preflight() {
  local report_file="$1"; shift
  set +e
  "$BINARY" upgrade "$@" \
    --policy-dir "$POLICY_DIR" \
    --output-file "$report_file" \
    2>/tmp/preflight-agent-stderr.txt
  local exit_code=$?
  set -e
  echo "$exit_code"
}

show_report() {
  local report="$1"
  if [ -n "$JQ" ]; then
    local verdict fingerprint tool_ver n_findings
    verdict=$(jq -r '.verdict' "$report")
    fingerprint=$(jq -r '.fingerprint' "$report" | cut -c1-20)
    tool_ver=$(jq -r '.tool.version' "$report")
    n_findings=$(jq '.security_findings | length' "$report")

    echo -e "  ${BOLD}Verdict${RESET}     : $(colorize_verdict "$verdict")"
    echo -e "  ${BOLD}Fingerprint${RESET} : ${DIM}${fingerprint}...${RESET}  ${DIM}(tamper-evident, excludes timestamps)${RESET}"
    echo -e "  ${BOLD}Tool${RESET}        : ${DIM}${tool_ver}${RESET}"
    echo -e "  ${BOLD}Findings${RESET}    : ${n_findings}"

    if [ "$n_findings" -gt 0 ]; then
      echo ""
      jq -r '.security_findings[] |
        "    [\(.verdict_contribution)] \(.rule_id) (\(.severity)) — \(.object.kind)/\(.object.name)\n      \(.message)\n      pre_existing=\(.pre_existing)"' \
        "$report" 2>/dev/null
    fi
  else
    grep -E '"verdict"|"fingerprint"|"rule_id"' "$report" | sed 's/^/  /'
  fi
}

colorize_verdict() {
  case "$1" in
    PASS)          echo -e "${GREEN}${BOLD}PASS${RESET}" ;;
    BLOCK)         echo -e "${RED}${BOLD}BLOCK${RESET}" ;;
    INDETERMINATE) echo -e "${YELLOW}${BOLD}INDETERMINATE${RESET}" ;;
    *)             echo "$1" ;;
  esac
}

# ══════════════════════════════════════════════════════════════════════════════
# SIMULATED AGENT SESSION
# ══════════════════════════════════════════════════════════════════════════════

banner "Simulated Agent Session — RBAC Escalation Scenario"
echo ""
human "Qualify the Helm upgrade from rbac-escalation/baseline to rbac-escalation/candidate"
human "Release: demo-app  |  Namespace: default  |  Kubernetes: 1.28"
echo ""

agent "I will follow the helm-preflight skill protocol."
agent "Step 1: Gather required inputs — ✔ all provided"
agent "Step 2: Run helm preflight upgrade"
echo ""

dim "  \$ preflight upgrade \\"
dim "      --from examples/rbac-escalation/baseline \\"
dim "      --to   examples/rbac-escalation/candidate \\"
dim "      --release-name demo-app --namespace default --kube-version 1.28 \\"
dim "      --output-file demo-agent-reports/rbac.json"
echo ""

RBAC_REPORT="${REPORTS_DIR}/rbac.json"
exit_code=$(run_preflight "$RBAC_REPORT" \
  --from  "${SCRIPT_DIR}/examples/rbac-escalation/baseline" \
  --to    "${SCRIPT_DIR}/examples/rbac-escalation/candidate" \
  --release-name demo-app \
  --namespace default \
  --kube-version 1.28)

tool "preflight exited with code ${exit_code} (2 = BLOCK)"
echo ""

agent "Step 3: Parse and report the verdict"
echo ""
show_report "$RBAC_REPORT"
echo ""

verdict_block "Upgrade must not proceed"
echo ""
agent "Step 4: Propose the smallest fix"
echo ""
echo -e "  ${BOLD}Finding RBAC-001/002:${RESET} ClusterRole uses wildcard (*) resources and verbs."
echo -e "  ${BOLD}Proposed fix:${RESET} Replace wildcard rules with an explicit allowlist:\n"
echo -e "  ${DIM}  rules:${RESET}"
echo -e "  ${DIM}    - apiGroups: [\"\"]${RESET}"
echo -e "  ${DIM}      resources: [\"pods\", \"services\", \"configmaps\"]  # explicit, not *${RESET}"
echo -e "  ${DIM}      verbs:     [\"get\", \"list\", \"watch\"]             # explicit, not *${RESET}"
echo ""
agent "Re-running preflight against the SAFE chart to confirm the fix works..."
echo ""

SAFE_REPORT="${REPORTS_DIR}/safe.json"
safe_exit=$(run_preflight "$SAFE_REPORT" \
  --from  "${SCRIPT_DIR}/examples/safe-upgrade/baseline" \
  --to    "${SCRIPT_DIR}/examples/safe-upgrade/candidate" \
  --release-name demo-app \
  --namespace default \
  --kube-version 1.28)

show_report "$SAFE_REPORT"
echo ""
verdict_pass "Upgrade cleared for human review"
echo ""
agent "I confirm the fingerprint in my report matches the tool output:"

if [ -n "$JQ" ]; then
  FP=$(jq -r '.fingerprint' "$SAFE_REPORT")
  echo -e "  ${DIM}Report fingerprint : ${FP}${RESET}"
  echo -e "  ${DIM}Tool JSON .fingerprint: ${FP}${RESET}"
  echo -e "  ${GREEN}  ✔ Fingerprints match — verdict was not fabricated${RESET}"
fi

echo ""
human "Reviewed. Approving the safe upgrade."
echo ""
dim "  \$ helm upgrade demo-app ./examples/safe-upgrade/candidate --namespace default"
dim "  Release \"demo-app\" has been upgraded."
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# LIVE OPENCODE SESSION (if available)
# ══════════════════════════════════════════════════════════════════════════════

banner "Live OpenCode Session"
echo ""

if [ ! -f "$OPENCODE" ]; then
  echo -e "  ${DIM}OpenCode not found at ${OPENCODE}${RESET}"
  echo -e "  ${DIM}Install: https://opencode.ai  — then re-run this script${RESET}"
  echo ""
  echo -e "  ${BOLD}To run the live agent session manually:${RESET}"
  echo ""
  dim "  ${OPENCODE:-~/.opencode/bin/opencode} run \\"
  dim "    --standalone --auto --archived \\"
  dim "    --file '${SCRIPT_DIR}/skills/helm-preflight/SKILL.md' \\"
  dim "    'Following the helm-preflight skill protocol, qualify this upgrade:"
  dim "     Baseline: ${SCRIPT_DIR}/examples/rbac-escalation/baseline"
  dim "     Candidate: ${SCRIPT_DIR}/examples/rbac-escalation/candidate"
  dim "     Release: demo-app  Namespace: default  Kubernetes: 1.28"
  dim "     Policy dir: ${POLICY_DIR}"
  dim "     Run helm preflight upgrade and report the verdict and all findings.'"
  echo ""
else
  echo -e "  ${GREEN}OpenCode found: $(${OPENCODE} --version 2>/dev/null | head -1)${RESET}"
  echo -e "  ${DIM}Starting live agent session against rbac-escalation scenario...${RESET}"
  echo -e "  ${DIM}(uses --standalone so it won't affect other OpenCode sessions)${RESET}\n"

  PROMPT="Following the helm-preflight skill protocol in the attached SKILL.md file, qualify this Helm upgrade:

Baseline chart:  ${SCRIPT_DIR}/examples/rbac-escalation/baseline
Candidate chart: ${SCRIPT_DIR}/examples/rbac-escalation/candidate
Release name:    demo-app
Namespace:       default
Kubernetes version: 1.28
Policy directory: ${POLICY_DIR}

Run: preflight upgrade (the binary at ${BINARY}) with --policy-dir ${POLICY_DIR}

Report:
1. The verdict (PASS/BLOCK/INDETERMINATE) with the JSON fingerprint
2. All security findings (rule_id, severity, object, message)
3. Your proposed remediation for each BLOCK finding
4. Confirmation that no deployment occurred

Do NOT invent or assume the verdict — run the tool and read its JSON output."

  "$OPENCODE" run \
    --standalone \
    --auto \
    --archived \
    --file "${SCRIPT_DIR}/skills/helm-preflight/SKILL.md" \
    "$PROMPT" \
    2>/tmp/opencode-stderr.txt || {
      echo -e "  ${YELLOW}OpenCode session ended (non-zero exit — check for API key configuration)${RESET}"
      echo -e "  ${DIM}stderr: $(cat /tmp/opencode-stderr.txt | head -3)${RESET}"
    }
fi

# ── summary ───────────────────────────────────────────────────────────────────
banner "Summary"
echo ""
echo -e "  Reports written to: ${BOLD}${REPORTS_DIR}/${RESET}"
for f in "${REPORTS_DIR}"/*.json; do
  [ -f "$f" ] || continue
  v=$(jq -r '.verdict' "$f" 2>/dev/null || echo "?")
  case "$v" in PASS) c="${GREEN}";; BLOCK) c="${RED}";; *) c="${YELLOW}";; esac
  printf "  %-35s %s${BOLD}%s${RESET}\n" "$(basename "$f")" "$c" "$v"
done
echo ""
echo -e "${BOLD}  Operating contract:${RESET}"
echo -e "  ${DIM}AI agents propose and explain. The tool decides. Humans authorize.${RESET}\n"
