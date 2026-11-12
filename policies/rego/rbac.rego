# SPDX-License-Identifier: Apache-2.0
# RBAC escalation rules — Conftest policy for helm-agent-preflight
#
# Message format (pipe-delimited, 7 fields):
#   RULE_ID|SEVERITY|KIND|NAMESPACE|NAME|JSON_PATH|description
# Cluster-scoped resources have an empty NAMESPACE field.
package preflight

# RBAC-001: wildcard resources -----------------------------------------------

deny[msg] {
	input.kind == "ClusterRole"
	some i
	input.rules[i].resources[_] == "*"
	msg := sprintf(
		"RBAC-001|CRITICAL|ClusterRole||%s|$.rules[%d].resources|wildcard (*) in resources grants access to all resource types",
		[input.metadata.name, i],
	)
}

deny[msg] {
	input.kind == "Role"
	some i
	input.rules[i].resources[_] == "*"
	msg := sprintf(
		"RBAC-001|CRITICAL|Role|%s|%s|$.rules[%d].resources|wildcard (*) in resources grants access to all resource types",
		[object.get(input.metadata, "namespace", ""), input.metadata.name, i],
	)
}

# RBAC-002: wildcard verbs ----------------------------------------------------

deny[msg] {
	input.kind == "ClusterRole"
	some i
	input.rules[i].verbs[_] == "*"
	msg := sprintf(
		"RBAC-002|CRITICAL|ClusterRole||%s|$.rules[%d].verbs|wildcard (*) in verbs grants all operations",
		[input.metadata.name, i],
	)
}

deny[msg] {
	input.kind == "Role"
	some i
	input.rules[i].verbs[_] == "*"
	msg := sprintf(
		"RBAC-002|CRITICAL|Role|%s|%s|$.rules[%d].verbs|wildcard (*) in verbs grants all operations",
		[object.get(input.metadata, "namespace", ""), input.metadata.name, i],
	)
}
