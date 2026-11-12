# Contributing to helm-agent-preflight

## Developer Certificate of Origin

All contributions must be signed with the Developer Certificate of Origin (DCO).

Use `git commit -s` for every commit. The `Author` and `Signed-off-by` lines
must match your git config `user.name` and `user.email` exactly.

```bash
git config user.name "Your Name"
git config user.email "you@example.com"
git commit -s -m "feat: describe your change"
```

## Security vulnerabilities

Do NOT open a public GitHub issue for security vulnerabilities.

Report to: **cncf-helm-security@lists.cncf.io**

See [SECURITY.md](SECURITY.md) for details.

## Branches

- `main` — active development

## Pull requests

This project currently has a single maintainer. Open a PR against `main`;
once additional maintainers join, the standard Helm requirement of 2 approvals
will apply to PRs of size/S or larger.

## Code standards

- Go: follow `gofmt` and `golangci-lint` with the project `.golangci.yml`
- Tests: table-driven tests using `github.com/stretchr/testify`
- Build: `make build`, `make test`, `make test-style`
- Commits: DCO sign-off required (`git commit -s`)
