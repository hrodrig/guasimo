# Go evaluation prompts

Each file in this directory is one prompt + expected-shape checklist.
Run them through the model with `scripts/benchmark.sh` or by hand from
the Open WebUI chat box. The checklist is the acceptance test — the
model's output is graded against it, not against a reference answer.

## How to use

1. Open the prompt file.
2. Copy the prompt body into a new chat (or POST to
   `http://127.0.0.1:11434/v1/chat/completions`).
3. Verify the answer satisfies every item in "Acceptance".
4. File a regression entry under "Known regressions" if it fails twice.

## Known regressions

(none yet)