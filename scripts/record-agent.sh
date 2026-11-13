#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
# Minimal recording script — shows the raw opencode run invocation
# so the GIF looks exactly like: opencode run "Explain how closures work"
# but for Helm upgrade qualification.
export PATH="${HOME}/.opencode/bin:/home/vpcuser/bin:${HOME}/.local/bin:/usr/local/bin:$PATH"
cd /home/vpcuser/helm-agent-preflight
set +e

OPENCODE="${HOME}/.opencode/bin/opencode"
MODEL="${OPENCODE_MODEL:-litellm/claude-sonnet-4-6}"

# Type a string character by character to simulate a human typing
typeout() {
  local str="$1"
  local delay="${2:-0.04}"
  while IFS= read -r -n1 char; do
    printf '%s' "$char"
    sleep "$delay"
  done <<< "$str"
}

# ── show a clean prompt and the command being typed ───────────────────────────
sleep 1
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
typeout ' namespace default, Kubernetes 1.28. Run the tool. Report the verdict."' 0.04
echo ""
sleep 0.5

# ── actually run opencode ─────────────────────────────────────────────────────
"$OPENCODE" run \
  --standalone \
  --auto \
  --model "$MODEL" \
  --file "skills/helm-preflight/SKILL.md" \
  "Qualify the Helm upgrade from examples/rbac-escalation/baseline to examples/rbac-escalation/candidate, release demo-app, namespace default, Kubernetes 1.28. The preflight binary is at ./bin/preflight-linux-amd64 and the policy dir is ./policies/rego. Run the tool, report the verdict, all findings, and propose the smallest fix." \
  2>/dev/null

# ── pause so the viewer can read the output ───────────────────────────────────
echo ""
for i in $(seq 10 -1 1); do
  echo "  Reviewing output... ${i}s"
  sleep 1
done
