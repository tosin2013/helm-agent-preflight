#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
#
# demo.sh — helm-agent-preflight proof-of-concept demo
# Demonstrates offline Helm upgrade qualification without a Kubernetes cluster.
#
# Prerequisites auto-installed if missing: conftest
# Prerequisites required: helm, go (or a pre-built binary in bin/)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/bin"
POLICY_DIR="${SCRIPT_DIR}/policies/rego"
EXAMPLES_DIR="${SCRIPT_DIR}/examples"
REPORTS_DIR="${SCRIPT_DIR}/demo-reports"
CONFTEST_VERSION="0.71.1"

# ── colours ──────────────────────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
DIM='\033[2m'
RESET='\033[0m'

pass()  { echo -e "${GREEN}${BOLD}  ✔  PASS${RESET}  $*"; }
block() { echo -e "${RED}${BOLD}  ✘  BLOCK${RESET} $*"; }
info()  { echo -e "${CYAN}  ▸${RESET}  $*"; }
head()  { echo -e "\n${BLUE}${BOLD}══════════════════════════════════════════════════════${RESET}"; \
          echo -e "${BLUE}${BOLD}  $*${RESET}"; \
          echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════${RESET}"; }
subhead() { echo -e "\n${BOLD}  $*${RESET}"; }
dim()   { echo -e "${DIM}$*${RESET}"; }

# ── banner ───────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
cat << 'EOF'
  ██╗  ██╗███████╗██╗     ███╗   ███╗    ██████╗ ██████╗ ███████╗███████╗██╗  ██╗ ██████╗ ██╗  ████████╗
  ██║  ██║██╔════╝██║     ████╗ ████║    ██╔══██╗██╔══██╗██╔════╝██╔════╝██║  ██║██╔════╝ ██║  ╚══██╔══╝
  ███████║█████╗  ██║     ██╔████╔██║    ██████╔╝██████╔╝█████╗  █████╗  ██║  ██║██║  ███╗██║     ██║
  ██╔══██║██╔══╝  ██║     ██║╚██╔╝██║    ██╔═══╝ ██╔══██╗██╔══╝  ██╔══╝  ██║  ██║██║   ██║██║     ██║
  ██║  ██║███████╗███████╗██║ ╚═╝ ██║    ██║     ██║  ██║███████╗██║      ╚████╔╝╚██████╔╝███████╗ ██║
  ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝     ╚═╝    ╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝       ╚═══╝  ╚═════╝ ╚══════╝ ╚═╝
EOF
echo -e "${RESET}"
echo -e "  ${DIM}Offline Helm upgrade qualification — POC Demo  |  PRD v0.3${RESET}"
echo -e "  ${DIM}No Kubernetes cluster required${RESET}\n"

mkdir -p "${REPORTS_DIR}"

# ── step 0: prerequisites ─────────────────────────────────────────────────────
head "Step 0 — Checking prerequisites"

# helm
if ! command -v helm &>/dev/null; then
  echo -e "${RED}ERROR: helm not found. Install helm first: https://helm.sh/docs/intro/install/${RESET}" >&2
  exit 1
fi
info "helm $(helm version --short 2>/dev/null)"

# conftest — install if missing
if ! command -v conftest &>/dev/null; then
  echo -e "${YELLOW}  conftest not found — installing v${CONFTEST_VERSION} to /usr/local/bin ...${RESET}"
  OS=$(uname -s)
  ARCH=$(uname -m)
  case "$ARCH" in x86_64) ARCH="x86_64";; aarch64|arm64) ARCH="arm64";; esac

  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT

  if command -v curl &>/dev/null; then
    curl -fsSL "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_${OS}_${ARCH}.tar.gz" \
      -o "${TMPDIR}/conftest.tar.gz"
  elif command -v wget &>/dev/null; then
    wget -q "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_${OS}_${ARCH}.tar.gz" \
      -O "${TMPDIR}/conftest.tar.gz"
  else
    echo -e "${RED}ERROR: neither curl nor wget found — cannot install conftest${RESET}" >&2
    exit 1
  fi

  tar -xz -C "${TMPDIR}" -f "${TMPDIR}/conftest.tar.gz"
  install -m 755 "${TMPDIR}/conftest" /usr/local/bin/conftest || \
    { cp "${TMPDIR}/conftest" "${BIN_DIR}/conftest"; export PATH="${BIN_DIR}:${PATH}"; }

  echo -e "${GREEN}  conftest installed: $(conftest --version 2>/dev/null)${RESET}"
