#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
#
# Record the agent demo GIF. Requirements before recording:
#   1. A kind cluster must be running (shows real Kubernetes context)
#   2. OpenCode must respond (pre-flight ping — script exits if it doesn't)
#
# Usage:
#   bash scripts/record-agent.sh
set -euo pipefail

export PATH="${HOME}/.local/bin:/home/vpcuser/bin:${HOME}/.opencode/bin:${HOME}/.local/bin:/usr/local/bin:$PATH"
cd /home/vpcuser/helm-agent-preflight

OPENCODE="${HOME}/.opencode/bin/opencode"
MODEL="${OPENCODE_MODEL:-litellm/claude-sonnet-4-6}"
BINARY="./bin/preflight-linux-amd64"
POLICY="./policies/rego"

# ── 1. Verify OpenCode responds before we record anything ────────────────────
echo "=== Pre-flight: verifying OpenCode responds ==="
PING_RESULT=$(
  "$OPENCODE" run \
    --standalone --auto \
    --model "$MODEL" \
    "Reply with exactly one word: READY" \
    2>/dev/null | tr -d '[:space:]'
)
if [[ -z "$PING_RESULT" ]] || [[ "$PING_RESULT" == *"Error"* ]] || [[ "$PING_RESULT" == *"limit"* ]]; then
  echo "ERROR: OpenCode did not respond (got: '${PING_RESULT}')" >&2
  echo "Check ~/.config/opencode/opencode.json and your API key." >&2
  exit 1
fi
echo "OpenCode responded: ${PING_RESULT} ✓"

# ── 2. Verify kind cluster is running ────────────────────────────────────────
echo "=== Pre-flight: verifying kind cluster ==="
if ! kubectl cluster-info --context kind-preflight-demo &>/dev/null; then
  echo "ERROR: kind cluster 'preflight-demo' is not running." >&2
  echo "Start it with:" >&2
  echo "  KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --name preflight-demo" >&2
  exit 1
fi
echo "kind cluster 'preflight-demo' is running ✓"
echo ""
echo "=== All pre-flights passed — starting recording ==="
echo ""

# ── Typing animation helper ───────────────────────────────────────────────────
typeout() {
  local str="$1"
  local delay="${2:-0.04}"
  while IFS= read -r -n1 char; do
    printf '%s' "$char"
    sleep "$delay"
  done <<< "$str"
}

# ── The recording content ─────────────────────────────────────────────────────
sleep 1

# Show the cluster context first
printf '\033[0;32m~/helm-agent-preflight\033[0m \033[0;34m$\033[0m '
sleep 0.3
typeout 'kubectl get nodes --context kind-preflight-demo' 0.05
echo ""
sleep 0.3
kubectl get nodes --context kind-preflight-demo
sleep 2
echo ""

# Show the opencode run command being typed
printf '\033[0;32m~/helm-agent-preflight\033[0m \033[0;34m$\033[0m '
sleep 0.3
typeout 'opencode run \' 0.05
echo ""
sleep 0.2
printf '  '
typeout '--file skills/helm-preflight/SKILL.md \' 0.04
echo ""
sleep 0.2
printf '  '
typeout '"Qualify the Helm upgrade from examples/rbac-escalation/baseline' 0.04
echo ""
printf '   '
typeout ' to examples/rbac-escalation/candidate, release demo-app,' 0.04
echo ""
printf '   '
typeout ' namespace default, Kubernetes 1.35. Run the tool. Report the verdict."' 0.04
echo ""
sleep 0.5

# Run OpenCode for real
"$OPENCODE" run \
  --standalone \
  --auto \
  --model "$MODEL" \
  --file "skills/helm-preflight/SKILL.md" \
  "Qualify the Helm upgrade from examples/rbac-escalation/baseline to examples/rbac-escalation/candidate, release demo-app, namespace default, Kubernetes 1.35. The preflight binary is at ${BINARY} and the policy dir is ${POLICY}. Run the tool, report the verdict, all findings, and propose the smallest fix." \
  2>/dev/null

# 10-second pause so the viewer can read the output
echo ""
for i in $(seq 10 -1 1); do
  echo "  Reviewing output... ${i}s"
  sleep 1
done
