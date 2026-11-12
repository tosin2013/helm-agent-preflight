// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

package conftest_test

import (
	"os/exec"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/tosin2013/helm-agent-preflight/internal/render"
	"github.com/tosin2013/helm-agent-preflight/internal/security"
	conftesteval "github.com/tosin2013/helm-agent-preflight/internal/security/conftest"
)

func conftestAvailable() bool {
	_, err := exec.LookPath("conftest")
	return err == nil
}

func TestEvaluator_Name(t *testing.T) {
	e := conftesteval.New("conftest", "")
	assert.Equal(t, "conftest", e.Name())
}

func TestEvaluator_RBACWildcard_Block(t *testing.T) {
	if !conftestAvailable() {
		t.Skip("conftest binary not in PATH")
	}
	e := conftesteval.New("conftest", "../../../../policies/rego")
	key := render.ResourceKey{
		APIVersion: "rbac.authorization.k8s.io/v1",
		Kind:       "ClusterRole",
		Name:       "admin",
	}
	manifests := map[render.ResourceKey]map[string]interface{}{
		key: {
			"apiVersion": "rbac.authorization.k8s.io/v1",
			"kind":       "ClusterRole",
			"metadata":   map[string]interface{}{"name": "admin"},
			"rules": []interface{}{
				map[string]interface{}{
					"apiGroups": []interface{}{"*"},
					"resources": []interface{}{"*"},
					"verbs":     []interface{}{"*"},
				},
			},
		},
	}
	findings, err := e.Evaluate(security.EvalInput{Candidate: manifests})
	require.NoError(t, err)

	var blocks []security.Finding
	for _, f := range findings {
		if f.VerdictContribution == "BLOCK" {
			blocks = append(blocks, f)
		}
	}
	assert.NotEmpty(t, blocks, "expected BLOCK findings for wildcard RBAC")
	assert.Equal(t, "RBAC-001", blocks[0].RuleID)
}

func TestEvaluator_PrivilegedContainer_Block(t *testing.T) {
	if !conftestAvailable() {
		t.Skip("conftest binary not in PATH")
	}
	e := conftesteval.New("conftest", "../../../../policies/rego")
	key := render.ResourceKey{
		APIVersion: "apps/v1",
		Kind:       "Deployment",
		Namespace:  "default",
		Name:       "worker",
	}
	manifests := map[render.ResourceKey]map[string]interface{}{
		key: {
			"apiVersion": "apps/v1",
			"kind":       "Deployment",
			"metadata":   map[string]interface{}{"name": "worker", "namespace": "default"},
			"spec": map[string]interface{}{
				"template": map[string]interface{}{
					"spec": map[string]interface{}{
						"containers": []interface{}{
							map[string]interface{}{
								"name":  "worker",
								"image": "worker:latest",
								"securityContext": map[string]interface{}{
									"privileged": true,
								},
							},
						},
					},
				},
			},
		},
	}
	findings, err := e.Evaluate(security.EvalInput{Candidate: manifests})
	require.NoError(t, err)

	var work001 []security.Finding
	for _, f := range findings {
		if f.RuleID == "WORK-001" {
			work001 = append(work001, f)
		}
	}
	assert.NotEmpty(t, work001)
	assert.Equal(t, "BLOCK", work001[0].VerdictContribution)
}

func TestEvaluator_PreExisting_Tagged(t *testing.T) {
	if !conftestAvailable() {
		t.Skip("conftest binary not in PATH")
	}
	e := conftesteval.New("conftest", "../../../../policies/rego")
	key := render.ResourceKey{
		APIVersion: "rbac.authorization.k8s.io/v1",
		Kind:       "ClusterRole",
		Name:       "pre-existing-admin",
	}
	obj := map[string]interface{}{
		"apiVersion": "rbac.authorization.k8s.io/v1",
		"kind":       "ClusterRole",
		"metadata":   map[string]interface{}{"name": "pre-existing-admin"},
		"rules": []interface{}{
			map[string]interface{}{
				"resources": []interface{}{"*"},
				"verbs":     []interface{}{"get"},
			},
		},
	}
	input := security.EvalInput{
		Baseline:  map[render.ResourceKey]map[string]interface{}{key: obj},
		Candidate: map[render.ResourceKey]map[string]interface{}{key: obj},
	}
	findings, err := e.Evaluate(input)
	require.NoError(t, err)

	for _, f := range findings {
		if f.RuleID == "RBAC-001" {
			assert.True(t, f.PreExisting, "finding in both baseline and candidate should be pre_existing=true")
		}
	}
}

func TestEvaluator_CleanManifest_NoBlockFindings(t *testing.T) {
	if !conftestAvailable() {
		t.Skip("conftest binary not in PATH")
	}
	e := conftesteval.New("conftest", "../../../../policies/rego")
	key := render.ResourceKey{APIVersion: "apps/v1", Kind: "Deployment", Namespace: "default", Name: "nginx"}
	manifests := map[render.ResourceKey]map[string]interface{}{
		key: {
			"apiVersion": "apps/v1",
			"kind":       "Deployment",
			"metadata":   map[string]interface{}{"name": "nginx", "namespace": "default"},
			"spec": map[string]interface{}{
				"template": map[string]interface{}{
					"spec": map[string]interface{}{
						"containers": []interface{}{
							map[string]interface{}{"name": "nginx", "image": "nginx:1.25"},
						},
					},
				},
			},
		},
	}
	findings, err := e.Evaluate(security.EvalInput{Candidate: manifests})
	require.NoError(t, err)

	for _, f := range findings {
		assert.NotEqual(t, "BLOCK", f.VerdictContribution, "clean manifest should have no BLOCK findings")
	}
}
