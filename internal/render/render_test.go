// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

package render_test

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/tosin2013/helm-agent-preflight/internal/render"
)

func TestParseManifests(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		wantKeys  []render.ResourceKey
		wantCount int
	}{
		{
			name: "single deployment",
			input: `apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: default
spec:
  replicas: 1`,
			wantCount: 1,
			wantKeys: []render.ResourceKey{
				{APIVersion: "apps/v1", Kind: "Deployment", Namespace: "default", Name: "my-app"},
			},
		},
		{
			name: "empty document skipped",
			input: `---
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: cm`,
			wantCount: 1,
		},
		{
			name:      "empty input",
			input:     "",
			wantCount: 0,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := render.ParseManifests(tt.input)
			require.NoError(t, err)
			assert.Len(t, got, tt.wantCount)
			for _, k := range tt.wantKeys {
				_, ok := got[k]
				assert.True(t, ok, "expected key %v", k)
			}
		})
	}
}

func TestScrubSecrets(t *testing.T) {
	input := map[render.ResourceKey]map[string]interface{}{
		{Kind: "Secret", Name: "my-secret"}: {
			"kind": "Secret",
			"data": map[string]interface{}{"password": "c2VjcmV0"},
		},
		{Kind: "ConfigMap", Name: "my-cm"}: {
			"kind": "ConfigMap",
			"data": map[string]interface{}{"key": "value"},
		},
	}
	scrubbed := render.ScrubSecrets(input)

	secretKey := render.ResourceKey{Kind: "Secret", Name: "my-secret"}
	assert.Equal(t, "[REDACTED]", scrubbed[secretKey]["data"], "secret data must be redacted")

	cmKey := render.ResourceKey{Kind: "ConfigMap", Name: "my-cm"}
	assert.Equal(t, map[string]interface{}{"key": "value"}, scrubbed[cmKey]["data"], "configmap data must pass through")
}