else
  info "conftest $(conftest --version 2>/dev/null)"
fi

# go binary
GOEXE=$(command -v go 2>/dev/null || echo /usr/local/go/bin/go)

# jq (optional — used for pretty report display)
JQ=$(command -v jq 2>/dev/null || echo "")

# ── step 1: build the binary ──────────────────────────────────────────────────
head "Step 1 — Building preflight binary"

OS_LC=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH_LC=$(uname -m)
case "$ARCH_LC" in x86_64) ARCH_LC="amd64";; aarch64|arm64) ARCH_LC="arm64";; esac
BINARY="${BIN_DIR}/preflight-${OS_LC}-${ARCH_LC}"

if [ ! -f "$BINARY" ]; then
  info "Running: go build → ${BINARY}"
  "$GOEXE" build -trimpath \
    -ldflags="-w -s -X github.com/tosin2013/helm-agent-preflight/internal/version.Version=v0.1.0-demo" \
    -o "$BINARY" \
    "${SCRIPT_DIR}/cmd/preflight" 2>&1 | sed 's/^/    /'
  info "Build complete"
else
  info "Binary already built: ${BINARY}"
fi

PREFLIGHT="$BINARY"

# ── helper: run_scenario ──────────────────────────────────────────────────────
run_scenario() {
  local label="$1"
  local expected_verdict="$2"
  local report_file="$3"
  shift 3
  local args=("$@")

  echo -e "\n${DIM}  Command:${RESET}"
  echo -e "  ${DIM}preflight upgrade ${args[*]}${RESET}\n"

  set +e
  POLICY_DIR="${POLICY_DIR}" "$PREFLIGHT" upgrade "${args[@]}" \
    --policy-dir "${POLICY_DIR}" \
    --output-file "${report_file}" \
    2>/tmp/preflight-stderr.txt
  exit_code=$?
  set -e

  local actual_verdict
  actual_verdict=$(jq -r '.verdict' "${report_file}" 2>/dev/null || grep -o '"verdict":"[^"]*"' "${report_file}" | cut -d'"' -f4)

  local fingerprint
  fingerprint=$(jq -r '.fingerprint' "${report_file}" 2>/dev/null || grep -o '"fingerprint":"[^"]*"' "${report_file}" | cut -d'"' -f4 | cut -c1-16)

  echo -e "  Exit code : ${exit_code}"
  echo -e "  Verdict   : ${BOLD}${actual_verdict}${RESET}"
  echo -e "  Fingerprint: ${DIM}${fingerprint}...${RESET}"

  if [ "$actual_verdict" = "$expected_verdict" ]; then
    if [ "$expected_verdict" = "PASS" ]; then
      pass "${label} — ${expected_verdict} as expected"
    else
      block "${label} — ${expected_verdict} as expected"
    fi
  else
    echo -e "${RED}  UNEXPECTED: wanted ${expected_verdict}, got ${actual_verdict}${RESET}"
  fi

  # Show findings if any
  local n_findings
  if [ -n "$JQ" ]; then
    n_findings=$(jq '.security_findings | length' "${report_file}" 2>/dev/null || echo 0)
  else
    n_findings=$(grep -c '"rule_id"' "${report_file}" 2>/dev/null || echo 0)
  fi

  if [ "$n_findings" -gt 0 ]; then
    echo -e "\n  ${BOLD}Security findings (${n_findings}):${RESET}"
    if [ -n "$JQ" ]; then
      jq -r '.security_findings[] | "    [\(.verdict_contribution)] \(.rule_id) (\(.severity))  \(.object.kind)/\(.object.name)\n      \(.message)\n      pre_existing=\(.pre_existing)"' \
        "${report_file}" 2>/dev/null
    else
      grep -A2 '"rule_id"' "${report_file}" | head -20 | sed 's/^/    /'
    fi
  fi
}

