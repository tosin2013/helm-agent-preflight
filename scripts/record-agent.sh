#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
# Records the agent demo GIF: a real OpenCode session using helm preflight upgrade.
# Pre-flight requirements (exits with error if either fails):
#   1. OpenCode responds to a test prompt
#   2. A kind cluster is running (shows real Kubernetes context)
set -euo pipefail

export PATH="${HOME}/.local/bin:/home/vpcuser/bin:${HOME}/.opencode/bin:/usr/local/bin:$PATH"
cd /home/vpcuser/helm-agent-preflight

OPENCODE="${HOME}/.opencode/bin/opencode"
MODEL="${OPENCODE_MODEL:-litellm/claude-sonnet-4-6}"

# ── 1. Verify OpenCode responds ───────────────────────────────────────────────
PING=$("$OPENCODE" run --standalone --auto --model "$MODEL" \
  "Reply with exactly one word: READY" 2>/dev/null | tr -d '[:space:]')
if [[ -z "$PING" ]] || [[ "$PING" == *"Error"* ]] || [[ "$PING" == *"limit"* ]]; then
  echo "ERROR: OpenCode did not respond (got: '${PING}')" >&2
  echo "Check ~/.config/opencode/opencode.json and your API key." >&2
  exit 1
fi

# ── 2. Verify kind cluster ────────────────────────────────────────────────────
if ! kubectl cluster-info --context kind-preflight-demo &>/dev/null; then
  echo "ERROR: kind cluster 'preflight-demo' is not running." >&2
  echo "Start it: KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --name preflight-demo" >&2
  exit 1
fi

# ── Show cluster context ──────────────────────────────────────────────────────
sleep 1
kubectl get nodes --context kind-preflight-demo
sleep 2
echo ""

# ── Show the command that will run — displayed text matches what executes ──────
echo "$ opencode run \\"
echo "    --file skills/helm-preflight/SKILL.md \\"
echo "    \"Qualify this Helm upgrade using helm preflight upgrade:\""
echo "      --from  examples/rbac-escalation/baseline"
echo "      --to    examples/rbac-escalation/candidate"
echo "      --release-name webapp --namespace staging --kube-version 1.37"
sleep 2
echo ""

# ── Run OpenCode — displayed command above is exactly what executes ───────────
"$OPENCODE" run \
  --standalone \
  --auto \
  --model "$MODEL" \
  --file "skills/helm-preflight/SKILL.md" \
  "Qualify this Helm upgrade using helm preflight upgrade:
  --from  examples/rbac-escalation/baseline
  --to    examples/rbac-escalation/candidate
  --release-name webapp --namespace staging --kube-version 1.37

Report the verdict, all security findings with their JSON paths, and
propose the smallest concrete fix. Include the fingerprint from the
JSON output." \
  2>/dev/null

# ── 10s review pause ──────────────────────────────────────────────────────────
echo ""
for i in $(seq 10 -1 1); do
  echo "  Reviewing output... ${i}s"
  sleep 1
done
