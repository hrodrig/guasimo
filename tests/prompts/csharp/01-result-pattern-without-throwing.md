# 01-result-pattern-without-throwing.md

## Prompt

Write a C# 12 (.NET 8) `Result<T>` type that represents either a success
value of type `T` or a failure with a structured error. Provide
`Map`, `Bind`, and `Tap` extension methods. Show a usage example for
parsing an int from a string, validating it is in `[1, 100]`, and
returning the doubled value. Use only the BCL — no third-party
packages.

## Acceptance

- [ ] `Result<T>` is a `readonly record struct` or a `sealed record class`.
      Pick one and justify briefly.
- [ ] Error type is also a record with at least `Code` and `Message`.
- [ ] `Map` and `Bind` handle the failure case by short-circuiting.
- [ ] `Tap` runs the side-effect delegate only on success.
- [ ] No exceptions thrown by the helper itself for the failure path.
- [ ] Nullable reference types enabled; no `#nullable disable`.
- [ ] Example covers: failure on parse, failure on validation, success.
- [ ] No `dynamic`, no `object` boxing.

## Difficulty

Medium. Tests record types, discriminated-union-via-types pattern, and
extension methods.