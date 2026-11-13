# helm-agent-preflight — AI agent session demo
#
# Story:
#   Act 0 — webapp is live in the cluster (kubectl get pods)
#   Act 1 — inspect the bad candidate chart (wildcard RBAC)
#   Act 2 — OpenCode agent qualifies the upgrade offline → BLOCK + fix
#   Act 3 — cluster is still clean (bad rules never landed)
#
# Run:   vhs demos/agent.tape
# Needs: bin/preflight-linux-amd64, conftest in PATH, kubectl context set,
#        baseline webapp already installed (bash demo-agent.sh --no-install
#        or run demo-agent.sh once to let it install)

Output demos/agent.gif

Set Width 160
Set Height 50
Set FontSize 13
Set Theme "Dracula"
Set TypingSpeed 28ms
Set CursorBlink false

Hide
  export PATH="/home/vpcuser/bin:/usr/local/bin:$PATH"
  cd /home/vpcuser/helm-agent-preflight
Show

Sleep 800ms

# ── Act 0: show the live app ──────────────────────────────────────────────────
Type "# Act 0 — webapp is live in the cluster"
Enter
Sleep 400ms

Type "kubectl get pods,deploy -n staging"
Enter
Sleep 3s

# ── Act 1: show the bad candidate chart ───────────────────────────────────────
Type "# Act 1 — inspect the candidate chart the team wants to deploy"
Enter
Sleep 400ms

Type "cat examples/rbac-escalation/candidate/templates/rbac.yaml"
Enter
Sleep 3s

Type "# ⚠  apiGroups/resources/verbs are all \"*\" — full cluster access!"
Enter
Sleep 1500ms

# ── Act 2: ask OpenCode to qualify the upgrade ────────────────────────────────
Type "# Act 2 — ask OpenCode to qualify the upgrade (offline, no cluster access)"
Enter
Sleep 400ms

Type "bash demo-agent.sh --no-install"
Enter
# agent runs: preflight binary + LLM interpretation
Sleep 55s

# ── Act 3: prove the cluster was never touched ────────────────────────────────
Type "# Act 3 — verify the cluster was never touched"
Enter
Sleep 400ms

Type "kubectl get clusterrole webapp-reader -o yaml | grep -A8 'rules:'"
Enter
Sleep 3s

Type "kubectl get pods -n staging"
Enter
Sleep 2s

Type "# ✔  Only safe baseline rules in cluster — BLOCK worked offline"
Enter
Sleep 2s
