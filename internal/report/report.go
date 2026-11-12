// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

// Package report defines the JSON output schema and builds report instances.
package report

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"sort"
	"time"

	"github.com/tosin2013/helm-agent-preflight/internal/diff"
	"github.com/tosin2013/helm-agent-preflight/internal/hash"
	"github.com/tosin2013/helm-agent-preflight/internal/render"
	"github.com/tosin2013/helm-agent-preflight/internal/security"
	"github.com/tosin2013/helm-agent-preflight/internal/version"
)

// Verdict constants (exit codes per PRD v0.3).
const (
	VerdictPass          = "PASS"
	VerdictBlock         = "BLOCK"
	VerdictIndeterminate = "INDETERMINATE"
)

// Report is the top-level JSON schema for helm-agent-preflight output.
type Report struct {
	SchemaVersion    string             `json:"schema_version"`
	Tool             ToolInfo           `json:"tool"`
	Operation        OpInfo             `json:"operation"`
	Verdict          string             `json:"verdict"`
	Inputs           Inputs             `json:"inputs"`
	Rendering        RenderingInfo      `json:"rendering"`
	DiffSummary      DiffSummary        `json:"diff_summary"`
	SecurityFindings []security.Finding `json:"security_findings"`
	Evidence         Evidence           `json:"evidence"`
	Fingerprint      string             `json:"fingerprint"`
	RunMetadata      RunMeta            `json:"run_metadata"`
}

// ToolInfo describes the tool version.
type ToolInfo struct {
	Name    string `json:"name"`
	Version string `json:"version"`
	Commit  string `json:"commit"`
}

// OpInfo describes the operation.
type OpInfo struct {
	Type                 string `json:"type"`
	OfflineMode          bool   `json:"offline_mode"`
	TimestampUTC         string `json:"timestamp_utc"`
	NoDeploymentOccurred bool   `json:"no_deployment_occurred"`
}

// Inputs holds references to all input artifacts.
type Inputs struct {
	FromChart   FileRef `json:"from_chart"`
	ToChart     FileRef `json:"to_chart"`
	ValuesFile  FileRef `json:"values_file,omitempty"`
	ReleaseName string  `json:"release_name"`
	Namespace   string  `json:"namespace"`
	KubeVersion string  `json:"kubernetes_version"`
	PolicyFile  FileRef `json:"policy_file"`
}

// FileRef is a path + SHA256 digest pair.
type FileRef struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
}

// RenderingInfo carries stability check results.
type RenderingInfo struct {
	StabilityConfirmed bool   `json:"stability_confirmed"`
	StabilityNote      string `json:"stability_note,omitempty"`
}

// DiffSummary summarizes resource changes.
type DiffSummary struct {
	AddedCount    int                     `json:"added_count"`
	ModifiedCount int                     `json:"modified_count"`
	RemovedCount  int                     `json:"removed_count"`
	Added         []render.ResourceKey    `json:"added"`
	Modified      []diff.ModifiedResource `json:"modified"`
	Removed       []render.ResourceKey    `json:"removed"`
}

// Evidence describes verification completeness.
type Evidence struct {
	Completeness          string   `json:"completeness"`
	Limitations           []string `json:"limitations"`
	HelmExitCodeBaseline  int      `json:"helm_exit_code_baseline"`
	HelmExitCodeCandidate int      `json:"helm_exit_code_candidate"`
}

// RunMeta carries execution context metadata.
type RunMeta struct {
	AgentSessionID       interface{} `json:"agent_session_id"`
	HumanRunnable        bool        `json:"human_runnable"`
	NoClusterCredentials bool        `json:"no_cluster_credentials"`
	NoDeploymentOccurred bool        `json:"no_deployment_occurred"`
}

// BuildInput carries all resolved data needed to build a Report.
type BuildInput struct {
	FromPath    string
	ToPath      string
	ValuesPath  string
	PolicyPath  string
	ReleaseName string
	Namespace   string
	KubeVersion string

	InputHashes     *hash.InputHashes
	BaselineResult  *render.Result
	CandidateResult *render.Result
	DiffResult      *diff.Result
	Findings        []security.Finding
	Verdict         string
	PolicyVersion   string

	StabilityConfirmed bool
	StabilityNote      string
}

