# SPDX-License-Identifier: Apache-2.0
# Copyright The helm-agent-preflight Authors.

BINDIR      := $(CURDIR)/bin
BINNAME     ?= preflight
MODULE      := github.com/tosin2013/helm-agent-preflight

GOBIN         = $(shell go env GOBIN)
ifeq ($(GOBIN),)
GOBIN         = $(shell go env GOPATH)/bin
endif

ARCH          = $(shell go env GOARCH)
OS            = $(shell go env GOOS)

PKG           := ./...
TESTFLAGS     := -count=1 -race
CGO_ENABLED   ?= 0
GOFLAGS       ?= -trimpath

GIT_COMMIT    = $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_TAG       = $(shell git describe --tags --abbrev=0 --exact-match 2>/dev/null || echo "")
GIT_DIRTY     = $(shell test -n "`git status --porcelain`" && echo "dirty" || echo "clean")

LDFLAGS       := -w -s
LDFLAGS       += -X $(MODULE)/internal/version.GitCommit=$(GIT_COMMIT)
LDFLAGS       += -X $(MODULE)/internal/version.GitTreeState=$(GIT_DIRTY)
ifneq ($(GIT_TAG),)
  LDFLAGS     += -X $(MODULE)/internal/version.Version=$(GIT_TAG)
endif

SRC := $(shell find . -type f -name '*.go' -not -path '*/vendor/*') go.mod go.sum

.PHONY: all
all: build

# ---- build ----------------------------------------------------------------

.PHONY: build
build: $(BINDIR)/$(BINNAME)-$(OS)-$(ARCH)

$(BINDIR)/$(BINNAME)-$(OS)-$(ARCH): $(SRC)
	CGO_ENABLED=$(CGO_ENABLED) go build $(GOFLAGS) \
		-ldflags '$(LDFLAGS)' \
		-o '$(BINDIR)/$(BINNAME)-$(OS)-$(ARCH)' \
		./cmd/preflight

.PHONY: build-cross
build-cross:
	@for os in linux darwin windows; do \
		for arch in amd64 arm64; do \
			ext=""; \
			[ "$$os" = "windows" ] && ext=".exe"; \
			echo "Building $$os/$$arch..."; \
			CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch \
				go build $(GOFLAGS) -ldflags '$(LDFLAGS)' \
				-o '$(BINDIR)/$(BINNAME)-'$$os'-'$$arch$$ext \
				./cmd/preflight || exit 1; \
		done; \
	done

# ---- install --------------------------------------------------------------

.PHONY: install
install: build
	helm plugin install .

.PHONY: uninstall
uninstall:
	helm plugin uninstall preflight || true

# ---- test -----------------------------------------------------------------

.PHONY: test
test: test-style test-unit

.PHONY: test-unit
test-unit:
	@echo "==> Running unit tests"
	go test $(GOFLAGS) $(TESTFLAGS) -v $(PKG)

.PHONY: test-coverage
test-coverage:
	@echo "==> Running unit tests with coverage"
	go test $(GOFLAGS) -coverprofile=coverage.out -covermode=atomic $(PKG)
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report: coverage.html"

.PHONY: test-integration
test-integration: build
	@echo "==> Running integration tests"
	PREFLIGHT_BIN='$(BINDIR)/$(BINNAME)-$(OS)-$(ARCH)' \
	HELM_BIN='$(shell which helm 2>/dev/null || echo helm)' \
	bash tests/run-tests.sh

.PHONY: test-style
test-style:
	@echo "==> Running lint"
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run $(PKG); \
	else \
		echo "golangci-lint not found, skipping lint"; \
	fi
	@bash scripts/validate-license.sh

# ---- tidy -----------------------------------------------------------------

.PHONY: tidy
tidy:
	go mod tidy
	go mod verify

# ---- clean ----------------------------------------------------------------

.PHONY: clean
clean:
	@rm -rf '$(BINDIR)' coverage.out coverage.html

# ---- demos ----------------------------------------------------------------

VHSBIN = $(GOBIN)/vhs

.PHONY: demo-install-vhs
demo-install-vhs:
	go install github.com/charmbracelet/vhs@latest
	@echo ""
	@echo "Also install ffmpeg (required by vhs for GIF output):"
	@echo "  sudo dnf install -y ffmpeg        # RHEL / el10"
	@echo "  sudo apt-get install -y ffmpeg    # Ubuntu / Debian"

.PHONY: demo-record
demo-record: demo-record-offline demo-record-agent

.PHONY: demo-record-offline
demo-record-offline:
	@command -v vhs >/dev/null 2>&1 || (echo "vhs not found — run: make demo-install-vhs" && exit 1)
	mkdir -p demos
	vhs demos/offline.tape

.PHONY: demo-record-agent
demo-record-agent:
	@command -v vhs >/dev/null 2>&1 || (echo "vhs not found — run: make demo-install-vhs" && exit 1)
	mkdir -p demos
	vhs demos/agent.tape

# ---- info -----------------------------------------------------------------

.PHONY: info
info:
	@echo "Version:    $(GIT_TAG)"
	@echo "Commit:     $(GIT_COMMIT)"
	@echo "Tree state: $(GIT_DIRTY)"
	@echo "OS/Arch:    $(OS)/$(ARCH)"
