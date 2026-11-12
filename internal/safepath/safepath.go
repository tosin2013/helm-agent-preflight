// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

// Package safepath validates that a path does not escape its declared root
// via symlinks or traversal sequences.
package safepath

import (
	"fmt"
	"path/filepath"
	"strings"
)

// Validate resolves all symlinks in path and verifies the result is still
// under allowedRoot. Returns an error if the path escapes.
// If allowedRoot is empty, only absolute path resolution is performed.
func Validate(path, allowedRoot string) error {
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		return fmt.Errorf("resolve path %q: %w", path, err)
	}
	if allowedRoot == "" {
		return nil
	}
	rootResolved, err := filepath.EvalSymlinks(allowedRoot)
	if err != nil {
		return fmt.Errorf("resolve root %q: %w", allowedRoot, err)
	}
	if !strings.HasPrefix(resolved, rootResolved) {
		return fmt.Errorf("path %q escapes allowed root %q (resolved: %q)", path, allowedRoot, resolved)
	}
	return nil
}