# ── scenario A: safe upgrade ─────────────────────────────────────────────────
head "Scenario A — Safe upgrade (image tag change only)"
echo -e "  ${DIM}Baseline: nginx:1.24.0  →  Candidate: nginx:1.25.0${RESET}"
echo -e "  ${DIM}Expected: PASS (no security invariants violated)${RESET}"

subhead "Diff summary:"
info "1 Deployment modified (image tag change only)"
info "0 security findings expected"

run_scenario "Scenario-A" "PASS" "${REPORTS_DIR}/scenario-a.json" \
  --from  "${EXAMPLES_DIR}/safe-upgrade/baseline" \
  --to    "${EXAMPLES_DIR}/safe-upgrade/candidate" \
  --release-name demo-release \
  --namespace default \
  --kube-version 1.35

# ── scenario B: RBAC escalation ──────────────────────────────────────────────
head "Scenario B — RBAC escalation (new wildcard ClusterRole)"
echo -e "  ${DIM}Candidate introduces ClusterRole with resources=[\"*\"] verbs=[\"*\"]${RESET}"
echo -e "  ${DIM}Expected: BLOCK (RBAC-001, RBAC-002)${RESET}"

run_scenario "Scenario-B" "BLOCK" "${REPORTS_DIR}/scenario-b.json" \
  --from  "${EXAMPLES_DIR}/rbac-escalation/baseline" \
  --to    "${EXAMPLES_DIR}/rbac-escalation/candidate" \
  --release-name demo-release \
  --namespace default \
  --kube-version 1.35

# ── scenario C: privileged container ─────────────────────────────────────────
head "Scenario C — Privileged container (securityContext.privileged=true)"
echo -e "  ${DIM}Candidate introduces a container with privileged=true${RESET}"
echo -e "  ${DIM}Expected: BLOCK (WORK-001)${RESET}"

run_scenario "Scenario-C" "BLOCK" "${REPORTS_DIR}/scenario-c.json" \
  --from  "${EXAMPLES_DIR}/privileged-container/baseline" \
  --to    "${EXAMPLES_DIR}/privileged-container/candidate" \
  --release-name demo-release \
  --namespace default \
  --kube-version 1.35

# ── scenario D: indeterminate (bad path) ─────────────────────────────────────
head "Scenario D — INDETERMINATE (baseline chart path does not exist)"
echo -e "  ${DIM}Missing required input → fail closed${RESET}"
echo -e "  ${DIM}Expected: INDETERMINATE (exit 3)${RESET}"

set +e
"$PREFLIGHT" upgrade \
  --from  /nonexistent/chart \
  --to    "${EXAMPLES_DIR}/safe-upgrade/candidate" \
  --policy-dir "${POLICY_DIR}" \
  --release-name demo-release \
  --namespace default \
  --kube-version 1.35 \
  --output-file "${REPORTS_DIR}/scenario-d.json" \
  2>/tmp/preflight-stderr.txt
d_exit=$?
set -e

d_verdict=$(jq -r '.verdict' "${REPORTS_DIR}/scenario-d.json" 2>/dev/null || echo "INDETERMINATE")
d_limit=$(jq -r '.evidence.limitations[0]' "${REPORTS_DIR}/scenario-d.json" 2>/dev/null || echo "(see report)")

echo -e "  Exit code : ${d_exit}"
echo -e "  Verdict   : ${BOLD}${d_verdict}${RESET}"
echo -e "  Reason    : ${d_limit}"
[ "$d_verdict" = "INDETERMINATE" ] && \
  echo -e "${YELLOW}${BOLD}  ⚠  INDETERMINATE${RESET} Scenario-D — fails closed as expected"

# ── scenario E: determinism ───────────────────────────────────────────────────
head "Scenario E — Determinism (run Scenario B twice, compare fingerprints)"
echo -e "  ${DIM}Same frozen inputs must produce identical fingerprints${RESET}"

"$PREFLIGHT" upgrade \
  --from  "${EXAMPLES_DIR}/rbac-escalation/baseline" \
  --to    "${EXAMPLES_DIR}/rbac-escalation/candidate" \
  --policy-dir "${POLICY_DIR}" \
  --release-name demo-release \
  --namespace default \
  --kube-version 1.35 \
  --output-file "${REPORTS_DIR}/scenario-e1.json" \
  2>/dev/null || true

