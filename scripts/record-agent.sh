#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
# Records the agent demo GIF as a real 3-turn conversation with OpenCode.
# No simulated user messages — only genuine OpenCode responses are shown.
set -euo pipefail

export PATH="${HOME}/.local/bin:/home/vpcuser/bin:${HOME}/.opencode/bin:/usr/local/bin:$PATH"
cd /home/vpcuser/helm-agent-preflight

OPENCODE="${HOME}/.opencode/bin/opencode"
MODEL="${OPENCODE_MODEL:-litellm/claude-sonnet-4-6}"
SESSION="ses-preflight-$(date +%s)"

# ── 1. Verify OpenCode responds before recording anything ─────────────────────
PING=$("$OPENCODE" run --session "${SESSION}-ping" --model "$MODEL" \
  "Reply with exactly one word: READY" 2>/dev/null | tr -d '[:space:]')
if [[ -z "$PING" ]] || [[ "$PING" == *"Error"* ]] || [[ "$PING" == *"limit"* ]]; then
  echo "ERROR: OpenCode did not respond (got: '${PING}')" >&2
  exit 1
fi

# ── 2. Verify kind cluster ────────────────────────────────────────────────────
if ! kubectl cluster-info --context kind-preflight-demo &>/dev/null; then
  echo "ERROR: kind cluster 'preflight-demo' is not running." >&2
  exit 1
fi
kubectl get nodes --context kind-preflight-demo
sleep 2
echo ""

# ── TURN 1: introduce the problem ────────────────────────────────────────────
set +e
"$OPENCODE" run \
  --session "$SESSION" \
  --model "$MODEL" \
  --file "skills/helm-preflight/SKILL.md" \
  "I'm about to upgrade my webapp Helm chart. The candidate chart adds new RBAC permissions. Can you help me check if it's safe using the helm preflight skill? I'll give you the chart locations when you're ready."
[ $? -ne 0 ] && { echo "ERROR: OpenCode session failed — demo aborted."; exit 1; }
set -e

sleep 10

# ── TURN 2: provide chart paths — agent runs the tool ────────────────────────
set +e
"$OPENCODE" run \
  --session "$SESSION" \
  --model "$MODEL" \
  "The charts are examples/rbac-escalation/baseline (current) and examples/rbac-escalation/candidate (new). Release: webapp, namespace: staging, Kubernetes 1.37. Please run the preflight check now."
[ $? -ne 0 ] && { echo "ERROR: OpenCode session failed — demo aborted."; exit 1; }
set -e

sleep 10

# ── TURN 3: ask for the minimum fix ──────────────────────────────────────────
set +e
"$OPENCODE" run \
  --session "$SESSION" \
  --model "$MODEL" \
  "What is the minimum change I need to make to get a PASS verdict? Show me the exact diff."
[ $? -ne 0 ] && { echo "ERROR: OpenCode session failed — demo aborted."; exit 1; }
set -e

# ── review pause ──────────────────────────────────────────────────────────────
echo ""
for i in $(seq 10 -1 1); do
  echo "  Reviewing output... ${i}s"
  sleep 1
done
