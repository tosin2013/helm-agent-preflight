// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

// Package kyverno will implement a security.Evaluator backed by the Kyverno CLI
// and Kyverno ClusterPolicy YAML (Phase 1 roadmap item).
//
// See policies/kyverno/ for the planned policy format.
package kyverno

import (
	"fmt"

	"github.com/tosin2013/helm-agent-preflight/internal/security"
)

// Evaluator is a Phase 1 placeholder. It is not yet implemented.
type Evaluator struct {
	BinPath          string
	DefaultPolicyDir string
}

// New creates a KyvernoEvaluator stub.
func New(binPath, defaultPolicyDir string) *Evaluator {
	return &Evaluator{BinPath: binPath, DefaultPolicyDir: defaultPolicyDir}
}

func (e *Evaluator) Name() string { return "kyverno" }

// Evaluate is not yet implemented. It returns an error indicating Phase 1 status.
func (e *Evaluator) Evaluate(_ security.EvalInput) ([]security.Finding, error) {
	return nil, fmt.Errorf("kyverno evaluator is a Phase 1 roadmap item and not yet implemented; use --evaluator conftest")
}
