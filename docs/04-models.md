# 04 — Models

## Selection criteria

For a coding LLM on a 32 GB CPU box we want:

1. **Strong on real programming tasks**, not just chat.
2. **Quantisation-friendly**: Q4_K_M should preserve ≥ 95 % of FP16 quality.
3. **Open licence** (Apache-2.0 / MIT / etc.) so we can self-host freely.
4. **Active maintenance** in 2025–2026, with regular code-specialised
   fine-tunes.

## Primary model — Qwen3.8-27B-Instruct (Q4_K_M)

| Attribute         | Value                                       |
|-------------------|---------------------------------------------|
| Family            | Qwen 3.8                                    |
| Size              | 27 B parameters (dense)                     |
| Quantisation      | Q4_K_M (4-bit, K-quant, medium)             |
| Disk              | ~18 GB                                      |
| RAM at inference  | ~25 GB partial-offload (weights + KV cache, 64K ctx) |
| Context window    | 256 K (we use 8–32 K; longer costs RAM)     |
| Modality          | Text + image (vision-language)              |
| Thinking          | On by default; per-request toggle           |
| Licence           | Apache-2.0                                  |
| Ollama tag        | `qwen3.8:27b`                               |
| Modelfile alias   | `qwen3-27b` (auto-created by `install-aliases.sh`) |
| Why               | Strongest local coder for this hardware in 2026 |

This is the daily driver as of v0.3.0. Use it for code completion,
refactor, review, explanation, docstring writing, and language
translation between Go ↔ C#.

### Tradeoff: partial offload on the RTX 3060 (12 GB)

The 18 GB Q4_K_M does not fit fully in 12 GB of VRAM. Ollama keeps the
layers that fit on the GPU and offloads the rest to CPU/RAM. Expect
**~4 gen tok/s with a 64K `num_ctx` in steady state** (validated on the
reference box, 2026-08-23, `num_ctx 65536`, warm load; cold load is
lower while the model streams in). Dropping `num_ctx` to 4096 does not
materially change generation rate (~5 t/s), but Hermes Agent's 64K
context floor is the number that matters. This is down from the
~18 tok/s the previous v0.2.x primary (Qwen2.5-Coder-14B, fully in
VRAM) achieved.

This is the documented cost of gaining agentic coding, multimodal
input, and 256K context on the same single-user box. Operators who
want fast chat can drop to `secondary` (Qwen2.5-Coder-7B, full VRAM,
~25–30 tok/s) for inline completions and keep `primary` for review
and refactor where quality matters more than latency.

### Validated pull (Ubuntu 26.04 + RTX 3060)

Pull validation for the previous primary (Qwen2.5-Coder-14B) is
preserved in the git history of v0.2.x (`assets/ollama-pull-qwen25-coder-14b-ok.png`).
The v0.3.0 primary (`qwen3.8:27b`) is too new for a captured pull
screenshot; a fresh capture will land here once the reference box
finishes the 18 GB download.

From the v0.2.2 reference run on the same box:
`./scripts/healthcheck.sh` → **8 ok / 0 fail**;
`./scripts/benchmark.sh primary` (against the 14B predecessor) →
~**18** gen tok/s, ~**4** prompt tok/s (200 gen tokens, ~57 s wall).

## Secondary model — Qwen2.5-Coder-7B-Instruct (Q4_K_M)

| Attribute         | Value                                       |
|-------------------|---------------------------------------------|
| Size              | 7 B parameters                              |
| Quantisation      | Q4_K_M                                      |
| Disk              | ~5 GB                                       |
| RAM               | ~6 GB                                       |
| Licence           | Apache-2.0                                  |
| Why               | Fast responses, fits comfortably with 14 B also loaded |

Use this for quick autocompletion-style prompts where the larger model
would feel sluggish.

## Large model — Qwen2.5-Coder-32B-Instruct (Q4_K_M) — LEGACY, optional

