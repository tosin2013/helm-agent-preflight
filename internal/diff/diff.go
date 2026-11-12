// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

// Package diff computes structural differences between two sets of rendered manifests.
// All inputs must already have secrets scrubbed.
package diff

import (
	"encoding/json"
	"fmt"
	"sort"

	"github.com/tosin2013/helm-agent-preflight/internal/render"
)

// Result summarizes the differences between baseline and candidate manifest sets.
type Result struct {
	Added    []render.ResourceKey `json:"added"`
	Removed  []render.ResourceKey `json:"removed"`
	Modified []ModifiedResource   `json:"modified"`
}

// ModifiedResource is a resource whose rendered YAML changed.
type ModifiedResource struct {
	Key     render.ResourceKey `json:"key"`
	Changes []FieldChange      `json:"changes"`
}

// FieldChange is one changed field within a resource.
type FieldChange struct {
	Path      string      `json:"path"`
	Baseline  interface{} `json:"baseline"`
	Candidate interface{} `json:"candidate"`
}

// Manifests diffs two manifest maps (baseline, candidate).
// Inputs must be secret-scrubbed before calling.
func Manifests(
	baseline map[render.ResourceKey]map[string]interface{},
	candidate map[render.ResourceKey]map[string]interface{},
) *Result {
	result := &Result{
		Added:    []render.ResourceKey{},
		Removed:  []render.ResourceKey{},
		Modified: []ModifiedResource{},
	}

	for key, cObj := range candidate {
		if bObj, exists := baseline[key]; !exists {
			result.Added = append(result.Added, key)
		} else {
			changes := fieldChanges("$", bObj, cObj)
			if len(changes) > 0 {
				result.Modified = append(result.Modified, ModifiedResource{Key: key, Changes: changes})
			}
		}
	}

	for key := range baseline {
		if _, exists := candidate[key]; !exists {
			result.Removed = append(result.Removed, key)
		}
	}

	sort.Slice(result.Added, func(i, j int) bool { return result.Added[i].String() < result.Added[j].String() })
	sort.Slice(result.Removed, func(i, j int) bool { return result.Removed[i].String() < result.Removed[j].String() })
	sort.Slice(result.Modified, func(i, j int) bool { return result.Modified[i].Key.String() < result.Modified[j].Key.String() })

	return result
}

func fieldChanges(path string, baseline, candidate interface{}) []FieldChange {
	bJSON, _ := json.Marshal(baseline)
	cJSON, _ := json.Marshal(candidate)
	if string(bJSON) == string(cJSON) {
		return nil
	}

	bMap, bIsMap := toStringMap(baseline)
	cMap, cIsMap := toStringMap(candidate)
	if bIsMap && cIsMap {
		var changes []FieldChange
		for _, k := range mergeKeys(bMap, cMap) {
			childPath := fmt.Sprintf("%s.%s", path, k)
			changes = append(changes, fieldChanges(childPath, bMap[k], cMap[k])...)
		}
		return changes
	}
	return []FieldChange{{Path: path, Baseline: baseline, Candidate: candidate}}
}

func toStringMap(v interface{}) (map[string]interface{}, bool) {
	m, ok := v.(map[string]interface{})
	return m, ok
}

func mergeKeys(a, b map[string]interface{}) []string {
	seen := make(map[string]bool)
	var keys []string
	for k := range a {
		seen[k] = true
		keys = append(keys, k)
	}
	for k := range b {
		if !seen[k] {
			keys = append(keys, k)
		}
	}
	sort.Strings(keys)
	return keys
}
