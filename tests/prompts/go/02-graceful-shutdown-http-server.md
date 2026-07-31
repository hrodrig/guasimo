# 02-graceful-shutdown-http-server.md

## Prompt

Write a Go HTTP server that handles `GET /healthz` (returns 200 with
body "ok") and `GET /version` (returns the value of a build-time
variable). The server must shut down gracefully on SIGTERM or SIGINT:
stop accepting new connections, wait up to 30 seconds for in-flight
requests to finish, then exit with status 0. Use only the standard
library.

## Acceptance

- [ ] `http.Server` used, not the default `http.ListenAndServe`.
- [ ] `signal.NotifyContext` (Go 1.16+) for SIGTERM/SIGINT.
- [ ] `Shutdown(ctx)` called with a 30-second timeout context.
- [ ] `version` is a `var`, not a `const`, and is documented as
      "overridden at build time via -ldflags".
- [ ] `main.go` is `package main`, has a single `func main()`.
- [ ] On shutdown timeout: log a clear message and exit non-zero.
- [ ] No global state; the server struct is constructed and configured
      inside `main`.
- [ ] Code passes `go vet` and is `gofmt`-clean.

## Difficulty

Easy. Tests idiomatic server lifecycle in Go.