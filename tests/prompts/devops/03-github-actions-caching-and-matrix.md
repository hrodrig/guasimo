# 03-github-actions-caching-and-matrix.md

## Prompt

Write a GitHub Actions workflow file `.github/workflows/test.yml` that
runs a Go test matrix across Go 1.22 and 1.23 on every push and pull
request. The workflow must:

1. Use `actions/setup-go@v5` with caching enabled.
2. Cache key includes `go.sum` and the runner OS.
3. Run `go vet ./...`, `gofmt -l .` (fail if non-empty), and `go test
   ./... -race -coverprofile=coverage.out`.
4. Upload the coverage report as an artifact named `coverage-<go-version>`.
5. Concurrency: cancel in-progress runs on the same PR.

## Acceptance

- [ ] Triggered on `push` and `pull_request`.
- [ ] Matrix has `go-version: ['1.22', '1.23']`.
- [ ] `actions/setup-go@v5` with `cache: true`.
- [ ] Cache key uses `${{ runner.os }}-go-${{ hashFiles('**/go.sum') }}`.
- [ ] `gofmt -l .` runs and the step fails if output is non-empty
      (the canonical way: `test -z "$(gofmt -l .)"`).
- [ ] `actions/upload-artifact@v4` (not v3) with the per-version name.
- [ ] `concurrency:` block at the top, group by `${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}` with `cancel-in-progress: true` for PRs.
- [ ] Permissions block at the top is minimal (`contents: read`).
- [ ] No `actions/checkout@v3` — v4.

## Difficulty

Medium. Tests CI hygiene for a Go repo.