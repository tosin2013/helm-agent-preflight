#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
# Offline scenarios script for asciinema recording. Run from project root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
export PATH="/home/vpcuser/bin:${HOME}/.local/bin:/usr/local/bin:$PATH"
set +e
BOLD='\033[1m'; RED='\033[0;31m'; CYAN='\033[0;36m'; DIM='\033[2m'; YELLOW='\033[1;33m'; RESET='\033[0m'
OS=$(uname -s | tr '[:upper:]' '[:lower:]'); ARCH=$(uname -m); [ "$ARCH" = "x86_64" ] && ARCH="amd64"
BIN="${ROOT_DIR}/bin/preflight-${OS}-${ARCH}"
POLICY="${ROOT_DIR}/policies/rego"
EX="${ROOT_DIR}/examples"

# pause N — prints a visible countdown on separate lines so asciinema
# records each second as a distinct event (not collapsed like \r overwrites)
pause() {
  local n="${1:-10}"
  echo ""
  for i in $(seq "$n" -1 1); do
    echo -e "  ${YELLOW}Next scenario in ${BOLD}${i}s${RESET}${YELLOW}...${RESET}"
    sleep 1
  done
  echo ""
}

echo -e "${BOLD}# helm-agent-preflight — offline Helm upgrade qualification${RESET}"
echo -e "${DIM}# No cluster · No network · No deployment${RESET}"
echo ""
sleep 2

# ─── Scenario A ──────────────────────────────────────────────────────────────
echo -e "${CYAN}${BOLD}─── Scenario A: safe image-tag upgrade (nginx 1.24 → 1.25) ───${RESET}"
sleep 1
"$BIN" upgrade \
  --from "$EX/safe-upgrade/baseline" \
  --to   "$EX/safe-upgrade/candidate" \
  --release-name demo --namespace default --kube-version 1.28 \
  --policy-dir "$POLICY" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(json.dumps({
  'verdict':  d['verdict'],
  'diff':     {'added': d['diff_summary']['added_count'], 'modified': d['diff_summary']['modified_count']},
  'findings': len(d['security_findings'])
}, indent=2))"

pause 10

# ─── Scenario B ──────────────────────────────────────────────────────────────
echo -e "${RED}${BOLD}─── Scenario B: wildcard ClusterRole → BLOCK ─────────────────${RESET}"
sleep 1
"$BIN" upgrade \
  --from "$EX/rbac-escalation/baseline" \
  --to   "$EX/rbac-escalation/candidate" \
  --release-name demo --namespace default --kube-version 1.28 \
  --policy-dir "$POLICY" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(json.dumps({
  'verdict':  d['verdict'],
  'findings': [
    {'rule': f['rule_id'], 'severity': f['severity'],
     'object': f['object']['kind'] + '/' + f['object']['name'],
     'msg': f['message']}
    for f in d['security_findings']
  ]
}, indent=2))"

pause 10

# ─── Scenario C ──────────────────────────────────────────────────────────────
echo -e "${RED}${BOLD}─── Scenario C: privileged container → BLOCK ─────────────────${RESET}"
sleep 1
"$BIN" upgrade \
  --from "$EX/privileged-container/baseline" \
  --to   "$EX/privileged-container/candidate" \
  --release-name demo --namespace default --kube-version 1.28 \
  --policy-dir "$POLICY" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
f = d['security_findings'][0]
print(json.dumps({
  'verdict': d['verdict'],
  'finding': {
    'rule':             f['rule_id'],
    'severity':         f['severity'],
    'msg':              f['message'],
    'newly_introduced': not f['pre_existing']
  }
}, indent=2))"

echo ""
sleep 10
echo -e "${DIM}# Fingerprints are deterministic — same frozen inputs → same verdict, every time${RESET}"
sleep 5
