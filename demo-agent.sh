#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
#
# demo-agent.sh — Real OpenCode × helm-agent-preflight
#
# Runs an actual OpenCode agent session using the helm-preflight SKILL.md.
# The agent reads the skill, invokes 'preflight upgrade', interprets the
# JSON verdict, and proposes a fix — all using the real LLM, not a simulation.
#
# Usage:
#   bash demo-agent.sh                        # uses default free model
#   bash demo-agent.sh --model litellm/claude-sonnet-4-6
#   bash demo-agent.sh --scenario safe        # PASS scenario
#   bash demo-agent.sh --scenario rbac        # BLOCK + fix scenario (default)
#   bash demo-agent.sh --scenario privileged  # privileged container BLOCK
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCODE="${HOME}/.opencode/bin/opencode"
BINARY="${SCRIPT_DIR}/bin/preflight-linux-amd64"
POLICY_DIR="${SCRIPT_DIR}/policies/rego"
SKILL="${SCRIPT_DIR}/skills/helm-preflight/SKILL.md"

# Default: a free model that works without an API key
MODEL="${OPENCODE_MODEL:-litellm/claude-sonnet-4-6}"
SCENARIO="rbac"

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)      MODEL="$2"; shift 2 ;;
    --scenario)   SCENARIO="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

# ── prerequisite checks ───────────────────────────────────────────────────────
if [ ! -f "$OPENCODE" ]; then
  echo "OpenCode not found at $OPENCODE"
  echo "Install from: https://opencode.ai"
  exit 1
fi

if [ ! -f "$BINARY" ]; then
  echo "preflight binary not found: $BINARY"
  echo "Run: make build"
  exit 1
fi

if ! command -v conftest &>/dev/null; then
  echo "conftest not in PATH. Install it or run demo.sh first."
  exit 1
fi

# ── scenario selection ────────────────────────────────────────────────────────
case "$SCENARIO" in
  safe)
    FROM="${SCRIPT_DIR}/examples/safe-upgrade/baseline"
    TO="${SCRIPT_DIR}/examples/safe-upgrade/candidate"
    SCENARIO_DESC="safe image-tag upgrade (nginx 1.24 → 1.25)"
    EXPECTED="PASS"
    ;;
  privileged)
    FROM="${SCRIPT_DIR}/examples/privileged-container/baseline"
    TO="${SCRIPT_DIR}/examples/privileged-container/candidate"
    SCENARIO_DESC="candidate introduces privileged container"
    EXPECTED="BLOCK"
    ;;
  rbac|*)
    FROM="${SCRIPT_DIR}/examples/rbac-escalation/baseline"
    TO="${SCRIPT_DIR}/examples/rbac-escalation/candidate"
    SCENARIO_DESC="candidate introduces wildcard ClusterRole"
    EXPECTED="BLOCK + proposed fix"
    ;;
esac

# ── banner ────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  OpenCode × helm-agent-preflight — real agent session"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Model     : $MODEL"
echo "  Scenario  : $SCENARIO_DESC"
echo "  Expected  : $EXPECTED"
echo "  Skill     : skills/helm-preflight/SKILL.md"
echo "  Binary    : $BINARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── build the prompt ──────────────────────────────────────────────────────────
# Give the agent the exact binary path and flags so it can run the tool
# without guessing. The SKILL.md is attached as a file.
read -r -d '' PROMPT << PROMPT_EOF || true
Follow the helm-preflight skill protocol in the attached SKILL.md exactly.

Qualify this Helm upgrade:

  Baseline chart : ${FROM}
  Candidate chart: ${TO}
  Release name   : demo-app
  Namespace      : default
  Kubernetes     : 1.28
  Policy dir     : ${POLICY_DIR}

The preflight binary to run is:
  ${BINARY} upgrade \\
    --from ${FROM} \\
    --to   ${TO} \\
    --release-name demo-app \\
    --namespace default \\
    --kube-version 1.28 \\
    --policy-dir ${POLICY_DIR} \\
    --output-file /tmp/preflight-agent-report.json

After running it, read /tmp/preflight-agent-report.json and report:
1. The verdict field (PASS / BLOCK / INDETERMINATE)
2. The fingerprint (first 20 chars is fine)
3. Every finding: rule_id, severity, object kind/name, message, pre_existing
4. The diff summary (added/modified/removed counts)
5. Confirmation that no_deployment_occurred is true

If verdict is BLOCK, propose the smallest concrete code change to fix
each finding. Then tell me which example chart would pass instead and why.

Do not invent or assume the verdict. Run the binary and read the JSON.
PROMPT_EOF

# ── run opencode ──────────────────────────────────────────────────────────────
echo "Starting OpenCode session (Ctrl+C to exit)..."
echo ""

"$OPENCODE" run \
  --standalone \
  --auto \
  --model "$MODEL" \
  --file "$SKILL" \
  "$PROMPT"

# ── show the raw report if it was written ────────────────────────────────────
if [ -f /tmp/preflight-agent-report.json ]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Tool output (what the agent received):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if command -v jq &>/dev/null; then
    jq '{verdict, fingerprint: .fingerprint[:20], findings: [.security_findings[] | {rule: .rule_id, sev: .severity, obj: (.object.kind+"/"+.object.name), new: (if .pre_existing then "pre-existing" else "NEW" end)}], diff: .diff_summary, no_deployment: .run_metadata.no_deployment_occurred}' \
      /tmp/preflight-agent-report.json
  else
    python3 -c "
import json, sys
d = json.load(open('/tmp/preflight-agent-report.json'))
print(json.dumps({'verdict': d['verdict'], 'fingerprint': d['fingerprint'][:20],
  'findings': len(d['security_findings']),
  'no_deployment': d['run_metadata']['no_deployment_occurred']}, indent=2))"
  fi
fi
