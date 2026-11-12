// SPDX-License-Identifier: Apache-2.0
// Copyright The helm-agent-preflight Authors.

package hash_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/tosin2013/helm-agent-preflight/internal/hash"
)

func TestHashPath_File(t *testing.T) {
	dir := t.TempDir()
	f := filepath.Join(dir, "test.txt")
	require.NoError(t, os.WriteFile(f, []byte("hello"), 0600))

	h, err := hash.HashPath(f)
	require.NoError(t, err)
	assert.Len(t, h, 64)

	h2, err := hash.HashPath(f)
	require.NoError(t, err)
	assert.Equal(t, h, h2, "same file should hash identically")
}

func TestHashPath_Dir_Deterministic(t *testing.T) {
	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, "a.txt"), []byte("aaa"), 0600))
	require.NoError(t, os.WriteFile(filepath.Join(dir, "b.txt"), []byte("bbb"), 0600))

	h1, err := hash.HashPath(dir)
	require.NoError(t, err)
	h2, err := hash.HashPath(dir)
	require.NoError(t, err)
	assert.Equal(t, h1, h2)
}

func TestHashPath_Missing(t *testing.T) {
	_, err := hash.HashPath("/nonexistent/path/xyz")
	assert.Error(t, err)
}
