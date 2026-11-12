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

if command -v curl >/dev/null 2>&1; then
  if curl -fsSL -o "${PLUGIN_DIR}/bin/${BINARY_NAME}" "$URL" 2>/dev/null; then
    chmod +x "${PLUGIN_DIR}/bin/${BINARY_NAME}"
    echo "helm-agent-preflight: installed ${BINARY_NAME} v${VERSION}"
    exit 0
  fi
elif command -v wget >/dev/null 2>&1; then
  if wget -q -O "${PLUGIN_DIR}/bin/${BINARY_NAME}" "$URL" 2>/dev/null; then
    chmod +x "${PLUGIN_DIR}/bin/${BINARY_NAME}"
    echo "helm-agent-preflight: installed ${BINARY_NAME} v${VERSION}"
    exit 0
  fi
fi

echo "helm-agent-preflight: download failed or no release binary available." >&2
echo "Build from source: make build && helm plugin install ." >&2
exit 0
