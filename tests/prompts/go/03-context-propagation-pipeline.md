# 03-context-propagation-pipeline.md

## Prompt

Write a Go function `RunPipeline` that takes a `context.Context`, a
slice of `Stage` (each is `func(context.Context, Item) (Item, error)`),
and an initial `Item`. It runs the stages in order, short-circuiting
on the first error or on context cancellation, and returns the final
`Item` and error. Add unit tests covering: success path, error in
stage 2, context cancelled before stage 3, and a stage that respects
context cancellation mid-work.

## Acceptance

- [ ] Signature: `func RunPipeline[T any](ctx context.Context, stages []Stage[T], initial T) (T, error)`.
- [ ] Generic over `T` (Go 1.18+).
- [ ] Each stage call is in a `select` against `ctx.Done()` and the
      stage's own return channel, OR the stage itself is documented to
      respect context — and tests prove it does.
- [ ] Error wrapped with `fmt.Errorf("stage %d: %w", i, err)`.
- [ ] Returns the zero value of `T` on error.
- [ ] Tests use `t.Run` and at least one uses `time.After` to cancel.
- [ ] No data races under `go test -race`.

## Difficulty

Hard. Tests generics, context propagation, and error wrapping idioms.