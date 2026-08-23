# Go evaluation prompts

Each file in this directory is one prompt + expected-shape checklist.
Run them through the model with `scripts/benchmark.sh` or by hand from
the Open WebUI chat box. The checklist is the acceptance test — the
model's output is graded against it, not against a reference answer.

**Target model (v0.3.0):** `qwen3-27b` (Modelfile alias for
`qwen3.8:27b`). The recipes in `config/ollama/Modelfile.qwen3-27b`
and `Modelfile.qwen3-27b-thinking` carry the same `PROMPT.coding.md`
system prompt, so acceptance is graded against the same persona. For
multi-step refactor prompts prefer the thinking variant; for the
small completions the default non-thinking primary is the right target.

## How to use

1. Open the prompt file.
2. Copy the prompt body into a new chat (or POST to
   `http://127.0.0.1:11434/v1/chat/completions`).
3. Verify the answer satisfies every item in "Acceptance".
4. File a regression entry under "Known regressions" if it fails twice.

## Known regressions

(none yet)