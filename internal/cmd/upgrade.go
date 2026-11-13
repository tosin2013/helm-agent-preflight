// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

package cmd

import (
	"encoding/json"
	"fmt"
	"io"
	"os"

	"github.com/spf13/cobra"
	"github.com/tosin2013/helm-agent-preflight/internal/diff"
	"github.com/tosin2013/helm-agent-preflight/internal/hash"
	"github.com/tosin2013/helm-agent-preflight/internal/render"
	"github.com/tosin2013/helm-agent-preflight/internal/report"
	"github.com/tosin2013/helm-agent-preflight/internal/safepath"
	"github.com/tosin2013/helm-agent-preflight/internal/security"
	conftesteval "github.com/tosin2013/helm-agent-preflight/internal/security/conftest"
	kyvernoeval "github.com/tosin2013/helm-agent-preflight/internal/security/kyverno"
)

type upgradeOptions struct {
	From        string
	To          string
	ValuesFile  string
	ReleaseName string
	Namespace   string
	KubeVersion string
	PolicyDir   string
	Evaluator   string
	OutputFile  string
}

func newUpgradeCmd() *cobra.Command {
	var opts upgradeOptions

	cmd := &cobra.Command{
		Use:   "upgrade",
		Short: "Run offline preflight check for a Helm upgrade",
		Long: `Renders both the from (baseline) and to (candidate) charts offline,
diffs the manifests, evaluates Rego/Kyverno security policies, and emits a JSON report.

No cluster access, no network calls, and no deployment occur.

Exit codes:
  0  PASS           - all configured offline checks passed
  2  BLOCK          - at least one enforced policy was violated
  3  INDETERMINATE  - required verification could not be completed
  4  error          - tool execution failure

Evaluators:
  conftest  (default) Uses Conftest + Rego policies (OPA). Requires conftest in PATH.
  kyverno             Phase 1 roadmap — not yet implemented.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			return runUpgrade(&opts)
		},
	}

	f := cmd.Flags()
	f.StringVar(&opts.From, "from", "", "Path to baseline chart directory or tarball (required)")
	f.StringVar(&opts.To, "to", "", "Path to candidate chart directory or tarball (required)")
	f.StringVar(&opts.ValuesFile, "values", "", "Path to values file (optional)")
	f.StringVar(&opts.ReleaseName, "release-name", "", "Helm release name (required)")
	f.StringVar(&opts.Namespace, "namespace", "default", "Kubernetes namespace")
	f.StringVar(&opts.KubeVersion, "kube-version", "", "Kubernetes version for Capabilities (required, e.g. 1.35)")
	f.StringVar(&opts.PolicyDir, "policy-dir", "", "Directory containing Rego policies (default: $HELM_PLUGIN_DIR/policies/rego)")
	f.StringVar(&opts.Evaluator, "evaluator", "conftest", "Security evaluator: conftest (default) or kyverno (Phase 1)")
	f.StringVar(&opts.OutputFile, "output-file", "", "Write JSON report to file (default: stdout)")

	_ = cmd.MarkFlagRequired("from")
	_ = cmd.MarkFlagRequired("to")
	_ = cmd.MarkFlagRequired("release-name")
	_ = cmd.MarkFlagRequired("kube-version")

	return cmd
}

func runUpgrade(opts *upgradeOptions) error {
	helmBin := os.Getenv("HELM_BIN")
	if helmBin == "" {
		helmBin = "helm"
	}

	// 1. Validate paths (symlink escape check).
	if err := safepath.Validate(opts.From, ""); err != nil {
		return exitIndeterminate(opts, nil, fmt.Sprintf("unsafe --from path: %v", err))
	}
	if err := safepath.Validate(opts.To, ""); err != nil {
		return exitIndeterminate(opts, nil, fmt.Sprintf("unsafe --to path: %v", err))
	}

	// 2. Compute input content digests.
	inputHashes, err := hash.ComputeInputHashes(opts.From, opts.To, opts.ValuesFile, opts.PolicyDir)
	if err != nil {
		return exitIndeterminate(opts, nil, fmt.Sprintf("cannot hash inputs: %v", err))
	}

	renderOpts := func(chartPath string) render.Options {
		return render.Options{
			HelmBin:     helmBin,
			ChartPath:   chartPath,
			ValuesFile:  opts.ValuesFile,
			ReleaseName: opts.ReleaseName,
			Namespace:   opts.Namespace,
			KubeVersion: opts.KubeVersion,
		}
	}

	// 3. Render baseline.
	baselineResult, err := render.Chart(renderOpts(opts.From))
	if err != nil {
		return exitIndeterminate(opts, inputHashes, fmt.Sprintf("baseline render failed: %v", err))
	}

	// 4. Render candidate.
	candidateResult, err := render.Chart(renderOpts(opts.To))
	if err != nil {
		return exitIndeterminate(opts, inputHashes, fmt.Sprintf("candidate render failed: %v", err))
	}

	// 5. Rendering stability check (DET-004).
	stabilityNote := ""
	stabilityConfirmed := true
	if err := render.StabilityCheck(renderOpts(opts.To)); err != nil {
		stabilityNote = fmt.Sprintf("rendering stability check failed: %v", err)
		stabilityConfirmed = false
		fmt.Fprintf(os.Stderr, "WARNING: %s\n", stabilityNote)
	}

	// 6. Diff manifests (using scrubbed maps).
	diffResult := diff.Manifests(baselineResult.Scrubbed, candidateResult.Scrubbed)

	// 7. Build evaluator.
	evaluator, err := buildEvaluator(opts)
	if err != nil {
		return exitIndeterminate(opts, inputHashes, fmt.Sprintf("evaluator init failed: %v", err))
	}

	// 8. Evaluate security policies (baseline preservation: SEC-007).
	findings, err := evaluator.Evaluate(security.EvalInput{
		Candidate: candidateResult.Scrubbed,
		Baseline:  baselineResult.Scrubbed,
		PolicyDir: opts.PolicyDir,
	})
	if err != nil {
		return exitIndeterminate(opts, inputHashes, fmt.Sprintf("security evaluation failed: %v", err))
	}

	// 9. Determine verdict.
	verdict := report.DetermineVerdict(findings)
	if !stabilityConfirmed {
		verdict = report.VerdictIndeterminate
	}

	// 10. Build report.
	r := report.Build(report.BuildInput{
		FromPath:    opts.From,
		ToPath:      opts.To,
		ValuesPath:  opts.ValuesFile,
		PolicyPath:  policyLabel(opts.PolicyDir, evaluator.Name()),
		ReleaseName: opts.ReleaseName,
		Namespace:   opts.Namespace,
		KubeVersion: opts.KubeVersion,

		InputHashes:        inputHashes,
		BaselineResult:     baselineResult,
		CandidateResult:    candidateResult,
		DiffResult:         diffResult,
		Findings:           findings,
		Verdict:            verdict,
		StabilityConfirmed: stabilityConfirmed,
		StabilityNote:      stabilityNote,
	})

	// 11. Write report.
	out, err := openOutput(opts.OutputFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "cannot open output: %v\n", err)
		os.Exit(4)
	}
	if opts.OutputFile != "" {
		defer out.Close()
	}
	enc := json.NewEncoder(out)
	enc.SetIndent("", "  ")
	if err := enc.Encode(r); err != nil {
		fmt.Fprintf(os.Stderr, "cannot write report: %v\n", err)
		os.Exit(4)
	}

	// 12. Exit code per PRD v0.3.
	switch verdict {
	case report.VerdictPass:
		return nil
	case report.VerdictBlock:
		os.Exit(2)
	case report.VerdictIndeterminate:
		os.Exit(3)
	}
	return nil
}

func buildEvaluator(opts *upgradeOptions) (security.Evaluator, error) {
	switch opts.Evaluator {
	case "kyverno":
		return kyvernoeval.New("kyverno", opts.PolicyDir), nil
	case "conftest", "":
		return conftesteval.New("conftest", opts.PolicyDir), nil
	default:
		return nil, fmt.Errorf("unknown evaluator %q; supported: conftest, kyverno", opts.Evaluator)
	}
}

func exitIndeterminate(opts *upgradeOptions, hashes *hash.InputHashes, reason string) error {
	r := report.BuildIndeterminate(opts.ReleaseName, opts.Namespace, hashes, reason)
	out, _ := openOutput(opts.OutputFile)
	enc := json.NewEncoder(out)
	enc.SetIndent("", "  ")
	_ = enc.Encode(r)
	os.Exit(3)
	return nil
}

func openOutput(path string) (io.WriteCloser, error) {
	if path == "" {
		return os.Stdout, nil
	}
	return os.Create(path)
}

func policyLabel(policyDir, evaluatorName string) string {
	if policyDir == "" {
		return fmt.Sprintf("embedded:%s-rego-baseline", evaluatorName)
	}
	return policyDir
}
