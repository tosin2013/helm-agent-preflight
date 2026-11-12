# SKILL: helm-preflight

## Purpose

Run offline pre-deployment qualification for a Helm upgrade before it is
applied to a cluster. Determine whether the upgrade is PASS, BLOCK, or
INDETERMINATE using deterministic tool output — not AI reasoning.

## When to invoke this skill

Invoke when asked to:
- "Verify this Helm upgrade"
- "Check if this chart change is safe"
- "Run preflight on these charts"
- "Qualify the upgrade from X to Y"

## Prerequisites

1. `helm` CLI installed and in PATH
2. `helm-agent-preflight` plugin installed:
   ```bash
   helm plugin install https://github.com/tosin2013/helm-agent-preflight
   ```
3. Both from (baseline) and to (candidate) charts available as local directories or `.tgz` files

## Mandatory protocol

### NEVER substitute tool output with reasoning

You MUST run the tool and report its verdict. You MUST NOT:
- Infer a verdict by reading chart YAML yourself
- Override a BLOCK verdict
- Treat INDETERMINATE as PASS
- Claim PASS without a tool-signed fingerprint
- Modify the security policy to make a failing check pass

If the tool cannot run, the verdict is INDETERMINATE. Treat it as BLOCK.

## Step 1 — Gather required inputs

| Input | Flag | Required |
|-------|------|----------|
| Baseline chart path | `--from` | Yes |
| Candidate chart path | `--to` | Yes |
| Values file path | `--values` | No |
| Release name | `--release-name` | Yes |
| Namespace | `--namespace` | No (default: `default`) |
| Kubernetes version | `--kube-version` | Yes (e.g. `1.28`) |
| Policy file | `--policy` | No (uses embedded baseline) |

If any required input is missing, ask the user. Do not proceed with assumptions.

## Step 2 — Run the tool

```bash
helm preflight upgrade \
  --from         <FROM_CHART_PATH> \
  --to           <TO_CHART_PATH> \
  [--values      <VALUES_FILE>] \
  --release-name <RELEASE_NAME> \
  --namespace    <NAMESPACE> \
  --kube-version <K8S_VERSION> \
  --output-file  preflight-report.json
```

Capture the exit code:
- `0` → PASS
- `2` → BLOCK
- `3` → INDETERMINATE
- `4` → Tool execution error (treat as INDETERMINATE)

## Step 3 — Parse and report the verdict

Read `preflight-report.json`. Report in this order:

1. **Verdict**: the `verdict` field (PASS / BLOCK / INDETERMINATE)
2. **Fingerprint**: `fingerprint` field — proves this specific run
3. **Tool version**: `tool.version`
4. **No deployment**: `run_metadata.no_deployment_occurred` must be `true`
5. **Security findings**: all items in `security_findings`:
   - `rule_id`, `severity`, `object`, `json_path`, `message`, `pre_existing`
6. **Diff summary**: added/modified/removed resource counts
7. **Evidence**: `evidence.completeness` and any `limitations`
8. **Rendering stability**: `rendering.stability_confirmed`

## Step 4 — Act on the verdict

| Verdict | Action |
|---------|--------|
| PASS | Upgrade may proceed. Include fingerprint in deployment record. |
| BLOCK | Do NOT proceed. Report all findings to the user. Propose the smallest fix. |
| INDETERMINATE | Do NOT proceed. Treat as BLOCK until inputs can be verified. |

## Proposing remediation

For BLOCK findings, propose the minimal change to fix the violation:
- RBAC-001/002: Replace wildcard `*` with explicit resource/verb lists
- WORK-001: Set `securityContext.privileged: false` or remove the field
- WORK-002/003/004: Remove `hostNetwork`/`hostPID`/`hostIPC: true`
- WORK-005: Use emptyDir or PVC instead of hostPath
- WORK-006: Set `allowPrivilegeEscalation: false`
- HOOK-001: Add `helm.sh/hook-delete-policy: hook-succeeded`

After proposing a fix, re-run preflight against the modified chart and report
the new verdict. Human authorization is required before modifying project files.

## Anti-patterns (forbidden)

- Do NOT run `helm upgrade` before obtaining a PASS verdict
- Do NOT tell the user the charts "look safe" without running the tool
- Do NOT skip security findings in your report
- Do NOT proceed when `evidence.completeness` is `"PARTIAL"`
- Do NOT modify the policy file solely to suppress a finding

## Example output summary

**PASS:**
```
Preflight verdict: PASS
Fingerprint: a3f9c1b8...
Tool: helm-agent-preflight v0.1.0

Diff: 1 modified, 0 added, 0 removed
Security findings: none
Evidence: COMPLETE — rendering stable
No deployment occurred: confirmed
```

**BLOCK:**
```
Preflight verdict: BLOCK — upgrade must not proceed

Findings:
  [CRITICAL] RBAC-001 (new): ClusterRole/my-release-reader
    Path: $.rules[0].resources[0]
    Wildcard (*) in RBAC resources grants access to all resource types

  [CRITICAL] RBAC-002 (new): ClusterRole/my-release-reader
    Path: $.rules[0].verbs[0]
    Wildcard (*) in RBAC verbs grants all operations

Fingerprint: d4e7a2f1...
No deployment occurred: confirmed
```