**Not pulled by `pull-models.sh` since v0.3.0.** The Q4 GGUF is ~20 GB
and only useful with partial CPU offload; the v0.3.0 primary
(Qwen3.8-27B) gives comparable context and better agentic quality on
the same hardware.

Operators who want to experiment with the 32 B can pull it directly:

    ollama pull qwen2.5-coder:32b-instruct-q4_K_M

The legacy Modelfile `config/ollama/Modelfile.coder-32b` is kept in the
repo but no longer referenced by `pull-models.sh` or `benchmark.sh`.

## Thinking variant — Qwen3.8-27B (reasoning on)

Same `qwen3.8:27b` base as the primary, with a system prompt that
forces step-by-step reasoning. Alias `qwen3-27b-thinking` from
`config/ollama/Modelfile.qwen3-27b-thinking`; auto-created by
`scripts/install-aliases.sh` after the primary base is in the local
library. No extra pull weight — it reuses the primary download.

Use for code review, multi-step refactor, and hard bug analysis where
the audit trail of `<think>…</think>` blocks is worth the latency.
Default chat and IDE inline completions should still use the non-thinking
primary (`qwen3-27b`) for speed.

Reasoning depth is per-request via the `reasoning_effort` parameter
(higher = more tokens in the trace). Qwen 3.8 supports the standard
`/think` and `/no_think` prompt toggles as well.

## Optional — Gemma 4 12B (`gemma`)

| Attribute         | Value                                       |
|-------------------|---------------------------------------------|
| Ollama tag        | `gemma4:12b`                                |
| Nickname          | `./scripts/pull-models.sh gemma`            |
| Disk              | ~8 GB                                       |
| Self-host 3060    | Yes at Q4; 8–16K ctx comfortable; 64K tight |
| Licence           | Apache-2.0 (Gemma 4)                        |
| Why               | Strong tool-calling / agent UX; multimodal  |

Not the daily coding driver (Qwen2.5-Coder still wins on pure code), but
a good alternate for Hermes Agent and Open WebUI tool workflows. Prefer
this or `secondary` (7B coder) when 14B @ Hermes’ 64K floor feels too
slow.

## Optional — DeepSeek-Coder-V2-Lite (`deepseek`)

| Attribute         | Value                                       |
|-------------------|---------------------------------------------|
| Ollama tag        | `deepseek-coder-v2:lite` (~8.9 GB, MoE)     |
| Nickname          | `./scripts/pull-models.sh deepseek`         |
| Self-host 3060    | Yes                                         |
| Licence           | DeepSeek licence (open weights; check card) |
| Why               | Strong coding backup; different training    |

Pull when you want a second opinion vs Qwen on hard refactors. Alias
`deepseek-lite` accepted by the pull/benchmark scripts.

## Why Qwen 3.8 (not Qwen 2.5-Coder / Llama / Mistral / …)

| Model family              | Coding (self-host focus) | Self-host on RTX 3060 (12 GB)? | Verdict |
|---------------------------|--------------------------|--------------------------------|---------|
| **Qwen3.8-27B**           | High (agentic, multimodal) | Partial offload (Q4 @ 64K)  | **Primary** (v0.3.0+) |
| Qwen2.5-Coder-14B-Instruct| High                     | Yes, full VRAM (Q4 @ 8K)       | Legacy primary (v0.2.x) |
| Qwen2.5-Coder-7B-Instruct | High / fast              | Yes, full VRAM                 | Secondary |
| Qwen2.5-Coder-32B-Instruct| High                     | Partial offload (heavy)        | LEGACY (not pulled by default) |
| Gemma 4 12B               | High (agents / tools)    | Yes (64K tight)                | Optional `gemma` |
| DeepSeek-Coder-V2-Lite    | Medium-high              | Yes                            | Optional `deepseek` |
| Qwen3-Coder-30B-A3B (MoE) | High (3.3B active)       | Partial offload (faster than 27B) | Considered, not picked |
| Llama-3.1-8B-Instruct     | Medium                   | Yes, fast                      | Niche   |
| Mistral-Codestral-22B     | High                     | Yes, tight                     | Considered |
| CodeLlama-70B             | High                     | No (needs ≥ 40 GB)             | Excluded |
| Bonsai (1-bit)            | Weak on code             | Tiny, but Ollama/Q1_0 friction | Out of scope |

