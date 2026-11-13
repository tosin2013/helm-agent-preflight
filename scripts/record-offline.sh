#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
# Offline scenarios script for asciinema recording. Run from project root.
# Looks like a real terminal session — shows typed command then filtered output.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
export PATH="${HOME}/.local/bin:/home/vpcuser/bin:/usr/local/bin:$PATH"
set +e

# show_cmd — prints a prompt+command line, then runs it and pipes output through jq
show_cmd() {
  local comment="$1"; shift
  echo ""
  echo "# ${comment}"
  echo -n "$ "
  echo "$@" | sed 's/ \\/\n    /g'   # pretty-print the command
  sleep 1
  eval "$@" 2>/dev/null   # suppress helm's non-zero exit message; JSON goes to stdout
  echo ""
}

sleep 2

show_cmd "Safe upgrade — only the nginx image tag changed" \
  "helm preflight upgrade \
  --from $ROOT_DIR/examples/safe-upgrade/baseline \
  --to   $ROOT_DIR/examples/safe-upgrade/candidate \
  --release-name webapp --namespace staging --kube-version 1.37 \
  | jq '{verdict, diff: {added:.diff_summary.added_count, modified:.diff_summary.modified_count}, findings:(.security_findings|length)}'"

sleep 10

show_cmd "Candidate adds a ClusterRole — does it escalate permissions?" \
  "helm preflight upgrade \
  --from $ROOT_DIR/examples/rbac-escalation/baseline \
  --to   $ROOT_DIR/examples/rbac-escalation/candidate \
  --release-name webapp --namespace staging --kube-version 1.37 \
  | jq '{verdict, findings:[.security_findings[]|{rule:.rule_id,object:(.object.kind+\"/\"+.object.name),issue:.message}]}'"

sleep 10

show_cmd "Candidate changes the container security context" \
  "helm preflight upgrade \
  --from $ROOT_DIR/examples/privileged-container/baseline \
  --to   $ROOT_DIR/examples/privileged-container/candidate \
  --release-name webapp --namespace staging --kube-version 1.37 \
  | jq '{verdict, findings:[.security_findings[]|{rule:.rule_id,severity,issue:.message,new:(if .pre_existing then \"pre-existing\" else \"newly introduced\" end)}]}'"

sleep 10
echo "# Same inputs always produce the same fingerprint — deterministic by design."
sleep 10
