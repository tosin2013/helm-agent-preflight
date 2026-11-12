// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

package main

import (
	"os"

	"github.com/tosin2013/helm-agent-preflight/internal/cmd"
)

func main() {
	root := cmd.NewRootCmd()
	if err := root.Execute(); err != nil {
		os.Exit(4)
	}
}
