// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

package report_test

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/tosin2013/helm-agent-preflight/internal/report"
	"github.com/tosin2013/helm-agent-preflight/internal/security"
)

func TestDetermineVerdict_Pass(t *testing.T) {
	findings := []security.Finding{
		{RuleID: "HOOK-001", VerdictContribution: "WARN", PreExisting: false},
	}
	assert.Equal(t, report.VerdictPass, report.DetermineVerdict(findings))
}

func TestDetermineVerdict_Block(t *testing.T) {
	findings := []security.Finding{
		{RuleID: "RBAC-001", VerdictContribution: "BLOCK", PreExisting: false},
	}
	assert.Equal(t, report.VerdictBlock, report.DetermineVerdict(findings))
}

func TestDetermineVerdict_PreExistingNotBlock(t *testing.T) {
	findings := []security.Finding{
		{RuleID: "RBAC-001", VerdictContribution: "BLOCK", PreExisting: true},
	}
	assert.Equal(t, report.VerdictPass, report.DetermineVerdict(findings),
		"pre-existing BLOCK should not cause BLOCK verdict")
}

func TestBuildIndeterminate_HasFingerprint(t *testing.T) {
	r := report.BuildIndeterminate("my-release", "default", nil, "baseline render failed")
	assert.NotEmpty(t, r.Fingerprint)
	assert.Equal(t, "INDETERMINATE", r.Verdict)
	assert.Equal(t, "PARTIAL", r.Evidence.Completeness)
}
