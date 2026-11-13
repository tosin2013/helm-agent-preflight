#!/usr/bin/env sh
# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.
# Plugin install hook: downloads the platform binary from GitHub releases.
set -e

PLUGIN_DIR="${HELM_PLUGIN_DIR}"
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
esac

VERSION=$(grep '^version:' "${PLUGIN_DIR}/plugin.yaml" | awk '{print $2}')
BINARY_NAME="preflight-${OS}-${ARCH}"
URL="https://github.com/tosin2013/helm-agent-preflight/releases/download/v${VERSION}/${BINARY_NAME}"

mkdir -p "${PLUGIN_DIR}/bin"

install_binary() {
  chmod +x "${PLUGIN_DIR}/bin/${BINARY_NAME}"
  echo "helm-agent-preflight: installed ${BINARY_NAME} v${VERSION}"
  # Warn if conftest is missing — the binary requires it for Rego policy evaluation
  if ! command -v conftest >/dev/null 2>&1; then
    echo ""
    echo "  NOTE: 'conftest' is required for security evaluation but was not found in PATH."
    echo "  Install conftest: https://www.conftest.dev/install/"
    echo "  Quick install (Linux/macOS):"
    echo "    curl -fsSL https://github.com/open-policy-agent/conftest/releases/download/v0.71.1/conftest_0.71.1_\$(uname -s)_x86_64.tar.gz | tar -xz -C /usr/local/bin conftest"
    echo ""
  fi
  exit 0
}

if command -v curl >/dev/null 2>&1; then
  if curl -fsSL -o "${PLUGIN_DIR}/bin/${BINARY_NAME}" "$URL" 2>/dev/null; then
    install_binary
  fi
elif command -v wget >/dev/null 2>&1; then
  if wget -q -O "${PLUGIN_DIR}/bin/${BINARY_NAME}" "$URL" 2>/dev/null; then
    install_binary
  fi
fi

echo "helm-agent-preflight: download failed or no release binary available." >&2
echo "Build from source: make build && helm plugin install ." >&2
exit 0
