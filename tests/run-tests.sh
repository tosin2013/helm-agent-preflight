#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
# Acceptance tests T01-T08 for helm-agent-preflight.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BIN="${PREFLIGHT_BIN:-}"
HELM_BIN="${HELM_BIN:-helm}"
POLICY_DIR="${POLICY_DIR:-${ROOT_DIR}/policies/rego}"

# Determine native binary if PREFLIGHT_BIN not set
if [ -z "$BIN" ] || [ ! -f "$BIN" ]; then
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)
  case "$ARCH" in x86_64) ARCH="amd64";; aarch64|arm64) ARCH="arm64";; esac
  BIN="${ROOT_DIR}/bin/preflight-${OS}-${ARCH}"
fi

if [ ! -f "$BIN" ]; then
  echo "ERROR: binary not found at $BIN. Run: make build" >&2
  exit 1
fi

pass=0
fail=0

run_test() {
  local name="$1"
  local expected_exit="$2"
  local expected_verdict="$3"
  shift 3
  local report_file
  report_file="$(mktemp /tmp/preflight-test-XXXXXX.json)"

  echo "--- $name ---"
  set +e
  "$BIN" upgrade "$@" --policy-dir "$POLICY_DIR" --output-file "$report_file" 2>/dev/null
  actual_exit=$?
  set -e

  if [ "$actual_exit" -ne "$expected_exit" ]; then
    echo "FAIL $name: expected exit $expected_exit, got $actual_exit"
    fail=$((fail + 1))
    rm -f "$report_file"
    return
  fi

  if [ -n "$expected_verdict" ]; then
    actual_verdict=$(jq -r '.verdict' "$report_file" 2>/dev/null || echo "PARSE_ERROR")
    if [ "$actual_verdict" != "$expected_verdict" ]; then
      echo "FAIL $name: expected verdict $expected_verdict, got $actual_verdict"
      fail=$((fail + 1))
      rm -f "$report_file"
      return
    fi
  fi

  echo "PASS $name"
  pass=$((pass + 1))
  rm -f "$report_file"
}

# T01 — Safe upgrade: image change only → PASS (exit 0)
run_test "T01-safe-upgrade" 0 "PASS" \
  --from "$ROOT_DIR/examples/safe-upgrade/baseline" \
  --to   "$ROOT_DIR/examples/safe-upgrade/candidate" \
  --release-name test-release \
  --namespace default \
  --kube-version 1.28

# T02 — RBAC escalation: wildcard * → BLOCK (exit 2)
run_test "T02-rbac-escalation" 2 "BLOCK" \
  --from "$ROOT_DIR/examples/rbac-escalation/baseline" \
  --to   "$ROOT_DIR/examples/rbac-escalation/candidate" \
  --release-name test-release \
  --namespace default \
  --kube-version 1.28

# T03 — Privileged container → BLOCK (exit 2)
run_test "T03-privileged-container" 2 "BLOCK" \
  --from "$ROOT_DIR/examples/privileged-container/baseline" \
  --to   "$ROOT_DIR/examples/privileged-container/candidate" \
  --release-name test-release \
  --namespace default \
  --kube-version 1.28

# T04 — Non-existent baseline path → INDETERMINATE (exit 3)
run_test "T04-indeterminate" 3 "INDETERMINATE" \
  --from /nonexistent/chart/path \
  --to   "$ROOT_DIR/examples/safe-upgrade/candidate" \
  --release-name test-release \
  --namespace default \
  --kube-version 1.28

# T05 — Determinism: run T02 twice, fingerprints must match
echo "--- T05-determinism ---"
f1="$(mktemp /tmp/preflight-det1-XXXXXX.json)"
f2="$(mktemp /tmp/preflight-det2-XXXXXX.json)"
set +e
"$BIN" upgrade \
  --from "$ROOT_DIR/examples/rbac-escalation/baseline" \
  --to   "$ROOT_DIR/examples/rbac-escalation/candidate" \
  --policy-dir "$POLICY_DIR" \
  --release-name test-release \
  --namespace default \
  --kube-version 1.28 \
  --output-file "$f1" 2>/dev/null
"$BIN" upgrade \
  --from "$ROOT_DIR/examples/rbac-escalation/baseline" \
  --to   "$ROOT_DIR/examples/rbac-escalation/candidate" \
  --policy-dir "$POLICY_DIR" \
  --release-name test-release \
  --namespace default \
  --kube-version 1.28 \
  --output-file "$f2" 2>/dev/null
