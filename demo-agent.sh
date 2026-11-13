#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
#
# demo-agent.sh — Real OpenCode × helm-agent-preflight
#
# Full workflow:
#   1. Install the baseline webapp chart into the cluster (staging namespace)
#   2. Show the live running app
#   3. Show the bad candidate chart (wildcard RBAC)
#   4. Run an OpenCode agent session: agent qualifies the upgrade offline,
#      reads the JSON verdict, and proposes a fix — all using the real LLM
#   5. Confirm the cluster was never touched (bad rules never landed)
#
# Usage:
#   bash demo-agent.sh                        # default model, rbac scenario
#   bash demo-agent.sh --model litellm/claude-sonnet-4-6
#   bash demo-agent.sh --scenario safe        # PASS scenario
#   bash demo-agent.sh --scenario rbac        # BLOCK + fix scenario (default)
#   bash demo-agent.sh --scenario privileged  # privileged container BLOCK
#   bash demo-agent.sh --no-install           # skip helm install (cluster already set up)
#   bash demo-agent.sh --cleanup              # uninstall release and exit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCODE="${HOME}/.opencode/bin/opencode"
BINARY="${SCRIPT_DIR}/bin/preflight-linux-amd64"
POLICY_DIR="${SCRIPT_DIR}/policies/rego"
SKILL="${SCRIPT_DIR}/skills/helm-preflight/SKILL.md"

MODEL="${OPENCODE_MODEL:-litellm/claude-sonnet-4-6}"
SCENARIO="rbac"
NAMESPACE="staging"
RELEASE_NAME="webapp"
DO_INSTALL=true

# ── parse flags ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)      MODEL="$2";      shift 2 ;;
    --scenario)   SCENARIO="$2";   shift 2 ;;
    --namespace)  NAMESPACE="$2";  shift 2 ;;
    --no-install) DO_INSTALL=false; shift ;;
    --cleanup)
      echo "Uninstalling release ${RELEASE_NAME} from namespace ${NAMESPACE}..."
      helm uninstall "${RELEASE_NAME}" --namespace "${NAMESPACE}" 2>/dev/null || true
      kubectl delete namespace "${NAMESPACE}" --ignore-not-found
      echo "Done."
      exit 0
      ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

# ── colours ───────────────────────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
DIM='\033[2m'
RESET='\033[0m'

banner() { echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
step()   { echo -e "\n${CYAN}${BOLD}▸ $*${RESET}"; }
ok()     { echo -e "  ${GREEN}${BOLD}✔${RESET}  $*"; }
info()   { echo -e "  ${DIM}$*${RESET}"; }

# ── prerequisite checks ───────────────────────────────────────────────────────
banner
echo -e "  ${BOLD}OpenCode × helm-agent-preflight — agent demo${RESET}"
banner

if [ ! -f "$OPENCODE" ]; then
  echo -e "${RED}OpenCode not found at $OPENCODE${RESET}"
  echo "Install from: https://opencode.ai"
  exit 1
fi

if [ ! -f "$BINARY" ]; then
  echo -e "${RED}preflight binary not found: $BINARY${RESET}"
  echo "Run: make build"
  exit 1
fi

if ! command -v conftest &>/dev/null; then
  echo -e "${RED}conftest not in PATH${RESET}"
  exit 1
fi

if ! command -v helm &>/dev/null; then
  echo -e "${RED}helm not in PATH${RESET}"
  exit 1
fi

if ! command -v kubectl &>/dev/null; then
  echo -e "${RED}kubectl not in PATH${RESET}"
  exit 1
fi

# ── scenario selection ────────────────────────────────────────────────────────
case "$SCENARIO" in
  safe)
    FROM="${SCRIPT_DIR}/examples/safe-upgrade/baseline"
    TO="${SCRIPT_DIR}/examples/safe-upgrade/candidate"
    SCENARIO_DESC="safe image-tag upgrade (nginx 1.24 → 1.25)"
    EXPECTED="PASS"
    INSTALL_CHART="${SCRIPT_DIR}/examples/safe-upgrade/baseline"
    ;;
  privileged)
    FROM="${SCRIPT_DIR}/examples/privileged-container/baseline"
    TO="${SCRIPT_DIR}/examples/privileged-container/candidate"
    SCENARIO_DESC="candidate introduces privileged container"
    EXPECTED="BLOCK"
    INSTALL_CHART="${SCRIPT_DIR}/examples/privileged-container/baseline"
    ;;
  rbac|*)
    FROM="${SCRIPT_DIR}/examples/rbac-escalation/baseline"
    TO="${SCRIPT_DIR}/examples/rbac-escalation/candidate"
    SCENARIO_DESC="candidate introduces wildcard ClusterRole (RBAC escalation)"
    EXPECTED="BLOCK + proposed fix"
    INSTALL_CHART="${SCRIPT_DIR}/examples/rbac-escalation/baseline"
    ;;
