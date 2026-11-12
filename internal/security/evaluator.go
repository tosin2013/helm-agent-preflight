// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

// Package security defines the Evaluator interface and shared types for
// running security policy checks against rendered Kubernetes manifests.
//
// Two evaluators are provided:
//   - conftest (MVP, Phase 0): uses Conftest + Rego policies
//   - kyverno  (Phase 1):      uses Kyverno CLI + ClusterPolicy YAML
package security

import (
	"github.com/tosin2013/helm-agent-preflight/internal/render"
)

// Verdict contribution constants.
const (
	ContributionBlock = "BLOCK"
	ContributionWarn  = "WARN"
)

// Finding is a single security policy violation.
type Finding struct {
	RuleID              string             `json:"rule_id"`
	Severity            string             `json:"severity"`
	Object              render.ResourceKey `json:"object"`
	JSONPath            string             `json:"json_path,omitempty"`
	Message             string             `json:"message"`
	VerdictContribution string             `json:"verdict_contribution"`
	PreExisting         bool               `json:"pre_existing"`
	Evaluator           string             `json:"evaluator"`
}

// EvalInput carries the data needed for a security evaluation run.
type EvalInput struct {
	// Candidate are the manifests to evaluate (required).
	Candidate map[render.ResourceKey]map[string]interface{}
	// Baseline, if non-nil, is used to tag pre-existing violations.
	// A finding present in both Baseline and Candidate is marked PreExisting=true.
	Baseline map[render.ResourceKey]map[string]interface{}
	// PolicyDir overrides the default policy location.
	// When empty, the evaluator uses its built-in default.
	PolicyDir string
}

// Evaluator runs security policy checks against rendered Kubernetes manifests.
type Evaluator interface {
	// Name returns the evaluator's identifier (e.g., "conftest", "kyverno").
	Name() string
	// Evaluate checks candidate manifests, optionally comparing to baseline
	// to detect pre-existing violations. Returns sorted findings.
	Evaluate(input EvalInput) ([]Finding, error)
}
