#!/usr/bin/env sh
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
# Checks that all .go files have an SPDX license header.
set -e

MISSING=0
while IFS= read -r -d '' file; do
  if ! grep -q "SPDX-License-Identifier" "$file"; then
    echo "MISSING license header: $file"
    MISSING=$((MISSING + 1))
  fi
done < <(find . -name "*.go" -not -path "*/vendor/*" -print0)

if [ "$MISSING" -gt 0 ]; then
  echo "ERROR: $MISSING file(s) missing SPDX license header" >&2
  exit 1
fi
echo "License headers OK"