esac

echo -e "  Model     : ${BOLD}${MODEL}${RESET}"
echo -e "  Scenario  : ${BOLD}${SCENARIO_DESC}${RESET}"
echo -e "  Expected  : ${BOLD}${EXPECTED}${RESET}"
echo -e "  Namespace : ${BOLD}${NAMESPACE}${RESET}"
echo -e "  Release   : ${BOLD}${RELEASE_NAME}${RESET}"
banner
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# ACT 0 — Install the baseline app into the cluster
# ══════════════════════════════════════════════════════════════════════════════
if [ "$DO_INSTALL" = "true" ]; then
  step "Act 0 — Installing baseline webapp into cluster (namespace: ${NAMESPACE})"
  echo ""

  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null
  ok "Namespace ${NAMESPACE} ready"

  echo ""
  info "$ helm upgrade --install ${RELEASE_NAME} ${INSTALL_CHART} --namespace ${NAMESPACE} --wait"
  echo ""
  helm upgrade --install "${RELEASE_NAME}" "${INSTALL_CHART}" \
    --namespace "${NAMESPACE}" \
    --wait --timeout=90s \
    2>&1 | grep -E '(deployed|upgraded|Error|NOTES|Release)' | sed 's/^/    /' || true
  echo ""
fi

# ══════════════════════════════════════════════════════════════════════════════
# ACT 0b — Show the live running app
# ══════════════════════════════════════════════════════════════════════════════
step "Live app — what's currently running in the cluster"
echo ""
info "$ kubectl get pods,deploy -n ${NAMESPACE}"
echo ""
kubectl get pods,deploy -n "${NAMESPACE}" 2>/dev/null | sed 's/^/    /'
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# ACT 1 — Show the bad candidate chart
# ══════════════════════════════════════════════════════════════════════════════
step "Act 1 — Inspect the candidate chart (what the team wants to deploy)"
echo ""

RBAC_CANDIDATE="${TO}/templates/rbac.yaml"
if [ -f "$RBAC_CANDIDATE" ]; then
  info "$ cat ${RBAC_CANDIDATE#"$SCRIPT_DIR/"}"
  echo ""
  cat "$RBAC_CANDIDATE" | sed 's/^/    /'
  echo ""
  echo -e "  ${RED}${BOLD}⚠  Spot the problem: apiGroups/resources/verbs are all \"*\" — full cluster access${RESET}"
  echo ""
fi

# ══════════════════════════════════════════════════════════════════════════════
# ACT 2 — Ask OpenCode to qualify the upgrade
# ══════════════════════════════════════════════════════════════════════════════
step "Act 2 — Ask OpenCode to qualify the upgrade (offline, no cluster access)"
echo ""
info "OpenCode reads SKILL.md, runs preflight, reads the JSON verdict."
info "No cluster credentials are used — the tool works entirely offline."
echo ""

read -r -d '' PROMPT << PROMPT_EOF || true
Follow the helm-preflight skill protocol in the attached SKILL.md exactly.

