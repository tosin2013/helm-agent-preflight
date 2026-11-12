// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

// Package conftest implements a security.Evaluator backed by the Conftest CLI
// and Rego policies (OPA). It calls `conftest test --output json` as a
// subprocess and parses the structured results.
package conftest

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"sigs.k8s.io/yaml"

	"github.com/tosin2013/helm-agent-preflight/internal/render"
	"github.com/tosin2013/helm-agent-preflight/internal/security"
)

const evaluatorName = "conftest"

// Evaluator calls conftest to evaluate Rego policies against rendered manifests.
type Evaluator struct {
	// BinPath is the path to the conftest binary (default: "conftest").
	BinPath string
	// DefaultPolicyDir is used when EvalInput.PolicyDir is empty.
	DefaultPolicyDir string
	// Timeout for each conftest invocation (default: 60s).
	Timeout time.Duration
}

// New creates an Evaluator with sensible defaults.
// defaultPolicyDir may be empty; callers should set it to $HELM_PLUGIN_DIR/policies/rego.
func New(binPath, defaultPolicyDir string) *Evaluator {
	if binPath == "" {
		binPath = "conftest"
	}
	return &Evaluator{
		BinPath:          binPath,
		DefaultPolicyDir: defaultPolicyDir,
		Timeout:          60 * time.Second,
	}
}

func (e *Evaluator) Name() string { return evaluatorName }

// Evaluate runs Rego policies against candidate manifests.
// If input.Baseline is non-nil, findings also present in the baseline are
// marked PreExisting=true (SEC-007 baseline preservation).
func (e *Evaluator) Evaluate(input security.EvalInput) ([]security.Finding, error) {
	policyDir := input.PolicyDir
	if policyDir == "" {
		policyDir = e.defaultPolicyDir()
	}
	if policyDir == "" {
		return nil, fmt.Errorf("no Rego policy directory found; set --policy-dir or install plugin via 'helm plugin install'")
	}
	if _, err := os.Stat(policyDir); err != nil {
		return nil, fmt.Errorf("policy directory %q: %w", policyDir, err)
	}

	// Evaluate candidate manifests.
	candidateFindings, err := e.runConftest(input.Candidate, policyDir)
	if err != nil {
		return nil, fmt.Errorf("evaluate candidate: %w", err)
	}

	// Evaluate baseline manifests to detect pre-existing violations.
	baselineSet := map[string]bool{}
	if len(input.Baseline) > 0 {
		baselineFindings, err := e.runConftest(input.Baseline, policyDir)
		if err != nil {
			return nil, fmt.Errorf("evaluate baseline: %w", err)
		}
		for _, f := range baselineFindings {
			baselineSet[findingKey(f)] = true
		}
	}

	for i := range candidateFindings {
		candidateFindings[i].PreExisting = baselineSet[findingKey(candidateFindings[i])]
	}

	sort.Slice(candidateFindings, func(i, j int) bool {
		if candidateFindings[i].RuleID != candidateFindings[j].RuleID {
			return candidateFindings[i].RuleID < candidateFindings[j].RuleID
		}
		return candidateFindings[i].Object.String() < candidateFindings[j].Object.String()
	})

	return candidateFindings, nil
}

// runConftest writes manifests to a temp file, runs conftest, and parses results.
func (e *Evaluator) runConftest(manifests map[render.ResourceKey]map[string]interface{}, policyDir string) ([]security.Finding, error) {
	if len(manifests) == 0 {
		return nil, nil
	}

	tmpFile, err := writeManifests(manifests)
	if err != nil {
		return nil, fmt.Errorf("write temp manifests: %w", err)
	}
	defer os.Remove(tmpFile)

	output, err := e.execConftest(policyDir, tmpFile)
	if err != nil {
		return nil, err
	}

	return parseOutput(output)
}

// execConftest runs `conftest test --policy <dir> --output json --all-namespaces <file>`.
func (e *Evaluator) execConftest(policyDir, manifestFile string) ([]byte, error) {
	args := []string{
		"test",
		"--policy", policyDir,
		"--output", "json",
		"--all-namespaces",
		"--no-color",
		manifestFile,
	}

	var stdout, stderr bytes.Buffer
	cmd := exec.Command(e.BinPath, args...)
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	done := make(chan error, 1)
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("start conftest: %w", err)
	}
	go func() { done <- cmd.Wait() }()

	timeout := e.Timeout
	if timeout == 0 {
		timeout = 60 * time.Second
	}

	select {
	case err := <-done:
		// conftest exits non-zero when there are failures; that's expected.
		// We only fail on actual execution errors (not policy violations).
		if err != nil {
			if _, ok := err.(*exec.ExitError); !ok {
				return nil, fmt.Errorf("conftest exec: %w", err)
			}
		}
	case <-time.After(timeout):
		_ = cmd.Process.Kill()
		return nil, fmt.Errorf("conftest timed out after %s", timeout)
	}

	if stdout.Len() == 0 {
		if stderr.Len() > 0 {
			return nil, fmt.Errorf("conftest produced no output: %s", strings.TrimSpace(stderr.String()))
		}
		return []byte("[]"), nil
	}

	return stdout.Bytes(), nil
}

