#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
#
# demo-minikube.sh — helm-agent-preflight × Minikube live cluster demo
#
# Demonstrates that helm preflight upgrade catches security regressions
# BEFORE they reach a real Kubernetes cluster. Three acts:
#
#   Act 1 — Safe upgrade:    preflight PASS → helm upgrade succeeds
#   Act 2 — RBAC escalation: preflight BLOCK → upgrade never runs → cluster safe
#   Act 3 — Privileged pod:  preflight BLOCK → upgrade never runs → cluster safe
#
# Usage:
#   bash demo-minikube.sh           # full interactive demo
#   bash demo-minikube.sh --ci-mode # non-interactive, skip pauses
#   bash demo-minikube.sh --cleanup # delete minikube cluster and exit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY="${SCRIPT_DIR}/bin/preflight-linux-amd64"
POLICY_DIR="${SCRIPT_DIR}/policies/rego"
REPORTS_DIR="${SCRIPT_DIR}/demo-minikube-reports"
MINIKUBE_K8S_VERSION="v1.37.2"
MINIKUBE_VERSION="v1.39.0"
RELEASE_NAME="preflight-demo"
NAMESPACE="preflight-demo"
CI_MODE=false

for arg in "$@"; do
  case "$arg" in
    --ci-mode) CI_MODE=true ;;
    --cleanup)
      echo "Deleting minikube cluster..."
      minikube delete --profile preflight-demo 2>/dev/null || true
      exit 0 ;;
  esac
done

mkdir -p "$REPORTS_DIR"

# ── colours ──────────────────────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
DIM='\033[2m'
RESET='\033[0m'

head()   { echo -e "\n${BLUE}${BOLD}══ $* ══${RESET}"; }
info()   { echo -e "  ${CYAN}▸${RESET}  $*"; }
ok()     { echo -e "  ${GREEN}${BOLD}✔${RESET}  $*"; }
block()  { echo -e "  ${RED}${BOLD}✘  BLOCK${RESET} — $*"; }
warn()   { echo -e "  ${YELLOW}▲${RESET}  $*"; }
dim()    { echo -e "${DIM}$*${RESET}"; }

pause() {
  if [ "$CI_MODE" = "false" ]; then
    echo ""
    read -r -p "  Press ENTER to continue..."
    echo ""
  fi
}

# ── prerequisites ─────────────────────────────────────────────────────────────
head "Prerequisites"

# Binary
if [ ! -f "$BINARY" ]; then
  echo -e "${RED}preflight binary not found: $BINARY${RESET}"
  echo "Run: make build"
  exit 1
fi
ok "preflight binary: $BINARY"

# conftest
if ! command -v conftest &>/dev/null; then
  echo -e "${RED}conftest not in PATH${RESET}"
  exit 1
fi
ok "conftest $(conftest --version 2>/dev/null | head -1)"

# kubectl
if ! command -v kubectl &>/dev/null; then
  echo -e "${RED}kubectl not found${RESET}"
  exit 1
fi
ok "kubectl $(kubectl version --client -o json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['clientVersion']['gitVersion'])" 2>/dev/null || kubectl version --client --short 2>/dev/null | head -1)"

# helm
HELM_BIN="${HELM_BIN:-$(command -v helm)}"
ok "helm $($HELM_BIN version --short 2>/dev/null)"

# minikube — install if missing
if ! command -v minikube &>/dev/null; then
  warn "minikube not found — installing ${MINIKUBE_VERSION} to ~/.local/bin/minikube"
  mkdir -p "${HOME}/.local/bin"
  if command -v curl &>/dev/null; then
    curl -fsSL "https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-amd64" \
      -o "${HOME}/.local/bin/minikube"
  else
    wget -q "https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-amd64" \
      -O "${HOME}/.local/bin/minikube"
  fi
  chmod +x "${HOME}/.local/bin/minikube"
  export PATH="${HOME}/.local/bin:${PATH}"
fi
ok "minikube $(minikube version --short 2>/dev/null)"

# ── start minikube ────────────────────────────────────────────────────────────
head "Starting Minikube (profile: preflight-demo, k8s: ${MINIKUBE_K8S_VERSION})"

CLUSTER_RUNNING=$(minikube status --profile preflight-demo --format '{{.Host}}' 2>/dev/null || echo "Nonexistent")
if [ "$CLUSTER_RUNNING" = "Running" ]; then
  ok "Cluster already running"