The Qwen 3.8 generation takes the primary slot in v0.3.0 because it
beats Qwen2.5-Coder-14B on agentic coding, adds multimodal (text +
image) input, supports 256K context, and ships under the same Apache
2.0 licence. The cost is partial offload on the RTX 3060 and lower
tokens/s than the previous primary. Qwen3-Coder-30B-A3B (MoE) was a
close runner-up — kept as a `considered` entry because the MoE
3.3B-active footprint was promising for partial offload, but it lands
~5 months earlier than the 27B and the quality gap was visible on
the local harness at the time of selection.

## Modelfiles

Each named model is a `Modelfile` in `config/ollama/`. A Modelfile specifies
the base GGUF, the chat template, the system prompt, and sampling defaults.
`scripts/install-aliases.sh` applies the recipes to the running Ollama after
each `pull-models.sh`; aliases are created with the Modelfile basename
minus the `Modelfile.` prefix (e.g. `Modelfile.qwen3-27b` → alias
`qwen3-27b`).

Recipes in this repo (v0.3.0+):

| File                                              | Alias                  | Base               | Notes                  |
|---------------------------------------------------|------------------------|--------------------|------------------------|
| `config/ollama/Modelfile.qwen3-27b`               | `qwen3-27b`            | `qwen3.8:27b`      | Default primary        |
| `config/ollama/Modelfile.qwen3-27b-thinking`     | `qwen3-27b-thinking`   | `qwen3.8:27b`      | Same base, thinking on |
| `config/ollama/Modelfile.coder-7b`                | `coder-7b`             | `qwen2.5-coder:7b` | Secondary, full VRAM   |

The v0.2.x legacy recipes (`Modelfile.coder-14b` and
`Modelfile.coder-32b`) were removed in v0.3.1. The 14B was superseded
by the new primary; the 32B was a LEGACY slot since v0.3.0. Operators
who still want either can `ollama pull <base>` and
`ollama create <alias> -f` against a hand-written Modelfile.

All recipes inherit the system prompt `config/ollama/PROMPT.coding.md` so
behaviour is consistent across sizes.

## Sampling defaults

For coding we want low temperature (deterministic-ish) and top-p clamped
narrow. Both v0.3.x Modelfiles (`qwen3-27b` and `qwen3-27b-thinking`)
use:

    temperature        0.2     # 0.6 for the thinking variant
    top_p              0.95
    top_k              40
    repeat_penalty     1.05    # 1.0 for the thinking variant
    num_ctx            65536   # 8192 for v0.2.x recipes

The `qwen3-27b-thinking` variant loosens `temperature` to 0.6 and
`repeat_penalty` to 1.0 because thinking traces repeat common
connectors; tighter penalties truncate the chain-of-thought. The
primary (`qwen3-27b`) stays at 0.2 / 1.05 for inline completions where
determinism matters.

`num_ctx 65536` (64K) is the v0.3.x default. It is the minimum the
Hermes Agent client expects (see `docs/06-networking-and-security.md` →
*Hermes Agent*); the Qwen 3.8 native context is 256K, but a 64K KV
cache already takes ~3 GB of RAM with a 27B partial-offload, and
operators pushing beyond 64K are likely to OOM. Operators can override
`num_ctx` per request via the API. The server-side
`OLLAMA_CONTEXT_LENGTH` env still applies to new loads.

For brainstorming / doc writing the same Modelfile can be invoked with
override parameters via the API. Defaults are conservative.

## Quantisation trade-offs (operator reference)

