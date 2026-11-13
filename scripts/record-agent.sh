#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
# Records the agent demo GIF: one complete question → one complete answer.
# No multi-turn. No simulated text. Only genuine OpenCode output.
set -euo pipefail

export PATH="${HOME}/.local/bin:/home/vpcuser/bin:${HOME}/.opencode/bin:/usr/local/bin:$PATH"
cd /home/vpcuser/helm-agent-preflight

OPENCODE="${HOME}/.opencode/bin/opencode"
MODEL="${OPENCODE_MODEL:-litellm/claude-sonnet-4-6}"

# ── 1. Verify OpenCode responds before recording anything ─────────────────────
PING=$("$OPENCODE" run --session "ses-ping-$$" --model "$MODEL" \
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

# ── Show the command the viewer can copy and run themselves ───────────────────
echo '$ opencode run \'
echo '    --file skills/helm-preflight/SKILL.md \'
echo '    "Is upgrading webapp from rbac-escalation/baseline to'
echo '     rbac-escalation/candidate safe? Run helm preflight upgrade'
echo '     and show me the verdict, findings, and exact fix if needed."'
sleep 2
echo ""

# ── Run OpenCode — one shot, complete answer ──────────────────────────────────
# If OpenCode exits non-zero, fail loudly — no silent empty GIF.
set +e
"$OPENCODE" run \
  --session "ses-agent-demo-$$" \
  --model "$MODEL" \
  --file "skills/helm-preflight/SKILL.md" \
  "Is it safe to upgrade my webapp Helm chart?
- Baseline (current): examples/rbac-escalation/baseline
- Candidate (new):    examples/rbac-escalation/candidate
- Release: webapp, namespace: staging, Kubernetes: 1.37

Run helm preflight upgrade with those flags. Then give me:
1. The verdict (PASS or BLOCK)
2. Each security finding — rule ID, object, what it means
3. If BLOCK: the exact diff to fix it

Do not ask clarifying questions — run the tool and report the result."
OPENCODE_EXIT=$?
set -e

if [ "$OPENCODE_EXIT" -ne 0 ]; then
  echo ""
  echo "ERROR: OpenCode session failed (exit $OPENCODE_EXIT) — demo aborted."
  exit 1
fi

# ── 10s pause so the viewer can read the output ───────────────────────────────
echo ""
for i in $(seq 10 -1 1); do
  echo "  Reviewing output... ${i}s"
  sleep 1
done
