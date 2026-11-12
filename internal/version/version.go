// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

package version

import "runtime"

var (
	Version      = "v0.1.0-dev"
	GitCommit    = "unknown"
	GitTreeState = "unknown"
)

func String() string {
	return Version + " (" + GitCommit + ", " + runtime.Version() + ")"
}