The webapp release is currently live in the cluster (namespace: ${NAMESPACE}).
The team wants to upgrade it. Qualify this Helm upgrade before it runs:

  Baseline chart : ${FROM}
  Candidate chart: ${TO}
  Release name   : ${RELEASE_NAME}
  Namespace      : ${NAMESPACE}
  Kubernetes     : 1.37
  Policy dir     : ${POLICY_DIR}

Run the preflight binary:
  ${BINARY} upgrade \\
    --from ${FROM} \\
    --to   ${TO} \\
    --release-name ${RELEASE_NAME} \\
    --namespace ${NAMESPACE} \\
    --kube-version 1.37 \\
    --policy-dir ${POLICY_DIR} \\
    --output-file /tmp/preflight-agent-report.json

After running it, read /tmp/preflight-agent-report.json and report:
1. The verdict (PASS / BLOCK / INDETERMINATE)
2. The fingerprint (first 20 chars is fine)
3. Every finding: rule_id, severity, object kind/name, message, pre_existing
4. The diff summary (added/modified/removed counts)
5. Confirmation that no_deployment_occurred is true

If verdict is BLOCK, propose the smallest concrete code change to fix
each finding. Show it as a unified diff.

Do not invent or assume the verdict. Run the binary and read the JSON.
PROMPT_EOF

echo -e "  ${DIM}Starting OpenCode session (Ctrl+C to exit)...${RESET}"
echo ""

"$OPENCODE" run \
  --standalone \
  --auto \
  --model "$MODEL" \
  --file "$SKILL" \
  "$PROMPT"

# ══════════════════════════════════════════════════════════════════════════════
# ACT 3 — Confirm the cluster was never touched
# ══════════════════════════════════════════════════════════════════════════════
step "Act 3 — Verify the cluster was never touched"
echo ""
info "If preflight returned BLOCK, helm upgrade was never called."
info "The cluster still has the safe baseline RBAC rules."
echo ""

info "$ kubectl get clusterrole ${RELEASE_NAME}-reader -o yaml 2>/dev/null | grep -A8 'rules:'"
echo ""
kubectl get clusterrole "${RELEASE_NAME}-reader" -o yaml 2>/dev/null \
  | grep -A8 'rules:' | sed 's/^/    /' \
  || echo "    (ClusterRole not found — baseline may not include one for this scenario)"
echo ""

info "$ kubectl get pods -n ${NAMESPACE}"
echo ""
kubectl get pods -n "${NAMESPACE}" 2>/dev/null | sed 's/^/    /'
echo ""

# ── show raw report ───────────────────────────────────────────────────────────
if [ -f /tmp/preflight-agent-report.json ]; then
  banner
  echo -e "  ${BOLD}Tool output (what the agent received):${RESET}"
  banner
  echo ""
  if command -v jq &>/dev/null; then
    jq '{verdict,
         fingerprint: .fingerprint[:20],
         findings: [.security_findings[] | {
           rule: .rule_id,
           sev: .severity,
           obj: (.object.kind+"/"+.object.name),
           status: (if .pre_existing then "pre-existing" else "NEW" end)
         }],
         diff: .diff_summary,
         no_deployment: .run_metadata.no_deployment_occurred}' \
      /tmp/preflight-agent-report.json | sed 's/^/  /'
  else
    python3 -c "
import json, sys
d = json.load(open('/tmp/preflight-agent-report.json'))
print(json.dumps({
  'verdict': d['verdict'],
  'fingerprint': d['fingerprint'][:20],
  'findings': len(d['security_findings']),
  'no_deployment': d['run_metadata']['no_deployment_occurred']
}, indent=2))"
  fi
  echo ""
fi

banner
echo -e "  ${GREEN}${BOLD}Demo complete.${RESET}"
echo -e "  Run ${DIM}bash demo-agent.sh --cleanup${RESET} to remove the cluster resources."
banner
echo ""
