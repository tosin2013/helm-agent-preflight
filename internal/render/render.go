// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

// Package render shells out to `helm template` and parses the YAML output.
// No cluster connection occurs.
package render

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"sigs.k8s.io/yaml"
)

// Options controls a single helm template invocation.
type Options struct {
	HelmBin     string
	ChartPath   string
	ValuesFile  string
	ReleaseName string
	Namespace   string
	KubeVersion string
	Timeout     time.Duration
}

// ResourceKey uniquely identifies a Kubernetes resource.
type ResourceKey struct {
	APIVersion string `json:"api_version"`
	Kind       string `json:"kind"`
	Namespace  string `json:"namespace"`
	Name       string `json:"name"`
}

func (k ResourceKey) String() string {
	ns := k.Namespace
	if ns == "" {
		ns = "(cluster-scoped)"
	}
	return fmt.Sprintf("%s/%s %s/%s", k.APIVersion, k.Kind, ns, k.Name)
}

// Result holds parsed rendered output from one chart.
type Result struct {
	Raw          string
	Objects      map[ResourceKey]map[string]interface{}
	Scrubbed     map[ResourceKey]map[string]interface{}
	HelmExitCode int
}

// Chart runs `helm template` and returns a Result.
func Chart(opts Options) (*Result, error) {
	if opts.Timeout == 0 {
		opts.Timeout = 30 * time.Second
	}
	args := []string{
		"template",
		opts.ReleaseName,
		opts.ChartPath,
		"--namespace", opts.Namespace,
		"--kube-version", opts.KubeVersion,
		"--include-crds",
	}
	if opts.ValuesFile != "" {
		args = append(args, "--values", opts.ValuesFile)
	}

	var stdout, stderr bytes.Buffer
	cmd := exec.Command(opts.HelmBin, args...)
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	cmd.Env = filterEnv()

	done := make(chan error, 1)
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("start helm template: %w", err)
	}
	go func() { done <- cmd.Wait() }()

	select {
	case err := <-done:
		if err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				return nil, fmt.Errorf("helm template exited %d: %s", exitErr.ExitCode(), strings.TrimSpace(stderr.String()))
			}
			return nil, fmt.Errorf("helm template: %w", err)
		}
	case <-time.After(opts.Timeout):
		_ = cmd.Process.Kill()
		return nil, fmt.Errorf("helm template timed out after %s", opts.Timeout)
	}

	objects, err := ParseManifests(stdout.String())
	if err != nil {
		return nil, fmt.Errorf("parse manifests: %w", err)
	}
	scrubbed := ScrubSecrets(objects)

	return &Result{
		Raw:      stdout.String(),
		Objects:  objects,
		Scrubbed: scrubbed,
	}, nil
}

// StabilityCheck runs Chart twice and returns an error if the normalized outputs differ.
func StabilityCheck(opts Options) error {
	r1, err := Chart(opts)
	if err != nil {
		return fmt.Errorf("first render: %w", err)
	}
	r2, err := Chart(opts)
	if err != nil {
		return fmt.Errorf("second render: %w", err)
	}
	j1, _ := json.Marshal(normalizeKeys(r1.Scrubbed))
	j2, _ := json.Marshal(normalizeKeys(r2.Scrubbed))
	if string(j1) != string(j2) {
		return fmt.Errorf("chart rendering is nondeterministic: outputs differ between two identical runs")
	}
	return nil
}

// ParseManifests splits multi-document YAML and unmarshals each document.
func ParseManifests(raw string) (map[ResourceKey]map[string]interface{}, error) {
	result := make(map[ResourceKey]map[string]interface{})
	docs := strings.Split(raw, "\n---")
	for _, doc := range docs {
		doc = strings.TrimSpace(doc)
		if doc == "" || strings.HasPrefix(doc, "#") {
			continue
		}
		var obj map[string]interface{}
		if err := yaml.Unmarshal([]byte(doc), &obj); err != nil {
			return nil, fmt.Errorf("unmarshal manifest: %w", err)
		}
		if obj == nil {
			continue
		}
		key := extractKey(obj)
		result[key] = obj
	}
	return result, nil
}

// ScrubSecrets returns a new map with Secret .data and .stringData replaced by "[REDACTED]".
func ScrubSecrets(in map[ResourceKey]map[string]interface{}) map[ResourceKey]map[string]interface{} {
	out := make(map[ResourceKey]map[string]interface{}, len(in))
	for k, v := range in {
		if k.Kind == "Secret" {
			cp := shallowCopy(v)
			cp["data"] = "[REDACTED]"
			cp["stringData"] = "[REDACTED]"
			out[k] = cp
		} else {
			out[k] = v
		}
	}
	return out
}

func extractKey(obj map[string]interface{}) ResourceKey {
	apiVersion, _ := obj["apiVersion"].(string)
	kind, _ := obj["kind"].(string)
	var ns, name string
	if meta, ok := obj["metadata"].(map[string]interface{}); ok {
		name, _ = meta["name"].(string)
		ns, _ = meta["namespace"].(string)
	}
	return ResourceKey{APIVersion: apiVersion, Kind: kind, Namespace: ns, Name: name}
}

func shallowCopy(m map[string]interface{}) map[string]interface{} {
	out := make(map[string]interface{}, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}

func normalizeKeys(m map[ResourceKey]map[string]interface{}) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k.String())
	}
	return keys
}

func filterEnv() []string {
	return nil
}
