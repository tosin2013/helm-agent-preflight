#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
#
# scripts/record-agent.sh — asciinema recording script for the agent demo
#
# Used by: make demo-record-asciinema (asciinema rec --command bash scripts/record-agent.sh)
# Output:  demos/agent.cast
#
# Tells the full story in a single terminal session:
#   Act 0 — live webapp in cluster (kubectl get pods)
#   Act 1 — bad candidate chart on screen (wildcard RBAC)
#   Act 2 — OpenCode agent qualifies the upgrade → BLOCK + fix
#   Act 3 — cluster still clean (bad rules never landed)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${SCRIPT_DIR}/bin/preflight-linux-amd64"
POLICY_DIR="${SCRIPT_DIR}/policies/rego"
SKILL="${SCRIPT_DIR}/skills/helm-preflight/SKILL.md"
OPENCODE="${HOME}/.opencode/bin/opencode"
MODEL="${OPENCODE_MODEL:-litellm/claude-sonnet-4-6}"
NAMESPACE="staging"
RELEASE_NAME="webapp"
FROM="${SCRIPT_DIR}/examples/rbac-escalation/baseline"
TO="${SCRIPT_DIR}/examples/rbac-escalation/candidate"

export PATH="/home/vpcuser/bin:/usr/local/bin:${PATH}"
cd "$SCRIPT_DIR"

# ── helpers ───────────────────────────────────────────────────────────────────
# Type text with a natural typing delay then run it
run() {
  local cmd="$1"
  printf '%s' "$ "
  local i
  for (( i=0; i<${#cmd}; i++ )); do
    printf '%s' "${cmd:$i:1}"
    sleep 0.025
  done
  echo ""
  sleep 0.3
  eval "$cmd"
  sleep 0.5
}

# Print a comment line
comment() {
  echo -e "\033[2m# $*\033[0m"
  sleep 0.6
}

# ── Act 0: live app ───────────────────────────────────────────────────────────
echo ""
comment "Act 0 — webapp is already live in the cluster (namespace: staging)"
sleep 0.8

run "kubectl get pods,deploy -n ${NAMESPACE}"
sleep 1.5

# ── Act 1: show the bad chart ─────────────────────────────────────────────────
echo ""
comment "Act 1 — inspect the candidate chart the team wants to deploy"
sleep 0.8

run "cat examples/rbac-escalation/candidate/templates/rbac.yaml"
sleep 1s

echo -e "\033[1;33m  ⚠  apiGroups/resources/verbs are all \"*\" — full cluster access if deployed!\033[0m"
sleep 2s

# ── Act 2: OpenCode agent ─────────────────────────────────────────────────────
echo ""
comment "Act 2 — OpenCode agent qualifies the upgrade offline (no cluster access)"
sleep 0.8

echo "$ opencode run --standalone --auto --model ${MODEL} \\"
echo "    --file skills/helm-preflight/SKILL.md \\"
echo "    \"Qualify the Helm upgrade of webapp from rbac-escalation/baseline to candidate\""
sleep 0.5

read -r -d '' PROMPT << 'PROMPT_EOF' || true
Follow the helm-preflight skill protocol in the attached SKILL.md exactly.

The webapp release is currently live in the cluster (namespace: staging).
The team wants to upgrade it. Qualify this Helm upgrade before it runs:

  Baseline chart : BASELINE
  Candidate chart: CANDIDATE
  Release name   : webapp
  Namespace      : staging
  Kubernetes     : 1.37
  Policy dir     : POLICY_DIR

Run the preflight binary:
  BINARY upgrade \
    --from BASELINE \
    --to   CANDIDATE \
    --release-name webapp \
    --namespace staging \
    --kube-version 1.37 \
    --policy-dir POLICY_DIR \
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

PROMPT="${PROMPT//BASELINE/$FROM}"
PROMPT="${PROMPT//CANDIDATE/$TO}"
PROMPT="${PROMPT//POLICY_DIR/$POLICY_DIR}"
PROMPT="${PROMPT//BINARY/$BINARY}"

"$OPENCODE" run \
  --standalone \
  --auto \
  --model "$MODEL" \
  --file  "$SKILL" \
  "$PROMPT"

# ── Act 3: cluster still clean ────────────────────────────────────────────────
echo ""
comment "Act 3 — verify the cluster was never touched"
sleep 0.8

run "kubectl get clusterrole ${RELEASE_NAME}-reader -o yaml 2>/dev/null | grep -A8 'rules:'"
sleep 1s

run "kubectl get pods -n ${NAMESPACE}"
sleep 1s

echo ""
echo -e "\033[1;32m  ✔  Only safe baseline rules in cluster — BLOCK worked offline\033[0m"
echo -e "\033[2m  The wildcard ClusterRole never reached the cluster.\033[0m"
sleep 2s