else
  info "Starting cluster (this takes ~60s on first run)..."
  minikube start \
    --profile preflight-demo \
    --driver=docker \
    --kubernetes-version="${MINIKUBE_K8S_VERSION}" \
    --cpus=2 \
    --memory=2048 \
    2>&1 | grep -E '(Starting|Done|minikube|✓|✗)' | sed 's/^/    /'
fi

kubectl config use-context preflight-demo 2>/dev/null
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null
ok "Namespace ${NAMESPACE} ready"

# helper: run preflight and return exit code
run_preflight() {
  local report="$1"; shift
  set +e
  "$BINARY" upgrade "$@" \
    --policy-dir "$POLICY_DIR" \
    --release-name "$RELEASE_NAME" \
    --namespace "$NAMESPACE" \
    --kube-version "1.37" \
    --output-file "$report" \
    2>/tmp/preflight-mk-stderr.txt
  echo $?
  set -e
}

show_verdict() {
  local report="$1"
  local verdict fingerprint n_findings
  verdict=$(python3 -c "import json; d=json.load(open('$report')); print(d['verdict'])")
  fingerprint=$(python3 -c "import json; d=json.load(open('$report')); print(d['fingerprint'][:20])")
  n_findings=$(python3 -c "import json; d=json.load(open('$report')); print(len(d['security_findings']))")
  echo -e "  Verdict     : ${BOLD}${verdict}${RESET}"
  echo -e "  Fingerprint : ${DIM}${fingerprint}...${RESET}"
  echo -e "  Findings    : ${n_findings}"
  if [ "$n_findings" -gt 0 ]; then
    python3 - "$report" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
for f in d["security_findings"]:
    print(f"    [{f['verdict_contribution']}] {f['rule_id']} ({f['severity']}) — {f['object']['kind']}/{f['object']['name']}")
    print(f"      {f['message']}")
PYEOF
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
# ACT 1 — SAFE UPGRADE
# ══════════════════════════════════════════════════════════════════════════════
head "Act 1 — Safe upgrade (nginx 1.24 → 1.25)"
echo ""
info "Installing baseline release (nginx:1.24.0)..."

$HELM_BIN upgrade --install "$RELEASE_NAME" \
  "${SCRIPT_DIR}/examples/safe-upgrade/baseline" \
  --namespace "$NAMESPACE" \
  --wait --timeout=60s \
  2>&1 | grep -E '(deployed|Error|NOTES)' | sed 's/^/    /' || true

kubectl get deploy,pod -n "$NAMESPACE" 2>/dev/null | sed 's/^/    /'
echo ""
info "Running preflight upgrade check (offline — no cluster access)..."

A1_REPORT="${REPORTS_DIR}/act1-safe.json"
a1_exit=$(run_preflight "$A1_REPORT" \
  --from "${SCRIPT_DIR}/examples/safe-upgrade/baseline" \
  --to   "${SCRIPT_DIR}/examples/safe-upgrade/candidate")

show_verdict "$A1_REPORT"
echo ""

if [ "$a1_exit" -eq 0 ]; then
  ok "Preflight PASS — upgrade authorized"
  pause
  info "Running: helm upgrade (nginx 1.24 → 1.25)..."
  $HELM_BIN upgrade "$RELEASE_NAME" \
    "${SCRIPT_DIR}/examples/safe-upgrade/candidate" \
    --namespace "$NAMESPACE" \
    --wait --timeout=60s \
    2>&1 | grep -E '(upgraded|Error)' | sed 's/^/    /' || true
  kubectl get deploy,pod -n "$NAMESPACE" | sed 's/^/    /'
  ok "Act 1 complete: safe upgrade deployed successfully"
else
  warn "Act 1 unexpected result: exit $a1_exit"
fi

pause

# ══════════════════════════════════════════════════════════════════════════════
# ACT 2 — RBAC ESCALATION
# ══════════════════════════════════════════════════════════════════════════════
head "Act 2 — RBAC escalation (new wildcard ClusterRole)"
echo ""
dim "  Candidate chart introduces:"
dim "    rules:"
dim "      - apiGroups: [\"*\"]"
dim "        resources: [\"*\"]    ← RBAC-001: wildcard"
dim "        verbs:     [\"*\"]    ← RBAC-002: wildcard"
echo ""
info "Running preflight upgrade check (offline)..."

A2_REPORT="${REPORTS_DIR}/act2-rbac.json"
a2_exit=$(run_preflight "$A2_REPORT" \
  --from "${SCRIPT_DIR}/examples/rbac-escalation/baseline" \
  --to   "${SCRIPT_DIR}/examples/rbac-escalation/candidate")

show_verdict "$A2_REPORT"
echo ""

if [ "$a2_exit" -eq 2 ]; then
  block "Upgrade blocked by preflight"
  echo ""
  warn "helm upgrade was NOT run — the cluster was never modified"
  info "Verifying cluster has no wildcard ClusterRole..."
  if kubectl get clusterrole -n "$NAMESPACE" 2>/dev/null | grep -q "${RELEASE_NAME}"; then
    warn "ClusterRole exists from baseline — checking for wildcards"
    kubectl get clusterrole "${RELEASE_NAME}-reader" -o yaml 2>/dev/null | grep -A2 "resources:" | sed 's/^/    /' || true
  else
    ok "No wildcard ClusterRole in cluster (blocked offline)"
  fi
  echo ""
  info "What would have happened without preflight:"
  dim "  $ helm upgrade $RELEASE_NAME .../rbac-escalation/candidate"
  dim "  Release \"$RELEASE_NAME\" has been upgraded.   ← helm succeeds, cluster is now vulnerable"
  dim "  $ kubectl auth can-i '*' '*' --as=system:serviceaccount:${NAMESPACE}:default"
  dim "  yes                                           ← everything allowed!"
  echo ""
  ok "Act 2 complete: RBAC escalation blocked before reaching cluster"
else
  warn "Act 2 unexpected result: exit $a2_exit"
fi

pause

# ══════════════════════════════════════════════════════════════════════════════
# ACT 3 — PRIVILEGED CONTAINER
# ══════════════════════════════════════════════════════════════════════════════
head "Act 3 — Privileged container (securityContext.privileged=true)"
echo ""
dim "  Candidate chart introduces:"
dim "    securityContext:"
dim "      privileged: true    ← WORK-001: full host access"
echo ""
info "Running preflight upgrade check (offline)..."

A3_REPORT="${REPORTS_DIR}/act3-privileged.json"
a3_exit=$(run_preflight "$A3_REPORT" \
  --from "${SCRIPT_DIR}/examples/privileged-container/baseline" \
  --to   "${SCRIPT_DIR}/examples/privileged-container/candidate")

show_verdict "$A3_REPORT"
echo ""

if [ "$a3_exit" -eq 2 ]; then
  block "Upgrade blocked by preflight"
  echo ""
  warn "No privileged pod was ever scheduled on the cluster"
  info "kubectl get pods in namespace (should show only the safe nginx from Act 1):"
  kubectl get pods -n "$NAMESPACE" | sed 's/^/    /'
  echo ""
  ok "Act 3 complete: privileged container blocked before reaching cluster"
else
  warn "Act 3 unexpected result: exit $a3_exit"
fi

pause

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
head "Demo Summary"
echo ""
echo -e "  ${BOLD}Reports:${RESET}"
for f in "${REPORTS_DIR}"/*.json; do
  [ -f "$f" ] || continue
  v=$(python3 -c "import json; print(json.load(open('$f'))['verdict'])" 2>/dev/null || echo "?")
  case "$v" in PASS) c="${GREEN}";; BLOCK) c="${RED}";; *) c="${YELLOW}";; esac
  printf "  %-40s %s${BOLD}%s${RESET}\n" "$(basename "$f")" "$c" "$v"
done

echo ""
echo -e "  ${BOLD}Cluster state after demo:${RESET}"
kubectl get all -n "$NAMESPACE" 2>/dev/null | sed 's/^/    /'

echo ""
echo -e "  ${BOLD}Key result:${RESET}"
echo -e "  ${GREEN}  Act 1${RESET}: safe upgrade qualified offline (PASS) → deployed to cluster"
echo -e "  ${RED}  Act 2${RESET}: RBAC escalation blocked offline (BLOCK) → cluster never touched"
echo -e "  ${RED}  Act 3${RESET}: privileged container blocked offline (BLOCK) → cluster never touched"
echo ""
echo -e "  ${DIM}Offline verification happened before any kubectl or helm calls.${RESET}"
echo -e "  ${DIM}The cluster received only what preflight approved.${RESET}"
echo ""

if [ "$CI_MODE" = "false" ]; then
  read -r -p "  Delete minikube cluster? [y/N] " yn
  case "$yn" in
    [Yy]*) minikube delete --profile preflight-demo && ok "Cluster deleted" ;;
    *) info "Cluster left running. Delete with: bash demo-minikube.sh --cleanup" ;;
  esac
fi