// Build constructs a fully-populated Report.
func Build(in BuildInput) *Report {
	r := &Report{
		SchemaVersion: "1.0.0",
		Tool:          ToolInfo{Name: "helm-agent-preflight", Version: version.Version, Commit: version.GitCommit},
		Operation: OpInfo{
			Type:                 "upgrade",
			OfflineMode:          true,
			TimestampUTC:         time.Now().UTC().Format(time.RFC3339),
			NoDeploymentOccurred: true,
		},
		Verdict: in.Verdict,
		Inputs: Inputs{
			FromChart:   FileRef{Path: in.FromPath, SHA256: in.InputHashes.Baseline},
			ToChart:     FileRef{Path: in.ToPath, SHA256: in.InputHashes.Candidate},
			ReleaseName: in.ReleaseName,
			Namespace:   in.Namespace,
			KubeVersion: in.KubeVersion,
			PolicyFile:  FileRef{Path: in.PolicyPath, SHA256: in.InputHashes.Policy},
		},
		Rendering: RenderingInfo{
			StabilityConfirmed: in.StabilityConfirmed,
			StabilityNote:      in.StabilityNote,
		},
		DiffSummary: DiffSummary{
			AddedCount:    len(in.DiffResult.Added),
			ModifiedCount: len(in.DiffResult.Modified),
			RemovedCount:  len(in.DiffResult.Removed),
			Added:         in.DiffResult.Added,
			Modified:      in.DiffResult.Modified,
			Removed:       in.DiffResult.Removed,
		},
		SecurityFindings: sortedFindings(in.Findings),
		Evidence: Evidence{
			Completeness:          "COMPLETE",
			Limitations:           []string{},
			HelmExitCodeBaseline:  in.BaselineResult.HelmExitCode,
			HelmExitCodeCandidate: in.CandidateResult.HelmExitCode,
		},
		RunMetadata: RunMeta{
			AgentSessionID:       nil,
			HumanRunnable:        true,
			NoClusterCredentials: true,
			NoDeploymentOccurred: true,
		},
	}
	if in.ValuesPath != "" {
		r.Inputs.ValuesFile = FileRef{Path: in.ValuesPath, SHA256: in.InputHashes.Values}
	}
	if !in.StabilityConfirmed && in.StabilityNote != "" {
		r.Evidence.Completeness = "PARTIAL"
		r.Evidence.Limitations = append(r.Evidence.Limitations, in.StabilityNote)
	}
	r.Fingerprint = computeFingerprint(r)
	return r
}

// BuildIndeterminate creates a minimal INDETERMINATE report.
func BuildIndeterminate(releaseName, namespace string, hashes *hash.InputHashes, reason string) *Report {
	h := &hash.InputHashes{}
	if hashes != nil {
		h = hashes
	}
	r := &Report{
		SchemaVersion: "1.0.0",
		Tool:          ToolInfo{Name: "helm-agent-preflight", Version: version.Version, Commit: version.GitCommit},
		Operation: OpInfo{
			Type:                 "upgrade",
			OfflineMode:          true,
			TimestampUTC:         time.Now().UTC().Format(time.RFC3339),
			NoDeploymentOccurred: true,
		},
		Verdict: VerdictIndeterminate,
		Inputs: Inputs{
			ReleaseName: releaseName,
			Namespace:   namespace,
			FromChart:   FileRef{SHA256: h.Baseline},
			ToChart:     FileRef{SHA256: h.Candidate},
		},
		SecurityFindings: []security.Finding{},
		DiffSummary:      DiffSummary{Added: []render.ResourceKey{}, Modified: []diff.ModifiedResource{}, Removed: []render.ResourceKey{}},
		Evidence: Evidence{
			Completeness: "PARTIAL",
			Limitations:  []string{reason},
		},
		RunMetadata: RunMeta{HumanRunnable: true, NoClusterCredentials: true, NoDeploymentOccurred: true},
	}
	r.Fingerprint = computeFingerprint(r)
	return r
}

// DetermineVerdict returns BLOCK if any new (non-pre-existing) finding blocks, else PASS.
func DetermineVerdict(findings []security.Finding) string {
	for _, f := range findings {
		if f.VerdictContribution == security.ContributionBlock && !f.PreExisting {
			return VerdictBlock
		}
	}
	return VerdictPass
}

func computeFingerprint(r *Report) string {
	type canonical struct {
		SchemaVersion string
		ToolVersion   string
		Verdict       string
		FromSHA256    string
		ToSHA256      string
		PolicySHA256  string
		ValuesSHA256  string
		Findings      []security.Finding
		AddedCount    int
		ModifiedCount int
		RemovedCount  int
	}
	c := canonical{
		SchemaVersion: r.SchemaVersion,
		ToolVersion:   r.Tool.Version,
		Verdict:       r.Verdict,
		FromSHA256:    r.Inputs.FromChart.SHA256,
		ToSHA256:      r.Inputs.ToChart.SHA256,
		PolicySHA256:  r.Inputs.PolicyFile.SHA256,
		ValuesSHA256:  r.Inputs.ValuesFile.SHA256,
		Findings:      r.SecurityFindings,
		AddedCount:    r.DiffSummary.AddedCount,
		ModifiedCount: r.DiffSummary.ModifiedCount,
		RemovedCount:  r.DiffSummary.RemovedCount,
	}
	b, _ := json.Marshal(c)
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

func sortedFindings(in []security.Finding) []security.Finding {
	out := make([]security.Finding, len(in))
	copy(out, in)
	sort.Slice(out, func(i, j int) bool {
		if out[i].RuleID != out[j].RuleID {
			return out[i].RuleID < out[j].RuleID
		}
		return out[i].Object.String() < out[j].Object.String()
	})
	return out
}
