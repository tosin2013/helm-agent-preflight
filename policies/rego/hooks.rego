# SPDX-License-Identifier: Apache-2.0
# Helm hook side-effect rules — Conftest policy for helm-agent-preflight
# OPA v1 syntax (required by OPA 1.x / conftest 0.71+)
#
# Message format (pipe-delimited, 7 fields):
#   RULE_ID|SEVERITY|KIND|NAMESPACE|NAME|JSON_PATH|description
package preflight

ns(obj) = n if {
	n := object.get(obj.metadata, "namespace", "")
}

# HOOK-001: upgrade hooks without hook-delete-policy -------------------------

warn contains msg if {
	hook := object.get(object.get(input, "metadata", {}), "annotations", {})["helm.sh/hook"]
	contains_upgrade_hook(hook)
	not object.get(object.get(input, "metadata", {}), "annotations", {})["helm.sh/hook-delete-policy"]
	msg := sprintf(
		"HOOK-001|MEDIUM|%s|%s|%s|$.metadata.annotations['helm.sh/hook-delete-policy']|upgrade hook lacks helm.sh/hook-delete-policy; side-effect resources may persist",
		[input.kind, ns(input), input.metadata.name],
	)
}

contains_upgrade_hook(annotation) if {
	parts := split(annotation, ",")
	part := parts[_]
	trimmed := trim(part, " ")
	trimmed == "pre-upgrade"
}

contains_upgrade_hook(annotation) if {
	parts := split(annotation, ",")
	part := parts[_]
	trimmed := trim(part, " ")
	trimmed == "post-upgrade"
}