// writeManifests serializes all manifests to a single multi-document YAML temp file.
func writeManifests(manifests map[render.ResourceKey]map[string]interface{}) (string, error) {
	f, err := os.CreateTemp("", "preflight-manifests-*.yaml")
	if err != nil {
		return "", err
	}
	defer f.Close()

	// Sort keys for determinism.
	keys := make([]render.ResourceKey, 0, len(manifests))
	for k := range manifests {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return keys[i].String() < keys[j].String() })

	for i, k := range keys {
		if i > 0 {
			if _, err := f.WriteString("---\n"); err != nil {
				return "", err
			}
		}
		data, err := yaml.Marshal(manifests[k])
		if err != nil {
			return "", fmt.Errorf("marshal manifest %v: %w", k, err)
		}
		if _, err := f.Write(data); err != nil {
			return "", err
		}
	}
	return f.Name(), nil
}

// conftestResult is the JSON structure conftest emits per file.
type conftestResult struct {
	Filename string              `json:"filename"`
	Failures []conftestViolation `json:"failures"`
	Warnings []conftestViolation `json:"warnings"`
	Successes []interface{}      `json:"successes"`
}

type conftestViolation struct {
	Message  string `json:"msg"`
}

// parseOutput parses conftest JSON output into security.Finding slice.
func parseOutput(data []byte) ([]security.Finding, error) {
	var results []conftestResult
	if err := json.Unmarshal(data, &results); err != nil {
		return nil, fmt.Errorf("parse conftest output: %w\noutput: %s", err, string(data))
	}

	var findings []security.Finding
	for _, result := range results {
		for _, v := range result.Failures {
			f, err := parseViolation(v.Message, security.ContributionBlock)
			if err != nil {
				// Non-parseable messages become raw findings.
				findings = append(findings, security.Finding{
					RuleID:              "UNKNOWN",
					Severity:            "HIGH",
					Message:             v.Message,
					VerdictContribution: security.ContributionBlock,
					Evaluator:           evaluatorName,
				})
				continue
			}
			findings = append(findings, f)
		}
		for _, v := range result.Warnings {
			f, err := parseViolation(v.Message, security.ContributionWarn)
			if err != nil {
				findings = append(findings, security.Finding{
					RuleID:              "UNKNOWN",
					Severity:            "MEDIUM",
					Message:             v.Message,
					VerdictContribution: security.ContributionWarn,
					Evaluator:           evaluatorName,
				})
				continue
			}
			findings = append(findings, f)
		}
	}
	return findings, nil
}

// parseViolation parses the pipe-delimited message format produced by the Rego policies:
//
//	RULE_ID|SEVERITY|KIND|NAMESPACE|NAME|JSON_PATH|description
func parseViolation(msg, contribution string) (security.Finding, error) {
	parts := strings.SplitN(msg, "|", 7)
	if len(parts) != 7 {
		return security.Finding{}, fmt.Errorf("unexpected message format (want 7 pipe-delimited fields): %q", msg)
	}
	return security.Finding{
		RuleID:   parts[0],
		Severity: parts[1],
		Object: render.ResourceKey{
			Kind:      parts[2],
			Namespace: parts[3],
			Name:      parts[4],
		},
		JSONPath:            parts[5],
		Message:             parts[6],
		VerdictContribution: contribution,
		Evaluator:           evaluatorName,
	}, nil
}

func findingKey(f security.Finding) string {
	return f.RuleID + "|" + f.Object.String() + "|" + f.JSONPath
}

// defaultPolicyDir resolves the policy directory when none is specified.
// Priority: $HELM_PLUGIN_DIR/policies/rego → binary-relative ../policies/rego
func (e *Evaluator) defaultPolicyDir() string {
	if e.DefaultPolicyDir != "" {
		return e.DefaultPolicyDir
	}
	if pluginDir := os.Getenv("HELM_PLUGIN_DIR"); pluginDir != "" {
		return filepath.Join(pluginDir, "policies", "rego")
	}
	// Development fallback: look relative to the executable.
	if exe, err := os.Executable(); err == nil {
		candidate := filepath.Join(filepath.Dir(exe), "..", "policies", "rego")
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	return ""
}