The Q4_K_M tag is the default in `scripts/pull-models.sh primary` because
it is the right sweet spot for the RTX 3060 (12 GB VRAM) + 32 GB RAM
reference box. Other quant tags of `qwen3.8:27b` exist on the Ollama
library for operators with different hardware. Pick by available RAM
and how much you want fully on GPU, not by the quality delta alone —
the quality differences across the table are < 5 %, and partial-offload
speed depends on how much fits in VRAM and on disk throughput, not on
the quant.

| Quant       | Approx weight | 12 GB VRAM?                       | 32 GB RAM comfortable? | Quality vs FP16 |
|-------------|---------------|-----------------------------------|------------------------|-----------------|
| **Q4_K_M**  | ~18 GB        | Partial offload (~6 GB to CPU)    | Yes                    | ~95 %           |
| Q5_K_M      | ~21 GB        | Partial offload (~9 GB to CPU)    | Tight                  | ~96.5 %         |
| Q6_K        | ~24 GB        | All offloaded (no VRAM use)        | Tight                  | ~98 %           |
| Q8_0        | ~32 GB        | All offloaded                     | Very tight             | ~99 %           |

The Ollama library also lists MLX and BF16 quant tags; those only
apply to Apple Silicon and are explicitly out of scope for guasimo v1
(`docs/01-architecture.md` → *What this architecture explicitly
excludes*).

To switch the default quant, edit the `[primary]` entry in
`scripts/pull-models.sh` and `scripts/benchmark.sh` to point at the
desired tag (e.g. `qwen3.8:27b-q5_K_M`), and update the `FROM` line
in `config/ollama/Modelfile.qwen3-27b` (and the thinking variant) to
match. Re-run `scripts/install-aliases.sh` to recreate the alias
against the new base. The disk-budget estimation in `pull-models.sh`
will pick up the new tag via the `*qwen3.8*` case branch as long as
the tag substring still contains `qwen3.8`.

Hardware targets (rule-of-thumb; validate on your own box):

- **12 GB VRAM + 32 GB RAM** (guasimo reference): Q4_K_M. ~3-5 gen
  tok/s in steady state; this is the default in v0.3.0.
- **16 GB VRAM + 32 GB RAM**: Q5_K_M fits with a small VRAM slice;
  ~25 % more weight, marginal quality gain. Worth it for inline
  completions where the partial-offload hits harder.
- **24 GB VRAM + 48 GB RAM**: Q6_K fits fully on GPU; ~33 % more
  weight than Q4, ~3 % quality gain. Best per-GB-of-quality choice
  for an upgrade path.
- **24 GB VRAM + 64 GB RAM**: Q8_0 fits fully on GPU; ~80 % more
  weight than Q4, marginal quality delta at the inference temperature
  this Modelfile uses. Skip unless the operator is sensitive to
  quantisation noise on long context.



1. Drop the GGUF into `/bulk/models/<vendor>-<name>-<size>-<quant>.gguf`.
2. Add a `Modelfile.<name>` in `config/ollama/` that points at it.
3. `ollama create <name> -f config/ollama/Modelfile.<name>`.
4. Verify with `./scripts/benchmark.sh <name>`.
5. Document in `docs/04-models.md` (this file) under a new heading.

This is intentionally a 5-step process; the friction prevents stale
models from accumulating.

## How to add a new model

1. Drop the GGUF into `/bulk/models/<vendor>-<name>-<size>-<quant>.gguf`.
2. Add a `Modelfile.<name>` in `config/ollama/` that points at it.
3. `ollama create <name> -f config/ollama/Modelfile.<name>`.
   (`scripts/install-aliases.sh` will pick up the new Modelfile
   automatically on the next `pull-models.sh` run; re-running it
   standalone also recreates the alias.)
4. Verify with `./scripts/benchmark.sh <name>`.
5. Document in `docs/04-models.md` (this file) under a new heading.

## What we explicitly do not pull

- Any model with a non-open licence.
- Any "uncensored" fine-tune — for code use, the standard instruct
  response is correct.
- Models > 70 B. Out of the box's reach.
- Models without a GGUF quantisation available — building one ourselves
  is possible but out of scope for v1.