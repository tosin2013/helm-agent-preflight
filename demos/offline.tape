# helm-agent-preflight — offline scenarios demo
# Records 3 scenarios: PASS, BLOCK (RBAC), BLOCK (privileged)
# Run:  vhs demos/offline.tape
# Needs: bin/preflight-linux-amd64, conftest in PATH, make build first

Output demos/offline.gif

Set Width 160
Set Height 44
Set FontSize 13
Set Theme "Dracula"
Set TypingSpeed 25ms
Set CursorBlink false

# Silent setup: ensure conftest and binary are accessible
Hide
  export PATH="/home/vpcuser/bin:/usr/local/bin:$PATH"
  PREFLIGHT="./bin/preflight-linux-amd64"
  POLICY="./policies/rego"
  alias pf="$PREFLIGHT upgrade --release-name demo --namespace default --kube-version 1.28 --policy-dir $POLICY"
Show

Sleep 500ms

# Title
Type "# helm-agent-preflight — offline Helm upgrade qualification"
Enter
Sleep 400ms
Type "# No cluster · No network · No deployment"
Enter
Sleep 1s

# ─── Scenario A: PASS ────────────────────────────────────────────────────────
Type "# ✔  Scenario A: safe image-tag upgrade (nginx 1.24 → 1.25)"
Enter
Sleep 300ms

Type "./bin/preflight-linux-amd64 upgrade \
  --from examples/safe-upgrade/baseline \
  --to   examples/safe-upgrade/candidate \
  --release-name demo --namespace default \
  --kube-version 1.28 --policy-dir policies/rego \
  | jq '{verdict, diff_counts: {added: .diff_summary.added_count, modified: .diff_summary.modified_count}, findings: (.security_findings|length)}'"
Enter
Sleep 10s

# ─── Scenario B: BLOCK — RBAC ────────────────────────────────────────────────
Type "# ✘  Scenario B: wildcard ClusterRole → BLOCK"
Enter
Sleep 300ms

Type "./bin/preflight-linux-amd64 upgrade \
  --from examples/rbac-escalation/baseline \
  --to   examples/rbac-escalation/candidate \
  --release-name demo --namespace default \
  --kube-version 1.28 --policy-dir policies/rego \
  | jq '{verdict, findings: [.security_findings[] | {rule: .rule_id, severity, object: (.object.kind+\"/\"+.object.name), msg: .message}]}'"
Enter
Sleep 12s

# ─── Scenario C: BLOCK — privileged ──────────────────────────────────────────
Type "# ✘  Scenario C: privileged container → BLOCK"
Enter
Sleep 300ms

Type "./bin/preflight-linux-amd64 upgrade \
  --from examples/privileged-container/baseline \
  --to   examples/privileged-container/candidate \
  --release-name demo --namespace default \
  --kube-version 1.28 --policy-dir policies/rego \
  | jq '{verdict, finding: .security_findings[0] | {rule: .rule_id, severity, msg: .message, new: (if .pre_existing then \"pre-existing\" else \"newly-introduced\" end)}}'"
Enter
Sleep 10s

# Footer
Type "# Fingerprints are deterministic — same inputs always produce same verdict"
Enter
Sleep 2s