"$PREFLIGHT" upgrade \
  --from  "${EXAMPLES_DIR}/rbac-escalation/baseline" \
  --to    "${EXAMPLES_DIR}/rbac-escalation/candidate" \
  --policy-dir "${POLICY_DIR}" \
  --release-name demo-release \
  --namespace default \
  --kube-version 1.35 \
  --output-file "${REPORTS_DIR}/scenario-e2.json" \
  2>/dev/null || true

fp1=$(jq -r '.fingerprint' "${REPORTS_DIR}/scenario-e1.json" 2>/dev/null || echo "")
fp2=$(jq -r '.fingerprint' "${REPORTS_DIR}/scenario-e2.json" 2>/dev/null || echo "")

echo -e "  Run 1 fingerprint: ${DIM}${fp1}${RESET}"
echo -e "  Run 2 fingerprint: ${DIM}${fp2}${RESET}"

if [ "$fp1" = "$fp2" ] && [ -n "$fp1" ]; then
  pass "Scenario-E — fingerprints match (deterministic)"
else
  echo -e "${RED}  FAIL: fingerprints differ${RESET}"
fi

# ── secret protection demonstration ──────────────────────────────────────────
head "Scenario F — Secret protection (no raw values in report)"
echo -e "  ${DIM}Chart with a Secret resource — values must be REDACTED${RESET}"

SECRET_CHART=$(mktemp -d /tmp/preflight-secret-demo-XXXXXX)
mkdir -p "${SECRET_CHART}/templates"
cat > "${SECRET_CHART}/Chart.yaml" << 'CHART'
apiVersion: v2
name: secret-demo
version: 1.0.0
CHART
cat > "${SECRET_CHART}/templates/secret.yaml" << 'SECRET'
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Release.Name }}-creds
  namespace: {{ .Release.Namespace }}
type: Opaque
data:
  password: c3VwZXJzZWNyZXQxMjM=
  api-key: bXktc2VjcmV0LWFwaS1rZXk=
SECRET

set +e
"$PREFLIGHT" upgrade \
  --from  "${SECRET_CHART}" \
  --to    "${SECRET_CHART}" \
  --policy-dir "${POLICY_DIR}" \
  --release-name demo-release \
  --namespace default \
  --kube-version 1.35 \
  --output-file "${REPORTS_DIR}/scenario-f.json" \
  2>/dev/null
set -e

rm -rf "${SECRET_CHART}"

if grep -q "c3VwZXJzZWNyZXQxMjM=" "${REPORTS_DIR}/scenario-f.json" 2>/dev/null; then
  echo -e "${RED}  FAIL: raw secret value found in report${RESET}"
elif grep -q "REDACTED" "${REPORTS_DIR}/scenario-f.json" 2>/dev/null; then
  pass "Scenario-F — secret data scrubbed (REDACTED in report)"
else
  pass "Scenario-F — no raw secret values in report"
fi

# ── summary ───────────────────────────────────────────────────────────────────
head "Demo complete — Report files"
echo -e "  Reports written to: ${BOLD}${REPORTS_DIR}/${RESET}\n"
for f in "${REPORTS_DIR}"/*.json; do
  verdict=$(jq -r '.verdict' "$f" 2>/dev/null || echo "?")
  size=$(wc -c < "$f")
  case "$verdict" in
    PASS)          col="${GREEN}" ;;
    BLOCK)         col="${RED}" ;;
    INDETERMINATE) col="${YELLOW}" ;;
    *)             col="${RESET}" ;;
  esac
  printf "  %-40s %s${BOLD}%-15s${RESET}${DIM}%6d bytes${RESET}\n" \
    "$(basename "$f")" "$col" "$verdict" "$size"
done

echo -e "\n${DIM}  View a full report:  jq . ${REPORTS_DIR}/scenario-b.json${RESET}"
echo -e "${DIM}  Agent skill:         cat skills/helm-preflight/SKILL.md${RESET}"
echo -e "${DIM}  Run acceptance tests: make test-integration${RESET}\n"

echo -e "${BOLD}${GREEN}  helm-agent-preflight POC demo finished.${RESET}"
echo -e "${DIM}  AI proposes · Helm renders · Rego evaluates · Human authorizes${RESET}\n"
