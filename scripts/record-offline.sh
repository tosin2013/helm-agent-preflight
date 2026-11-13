#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
# Offline scenarios script for asciinema recording. Run from project root.
# Uses `helm preflight upgrade` via the installed plugin — same as a real user.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
export PATH="${HOME}/.local/bin:/home/vpcuser/bin:/usr/local/bin:$PATH"
set +e

echo "helm preflight upgrade — offline Helm upgrade qualification"
echo "No cluster access · No network · No deployment"
echo ""
sleep 3

# ─── Scenario A: safe image-tag upgrade ──────────────────────────────────────
echo "# Checking if the nginx image upgrade is safe..."
sleep 1

helm preflight upgrade \
  --from "$ROOT_DIR/examples/safe-upgrade/baseline" \
  --to   "$ROOT_DIR/examples/safe-upgrade/candidate" \
  --release-name webapp \
  --namespace   staging \
  --kube-version 1.37

sleep 10

# ─── Scenario B: RBAC escalation ─────────────────────────────────────────────
echo ""
echo "# Checking candidate chart that adds a ClusterRole..."
sleep 1

helm preflight upgrade \
  --from "$ROOT_DIR/examples/rbac-escalation/baseline" \
  --to   "$ROOT_DIR/examples/rbac-escalation/candidate" \
  --release-name webapp \
  --namespace   staging \
  --kube-version 1.37

sleep 10

# ─── Scenario C: privileged container ────────────────────────────────────────
echo ""
echo "# Checking candidate chart that changes the container security context..."
sleep 1

helm preflight upgrade \
  --from "$ROOT_DIR/examples/privileged-container/baseline" \
  --to   "$ROOT_DIR/examples/privileged-container/candidate" \
  --release-name webapp \
  --namespace   staging \
  --kube-version 1.37

sleep 5
echo ""
echo "# Same inputs always produce the same fingerprint."
sleep 3