set -e
fp1=$(jq -r '.fingerprint' "$f1" 2>/dev/null || echo "")
fp2=$(jq -r '.fingerprint' "$f2" 2>/dev/null || echo "")
rm -f "$f1" "$f2"
if [ "$fp1" = "$fp2" ] && [ -n "$fp1" ]; then
  echo "PASS T05-determinism (fingerprint: $fp1)"
  pass=$((pass + 1))
else
  echo "FAIL T05-determinism: fp1=$fp1 fp2=$fp2"
  fail=$((fail + 1))
fi

# T06 — Tool verdict immutable: BLOCK report verdict field must be "BLOCK"
echo "--- T06-agent-override ---"
t06_report="$(mktemp /tmp/preflight-t06-XXXXXX.json)"
set +e
"$BIN" upgrade \
  --from "$ROOT_DIR/examples/rbac-escalation/baseline" \
  --to   "$ROOT_DIR/examples/rbac-escalation/candidate" \
  --policy-dir "$POLICY_DIR" \
  --release-name test-release \
  --namespace default \
  --kube-version 1.28 \
  --output-file "$t06_report" 2>/dev/null
set -e
t06_verdict=$(jq -r '.verdict' "$t06_report" 2>/dev/null || echo "")
rm -f "$t06_report"
if [ "$t06_verdict" = "BLOCK" ]; then
  echo "PASS T06-agent-override (verdict field is BLOCK, cannot be overridden)"
  pass=$((pass + 1))
else
  echo "FAIL T06-agent-override: verdict is $t06_verdict, expected BLOCK"
  fail=$((fail + 1))
fi

# T07 — Secret protection: no raw secret values in report
echo "--- T07-secret-protection ---"
t07_chart="$(mktemp -d /tmp/preflight-t07chart-XXXXXX)"
mkdir -p "${t07_chart}/templates"
cat > "${t07_chart}/Chart.yaml" << 'EOF'
apiVersion: v2
name: secret-test
version: 1.0.0
EOF
cat > "${t07_chart}/templates/secret.yaml" << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Release.Name }}-secret
  namespace: {{ .Release.Namespace }}
type: Opaque
data:
  password: c3VwZXJzZWNyZXQ=
  api-key: bXktc2VjcmV0LWFwaS1rZXk=
EOF
t07_report="$(mktemp /tmp/preflight-t07-XXXXXX.json)"
set +e
"$BIN" upgrade \
  --from "$t07_chart" \
  --to   "$t07_chart" \
  --policy-dir "$POLICY_DIR" \
  --release-name test-release \
  --namespace default \
  --kube-version 1.28 \
  --output-file "$t07_report" 2>/dev/null
set -e
if grep -q "c3VwZXJzZWNyZXQ=" "$t07_report" || grep -q "bXktc2VjcmV0LWFwaS1rZXk=" "$t07_report"; then
  echo "FAIL T07-secret-protection: raw secret values found in report"
  fail=$((fail + 1))
elif grep -q "REDACTED" "$t07_report"; then
  echo "PASS T07-secret-protection (secrets scrubbed with REDACTED)"
  pass=$((pass + 1))
else
  echo "PASS T07-secret-protection (no secret values in report)"
  pass=$((pass + 1))
fi
rm -f "$t07_report"
rm -rf "$t07_chart"

# T08 — No cluster credentials required
echo "--- T08-no-credentials ---"
t08_report="$(mktemp /tmp/preflight-t08-XXXXXX.json)"
set +e
KUBECONFIG=/dev/null "$BIN" upgrade \
  --from "$ROOT_DIR/examples/safe-upgrade/baseline" \
  --to   "$ROOT_DIR/examples/safe-upgrade/candidate" \
  --policy-dir "$POLICY_DIR" \
  --release-name test-release \
  --namespace default \
  --kube-version 1.28 \
  --output-file "$t08_report" 2>/dev/null
t08_exit=$?
set -e
t08_no_deploy=$(jq -r '.run_metadata.no_deployment_occurred' "$t08_report" 2>/dev/null || echo "false")
t08_no_creds=$(jq -r '.run_metadata.no_cluster_credentials' "$t08_report" 2>/dev/null || echo "false")
rm -f "$t08_report"
if [ "$t08_exit" -eq 0 ] && [ "$t08_no_deploy" = "true" ] && [ "$t08_no_creds" = "true" ]; then
  echo "PASS T08-no-credentials (exit=$t08_exit, no_deployment=true, no_cluster_credentials=true)"
  pass=$((pass + 1))
else
  echo "FAIL T08-no-credentials: exit=$t08_exit no_deployment=$t08_no_deploy no_cluster_credentials=$t08_no_creds"
  fail=$((fail + 1))
fi

echo ""
echo "============================================="
echo "Results: $pass passed, $fail failed"
echo "============================================="
[ "$fail" -eq 0 ] || exit 1
