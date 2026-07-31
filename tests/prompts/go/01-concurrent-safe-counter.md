# 01-concurrent-safe-counter.md

## Prompt

Write a Go package `counter` that provides a `Counter` type which is safe
for concurrent use, plus a `Snapshot` method that returns a consistent
point-in-time view of the current value across all goroutines that have
called `Increment` at least once. Add a small table-driven test using
`testing.T`.

## Acceptance

- [ ] Type defined as `type Counter struct { ... }` with unexported fields.
- [ ] `New() *Counter` constructor.
- [ ] `Increment()` and `Value() int64` methods.
- [ ] `Snapshot() int64` returns the value as observed atomically at the
      call site (does not require a lock to read).
- [ ] Code passes `go vet ./...` and `gofmt -l .` is empty.
- [ ] Table-driven test uses `t.Run` subtests.
- [ ] Test covers: serial increment, parallel increment (sync.WaitGroup,
      N goroutines), zero-value counter, and Snapshot consistency under
      contention.
- [ ] No external dependencies beyond the standard library.
- [ ] No use of `sync/atomic` for `Snapshot` (the requirement is "atomic
      at the call site", which means the field must be aligned and read
      with the matching atomic load, not that a mutex is forbidden — but
      a mutex-only implementation is acceptable if the read is lock-free).

## Difficulty

Medium. Tests both concurrency primitives and idiomatic Go structure.