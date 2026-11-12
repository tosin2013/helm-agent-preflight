# SPDX-License-Identifier: Apache-2.0
# Workload security rules — Conftest policy for helm-agent-preflight
# Covers Kubernetes Baseline Pod Security Standard (subset)
#
# Message format (pipe-delimited, 7 fields):
#   RULE_ID|SEVERITY|KIND|NAMESPACE|NAME|JSON_PATH|description
package preflight

# --- pod spec helpers --------------------------------------------------------

pod_spec(obj) = spec {
	obj.kind == "Pod"
	spec := obj.spec
}

pod_spec(obj) = spec {
	obj.kind == "Deployment"
	spec := obj.spec.template.spec
}

pod_spec(obj) = spec {
	obj.kind == "DaemonSet"
	spec := obj.spec.template.spec
}

pod_spec(obj) = spec {
	obj.kind == "StatefulSet"
	spec := obj.spec.template.spec
}

pod_spec(obj) = spec {
	obj.kind == "ReplicaSet"
	spec := obj.spec.template.spec
}

pod_spec(obj) = spec {
	obj.kind == "Job"
	spec := obj.spec.template.spec
}

pod_spec(obj) = spec {
	obj.kind == "CronJob"
	spec := obj.spec.jobTemplate.spec.template.spec
}

ns(obj) = n {
	n := object.get(obj.metadata, "namespace", "")
}

# all_containers yields {index, container} for containers + initContainers + ephemeralContainers
all_containers[{"idx": i, "prefix": "containers", "c": c}] {
	spec := pod_spec(input)
	c := spec.containers[i]
}

all_containers[{"idx": i, "prefix": "initContainers", "c": c}] {
	spec := pod_spec(input)
	c := spec.initContainers[i]
}

all_containers[{"idx": i, "prefix": "ephemeralContainers", "c": c}] {
	spec := pod_spec(input)
	c := spec.ephemeralContainers[i]
}

# WORK-001: privileged containers --------------------------------------------

deny[msg] {
	pod_spec(input)
	entry := all_containers[_]
	entry.c.securityContext.privileged == true
	msg := sprintf(
		"WORK-001|CRITICAL|%s|%s|%s|$.spec.%s[%d].securityContext.privileged|container '%s' runs privileged (securityContext.privileged=true)",
		[input.kind, ns(input), input.metadata.name, entry.prefix, entry.idx, entry.c.name],
	)
}

# WORK-002: hostNetwork ------------------------------------------------------

deny[msg] {
	spec := pod_spec(input)
	spec.hostNetwork == true
	msg := sprintf(
		"WORK-002|HIGH|%s|%s|%s|$.spec.hostNetwork|pod uses host network namespace (hostNetwork=true)",
		[input.kind, ns(input), input.metadata.name],
	)
}

# WORK-003: hostPID ----------------------------------------------------------

deny[msg] {
	spec := pod_spec(input)
	spec.hostPID == true
	msg := sprintf(
		"WORK-003|HIGH|%s|%s|%s|$.spec.hostPID|pod shares host PID namespace (hostPID=true)",
		[input.kind, ns(input), input.metadata.name],
	)
}

# WORK-004: hostIPC ----------------------------------------------------------

deny[msg] {
	spec := pod_spec(input)
	spec.hostIPC == true
	msg := sprintf(
		"WORK-004|HIGH|%s|%s|%s|$.spec.hostIPC|pod shares host IPC namespace (hostIPC=true)",
		[input.kind, ns(input), input.metadata.name],
	)
}

# WORK-005: hostPath volumes -------------------------------------------------

deny[msg] {
	spec := pod_spec(input)
	vol := spec.volumes[i]
	vol.hostPath
	msg := sprintf(
		"WORK-005|HIGH|%s|%s|%s|$.spec.volumes[%d].hostPath|volume mounts a host filesystem path (hostPath)",
		[input.kind, ns(input), input.metadata.name, i],
	)
}

# WORK-006: allowPrivilegeEscalation ----------------------------------------

deny[msg] {
	pod_spec(input)
	entry := all_containers[_]
	entry.c.securityContext.allowPrivilegeEscalation == true
	msg := sprintf(
		"WORK-006|HIGH|%s|%s|%s|$.spec.%s[%d].securityContext.allowPrivilegeEscalation|container '%s' allows privilege escalation",
		[input.kind, ns(input), input.metadata.name, entry.prefix, entry.idx, entry.c.name],
	)
}
