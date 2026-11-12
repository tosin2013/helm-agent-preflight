// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

package diff_test

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/tosin2013/helm-agent-preflight/internal/diff"
	"github.com/tosin2013/helm-agent-preflight/internal/render"
)

func TestManifests_Added(t *testing.T) {
	baseline := map[render.ResourceKey]map[string]interface{}{}
	candidate := map[render.ResourceKey]map[string]interface{}{
		{Kind: "Deployment", Name: "new"}: {"kind": "Deployment"},
	}
	result := diff.Manifests(baseline, candidate)
	assert.Len(t, result.Added, 1)
	assert.Empty(t, result.Removed)
	assert.Empty(t, result.Modified)
}

func TestManifests_Removed(t *testing.T) {
	baseline := map[render.ResourceKey]map[string]interface{}{
		{Kind: "Deployment", Name: "old"}: {"kind": "Deployment"},
	}
	candidate := map[render.ResourceKey]map[string]interface{}{}
	result := diff.Manifests(baseline, candidate)
	assert.Empty(t, result.Added)
	assert.Len(t, result.Removed, 1)
}

func TestManifests_Modified(t *testing.T) {
	key := render.ResourceKey{Kind: "Deployment", Name: "app"}
	baseline := map[render.ResourceKey]map[string]interface{}{
		key: {"image": "nginx:1.24"},
	}
	candidate := map[render.ResourceKey]map[string]interface{}{
		key: {"image": "nginx:1.25"},
	}
	result := diff.Manifests(baseline, candidate)
	assert.Empty(t, result.Added)
	assert.Empty(t, result.Removed)
	assert.Len(t, result.Modified, 1)
	assert.Equal(t, "nginx:1.24", result.Modified[0].Changes[0].Baseline)
	assert.Equal(t, "nginx:1.25", result.Modified[0].Changes[0].Candidate)
}

func TestManifests_Unchanged(t *testing.T) {
	key := render.ResourceKey{Kind: "ConfigMap", Name: "cm"}
	obj := map[string]interface{}{"key": "value"}
	baseline := map[render.ResourceKey]map[string]interface{}{key: obj}
	candidate := map[render.ResourceKey]map[string]interface{}{key: obj}
	result := diff.Manifests(baseline, candidate)
	assert.Empty(t, result.Added)
	assert.Empty(t, result.Removed)
	assert.Empty(t, result.Modified)
}
