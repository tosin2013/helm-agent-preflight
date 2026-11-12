// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

package hash

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
)

// InputHashes holds SHA256 digests for all preflight inputs.
type InputHashes struct {
	Baseline  string
	Candidate string
	Values    string
	Policy    string
}

// ComputeInputHashes computes SHA256 digests for the given paths.
// Empty paths are skipped (optional inputs).
func ComputeInputHashes(baseline, candidate, values, policy string) (*InputHashes, error) {
	h := &InputHashes{}
	var err error

	h.Baseline, err = HashPath(baseline)
	if err != nil {
		return nil, fmt.Errorf("hash baseline: %w", err)
	}
	h.Candidate, err = HashPath(candidate)
	if err != nil {
		return nil, fmt.Errorf("hash candidate: %w", err)
	}
	if values != "" {
		h.Values, err = HashPath(values)
		if err != nil {
			return nil, fmt.Errorf("hash values: %w", err)
		}
	}
	if policy != "" {
		h.Policy, err = HashPath(policy)
		if err != nil {
			return nil, fmt.Errorf("hash policy: %w", err)
		}
	}
	return h, nil
}

// HashPath hashes a file or directory (sorted walk for directories).
func HashPath(path string) (string, error) {
	info, err := os.Stat(path)
	if err != nil {
		return "", err
	}
	if info.IsDir() {
		return hashDir(path)
	}
	return hashFile(path)
}

func hashFile(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func hashDir(dir string) (string, error) {
	h := sha256.New()
	var files []string
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !d.IsDir() {
			files = append(files, path)
		}
		return nil
	})
	if err != nil {
		return "", err
	}
	sort.Strings(files)
	for _, f := range files {
		fh, err := hashFile(f)
		if err != nil {
			return "", err
		}
		fmt.Fprintf(h, "%s  %s\n", fh, f)
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
