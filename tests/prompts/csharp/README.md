# C# evaluation prompts

Same workflow as the Go prompts: copy the prompt into a chat, grade
against the acceptance checklist. The bar is .NET 8+ idiomatic code with
nullable reference types enabled and async-correct.

**Target model (v0.3.0):** `qwen3-27b` (Modelfile alias for
`qwen3.8:27b`). Same persona and sampling defaults as the Go suite;
see `tests/prompts/go/README.md` for the variant choice guidance.

## Known regressions

(none yet)