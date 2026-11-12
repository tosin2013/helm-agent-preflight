// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

package cmd

import (
	"github.com/spf13/cobra"
	"github.com/tosin2013/helm-agent-preflight/internal/version"
)

// NewRootCmd builds the root cobra command.
func NewRootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:          "preflight",
		Short:        "Offline Helm upgrade qualification with security checks",
		Version:      version.String(),
		SilenceUsage: true,
	}
	root.AddCommand(newUpgradeCmd())
	return root
}
