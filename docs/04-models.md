# 04 — Models

## Selection criteria

For a coding LLM on a 32 GB CPU box we want:

1. **Strong on real programming tasks**, not just chat.
2. **Quantisation-friendly**: Q4_K_M should preserve ≥ 95 % of FP16 quality.
3. **Open licence** (Apache-2.0 / MIT / etc.) so we can self-host freely.
4. **Active maintenance** in 2025–2026, with regular code-specialised
   fine-tunes.

## Primary model — Ornith-1.5-9B (Q6_K)

| Attribute         | Value                                       |
|-------------------|---------------------------------------------|
| Family            | Ornith 1.5                                  |
| Size              | 9 B parameters (dense, hybrid attention)    |
| Quantisation      | Q6_K (6-bit, K-quant)                       |
| Disk              | ~7.4 GB                                     |
| RAM at inference  | full VRAM (12 GB card), weights + 64K KV cache |
| Context window    | 128 K (we use 8–64 K)                       |
| Modality          | Text                                        |
| Thinking          | Off by default; per-request toggle          |
| Licence           | Apache-2.0                                  |
| Ollama tag        | — (manual GGUF drop, not a library tag)     |
| Modelfile alias   | `ornith-9b` (auto-created by `install-aliases.sh`) |
| Why               | Flat throughput across 8K→64K, full VRAM, fast daily driver |

This is the daily driver as of v0.4.0. It replaces Qwen3.8-27B-Instruct
(`qwen3-27b`) as the primary. Use it for code completion, refactor,
review, explanation, docstring writing, and language translation between
Go ↔ C#.

The win is **contextflatness**, not raw flops. Ornith 1.5 uses hybrid
attention — full attention on the early layers, a KV-cache-friendly
attention on the rest — so the KV cache stays small and the model holds
its generation rate as context grows instead of collapsing like a dense
model. On the reference box it is ~**37.9 gen tok/s @ 8K → ~38.0 @ 64K**
(**+0.2 %**, i.e. flat), full VRAM. That is the opposite of the cliff
the previous primaries showed at 64K.

### Tradeoff: quality vs the 27B secondary

A 9B is not a 27B. On hard multi-step refactors the Qwen3.8-27B
(`secondary`, kept below) still lands better answers, at the cost of
partial-offload latency. The split is deliberate:

- **Ornith 9B (`primary`)** — the day-to-day loop. Fast, flat, idiomatic
  Go/C#, full VRAM. Inline completion, quick review, chat.
- **Qwen3.8-27B (`secondary`)** — agentic depth. Deep review/refactor at
  64K+ where quality beats latency.

This is the documented cost of choosing throughput for the loop. Operators
who want agentic depth can select `secondary`; fast chat stays on `primary`.

### Measured throughput on the reference box (2026-08-25)

`num_ctx` is per-request, so the same box serves both uses at once — a
low-context client (editor/chat) gets fast completions while a
high-context client (agent) stays full-depth. Measured with a Go prompt,
`num_predict` ~300, warm load, stock quantisations unless noted:

| Model                     | `num_ctx` | gen tok/s | prompt tok/s | VRAM | Notes |
|---------------------------|-----------|-----------|--------------|------|-------|
| **`ornith-9b` (Q6_K)**    | 8K        | **37.91** | —            | full | **primary** — fast default |
| **`ornith-9b` (Q6_K)**    | 64K       | **37.98** | —            | full | flat — 0 % cliff |
| `ornith-9b` (AD Q8_0)     | 64K       | 35.58     | —            | full | AD requant, ~6 % slower, slightly higher quality |
| `ornith-35b` (MoE A3B)    | 8K        | 31.15     | —            | ~    | Ollama offload, best Go quality |
| `ornith-35b` (MoE A3B)    | 64K       | 29.16     | —            | spill| −6.4 % drop, KV cache out of VRAM |
| `ornith-35b` `--cpu-moe`  | 8K / 64K  | 23.5      | 25.6 / 37.7 | full | llama.cpp, experts in RAM, 0 % drop |
| `coder-14b`               | 8192      | ~32.61    | —            | full | legacy v0.2.x primary |
| `coder-14b`               | 64K       | 7.64      | —            | spill| −77 % — the cliff in full view |
| `qwen3-27b`               | 64K       | ~4        | ~35          | spill| agentic depth / long context |
| `unsloth-27b` (UD-Q3_K_XL)| 8K / 64K  | 5.44 / 3.23 | —         | spill| −41 % — dynamic-quant experiment |

The cliff is the KV cache, not the model: `coder-14b` goes from ~33 t/s
at 8K ctx to ~7.6 t/s at 64K ctx because the 64K cache no longer fits in
12 GB VRAM. Ornith 1.5 sidesteps it with hybrid attention: the 9B holds
~38 t/s at both 8K and 64K. Rule of thumb — **pick the model by task, and
don't raise `num_ctx` beyond what the task's files actually need.**

### Validated pull (Ubuntu 26.04 + RTX 3060)

Ornith 1.5 is not an Ollama library tag, so it is a **manual GGUF drop**,
not a `pull-models.sh` pull. See *How to add a new model* below; the
Modelfile is `config/ollama/Modelfile.ornith-9b`. Pull validation for
the prior primaries is preserved in git history (`assets/` of v0.2.x and
the v0.3.x `qwen3.8:27b` run). From the v0.2.2 reference run on the same
box: `./scripts/healthcheck.sh` → **8 ok / 0 fail**.

## Secondary model — Qwen3.8-27B-Instruct (Q4_K_M)

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
| Why               | Agentic depth, multimodal, 256K context     |

This was the v0.3.x primary and is demoted to **secondary** in v0.4.0 to
make room for the flat Ornith 9B. Keep it for deep agentic work: multi-step
refactor, code review with audit trail, 64K+ context, and vision-language
input where the 9B falls short.

### Tradeoff: partial offload on the RTX 3060 (12 GB)

The 18 GB Q4_K_M does not fit fully in 12 GB of VRAM. Ollama keeps the
layers that fit on the GPU and offloads the rest to CPU/RAM. Expect
**~4 gen tok/s with a 64K `num_ctx` in steady state** (validated on the
reference box, 2026-08-23, `num_ctx 65536`, warm load; cold load is
lower while the model streams in). Dropping `num_ctx` to 4096 does not
materially change generation rate (~5 t/s), but Hermes Agent's 64K
context floor is the number that matters. This is the documented cost of
agentic coding plus multimodal input on the same single-user box.

## Thinking variant — Qwen3.8-27B (reasoning on)

Same `qwen3.8:27b` base as the secondary, with a system prompt that
forces step-by-step reasoning. Alias `qwen3-27b-thinking` from
`config/ollama/Modelfile.qwen3-27b-thinking`; auto-created by
`scripts/install-aliases.sh` after the secondary base is in the local
library. No extra pull weight — it reuses the secondary download.

Use for code review, multi-step refactor, and hard bug analysis where
the audit trail of `<think>…</think>` blocks is worth the latency.
Default chat and IDE inline completions should still use the non-thinking
models (`ornith-9b` primary, `qwen3-27b` secondary) for speed.

Reasoning depth is per-request via the `reasoning_effort` parameter
(higher = more tokens in the trace). Qwen 3.8 supports the standard
`/think` and `/no_think` prompt toggles as well.

## Ornith 1.5 family — the MoE and MTP angle (operator note)

Beyond the 9B primary, Ornith 1.5 has a 35B-A3B **mixture-of-experts**
build: 35 B of weights, only ~3 B active per token (`n_expert 256`,
`n_expert_used 8`, arch `qwen35moe`). The idea was to squeeze it with
speculative decoding. Two findings, both measured 2026-08-25:

1. **`--cpu-moe` flattens context, at a speed cost.** Running via
   llama.cpp with `--cpu-moe` (experts pinned in RAM, dense layers +
   attention offloaded to VRAM) yields **23.5 gen tok/s @ 8K → 23.5 @
   64K (0.0 % drop)** — literally flat — vs Ollama's 31.15 → 29.16
   (−6.4 %). The trade: ~25 % slower peak, because moving the experts
   over PCIe per token is constant overhead. The win is *predictability*
   and *no cliff*, at the cost of raw speed.

2. **MTP does not apply.** Native multi-token prediction
   (`--spec-type draft-mtp`) requires a **Qwen3-Next** architecture
   (`qwen3next`, with a physical MTP/NextN block, `n_layer_nextn > 0`).
   This build is **`qwen35moe`** — no MTP head exists in the weights, so
   `failed to create MTP context` is the expected, correct failure.
   n-gram speculative decoding (`ngram-map-k4v`) runs but only gains
   ~7 % on a cold prompt (25.1 t/s) because there is no repeated text to
   draft from — speculative decoding shines on repetition inside a
   conversation, not a cold 300-token request.

**Verdict:** the 35B stays the *quality* path (best idiomatic Go,
`%w`-wrapped errors, doc comments) but does not displace the 9B on
throughput. Ornith 9B Q6_K is the primary; the 35B is an optional manual
drop for deep refactors.

## How to switch the model

The primary (`ornith-9b`) is what Open WebUI, the Ollama OpenAI-compat
API, and the healthcheck all point at by default. Switching is a matter
of *which endpoint you talk to*, not a global re-point:

| Model                        | Talk to                | How to start it                                    |
|------------------------------|------------------------|----------------------------------------------------|
| **Ornith 9B** (primary)      | Ollama `:11434`        | default — `./scripts/pull-models.sh primary`       |
| **Ornith 35B** (quality)     | llama-server `:8081`   | `./scripts/serve-35b.sh`                           |
| **Qwen3-27B** (agentic/multimodal) | Ollama `:11434`  | `./scripts/pull-models.sh secondary`               |
| **Coder 7B** (fast fallback)  | Ollama `:11434`        | `./scripts/pull-models.sh secondary-fast`          |

### Point Open WebUI at the 35B

Open WebUI speaks the Ollama API by default. The 35B is *not* registered
in Ollama — `serve-35b.sh` exposes it directly from `llama-server` as an
OpenAI-compatible endpoint (`/v1`). Point at it via **OpenAI connection**
in Open WebUI's admin settings:

1. `./scripts/serve-35b.sh` — runs foreground on `127.0.0.1:8081`,
   model alias `ornith-35b` (server prints the alias on startup).
2. In Open WebUI → Admin → Settings → **Connections → OpenAI API**:
   - Base URL: `http://127.0.0.1:8081/v1`
   - API key: (anything — `serve-35b.sh` binds no auth by default)
   - Model: `ornith-35b`
3. Save. The 35B now appears as a selectable model in the chat picker
   alongside the Ollama-served primary.

Switching back is just selecting `ornith-9b` in the same picker — no
reconfiguration. Both servers stay up independently.

### When to use which

- **Everyday coding / fastest iteration** → Ornith 9B (38 tok/s flat).
- **Deep refactors, tricky concurrency, idiomatic-correct Go** → 35B
  (accept ~23.5 tok/s for the best local code quality).
- **Multimodal / thinking / agentic depth** → Qwen3-27B (slow @ 64K).


## Optional — Qwen2.5-Coder-7B-Instruct (`secondary-fast`)

| Attribute         | Value                                       |
|-------------------|---------------------------------------------|
| Size              | 7 B parameters                              |
| Quantisation      | Q4_K_M                                      |
| Disk              | ~5 GB                                       |
| RAM               | ~6 GB                                       |
| Licence           | Apache-2.0                                  |
| Why               | Fastest responses; tiny footprint           |

Kept as a low-latency fallback. On the current box the Ornith 9B primary
is just as fast and more capable, so this is mostly a compatibility slot
for RAM-constrained boxes.

## Optional — Gemma 4 12B (`gemma`)

| Attribute         | Value                                       |
|-------------------|---------------------------------------------|
| Ollama tag        | `gemma4:12b`                                |
| Nickname          | `./scripts/pull-models.sh gemma`            |
| Disk              | ~8 GB                                       |
| Self-host 3060    | Yes at Q4; 8–16K ctx comfortable; 64K tight |
| Licence           | Apache-2.0 (Gemma 4)                        |
| Why               | Strong tool-calling / agent UX; multimodal  |

Not the daily coding driver (Ornith/Qwen still win on pure code), but a
good alternate for Hermes Agent and Open WebUI tool workflows.

## Optional — DeepSeek-Coder-V2-Lite (`deepseek`)

| Attribute         | Value                                       |
|-------------------|---------------------------------------------|
| Ollama tag        | `deepseek-coder-v2:lite` (~8.9 GB, MoE)     |
| Nickname          | `./scripts/pull-models.sh deepseek`         |
| Self-host 3060    | Yes                                         |
| Licence           | DeepSeek licence (open weights; check card) |
| Why               | Strong coding backup; different training    |

Pull when you want a second opinion vs Qwen/Ornith on hard refactors.
Alias `deepseek-lite` accepted by the pull/benchmark scripts.

## Legacy — Qwen2.5-Coder 14B / 32B

The 14B was the v0.2.x primary (superseded by Qwen3.8 then Ornith); the
32B was LEGACY since v0.3.0 (superseded by the 27B). Neither is pulled by
`pull-models.sh`. Their Modelfiles were removed in v0.3.1. Operators who
still want either can `ollama pull <base>` and hand-write a Modelfile.

## Why Ornith 1.5 (not Qwen / Llama / Mistral / …)

| Model family              | Coding (self-host focus) | Self-host on RTX 3060 (12 GB)? | Verdict |
|---------------------------|--------------------------|--------------------------------|---------|
| **Ornith-1.5-9B**         | High (idiomatic Go/C#)   | Yes, full VRAM, flat 8K→64K     | **Primary** (v0.4.0+) |
| Qwen3.8-27B               | High (agentic, multimodal) | Partial offload (Q4 @ 64K)  | Secondary (was primary v0.3.x) |
| Ornith-1.5-35B-A3B (MoE)  | Highest (best Go)        | `--cpu-moe` or spill            | Optional quality path |
| Qwen2.5-Coder-14B-Instruct| High                     | Yes (Q4 @ 8K)                   | Legacy (v0.2.x) |
| Qwen2.5-Coder-7B-Instruct | High / fast              | Yes                             | Optional fast fallback |
| Qwen2.5-Coder-32B-Instruct| High                     | Partial offload (heavy)         | Legacy (not pulled) |
| Gemma 4 12B               | High (agents / tools)    | Yes (64K tight)                 | Optional `gemma` |
| DeepSeek-Coder-V2-Lite    | Medium-high              | Yes                             | Optional `deepseek` |
| Qwen3-Coder-30B-A3B (MoE) | High (3.3B active)       | Partial offload                 | Considered, not picked |
| Llama-3.1-8B-Instruct     | Medium                   | Yes                             | Niche |
| Mistral-Codestral-22B     | High                     | Yes, tight                      | Considered |
| CodeLlama-70B             | High                     | No (needs ≥ 40 GB)              | Excluded |
| Bonsai (1-bit)            | Weak on code             | Tiny, Ollama/Q1_0 friction      | Out of scope |

Ornith 1.5 takes the primary slot in v0.4.0 because its hybrid attention
delivers **flat throughput 8K→64K** — the single biggest pain point on
self-hosted coding boxes — with idiomatic code output, at a size that
fits 12 GB VRAM comfortably. The Qwen 3.8 generation stays as `secondary`
for agentic/multimodal depth. Both the MoE 35B (quality) and the
Qwen3.8-27B (depth) were close runners-up and are kept as secondary /
optional slots rather than dropped.

### Unsloth dynamic quants (operator note)

For the v0.3.x primary there is an alternative GGUF set —
[`unsloth/Qwen3.8-27B-GGUF`](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/tree/main) —
with **Unsloth Dynamic (UD) quantisations** that improve on the stock
K-quants for this model. The `UD-*` tags re-measure the imatrix against
the actual weights, which can recover a little quality at the same file
size, or squeeze the same quality into a smaller file. Measured on the
reference box (2026-08-25), `UD-Q3_K_XL` ran 5.44 → 3.23 gen tok/s
(−41 %) — a worse cliff than stock, so UD was not adopted. Relevant
sizes (27B dense):

| Tag             | Weight  | Notes vs stock Q4_K_M (~18 GB)               |
|-----------------|---------|----------------------------------------------|
| `UD-IQ3_XXS`    | ~10.9 GB| smallest; biggest quality spread, skip       |
| `UD-IQ4_XS`     | ~14.3 GB| lighter than Q4_K_M, close quality           |
| `UD-Q4_K_M`     | ~16.5 GB| slightly smaller than stock, similar quality |
| `UD-Q3_K_XL`    | ~13.2 GB| sweet spot only if RAM/VRAM is tight         |

Note: these are manual GGUF drops (`FROM /bulk/models/...gguf`), not
Ollama library tags, so they follow the "How to add a new model" flow
below rather than `pull-models.sh`. There is also a vision mmproj
(`mmproj-BF16.gguf`) in the repo if the multimodal path is wanted with
a manual drop.

## Ornith 1.5 quantisation trade-off (operator reference)

The primary is Q6_K rather than the v0.3.x Q4_K_M because Ornith 9B is
small enough that Q6_K still fits 12 GB VRAM at 64K ctx while retaining
~98 % of FP16 quality. The AD (AtomicChat/DeepReinforce) requant —
`Ornith-1.5-9B-AD-Q8_0-Q6_K.gguf`, alias `ornith-9b-ad` — squeezes a
little more quality from the static-sparse experts at the cost of ~1.5 GB
and ~6 % speed; it exists as `Modelfile.ornith-9b-ad` for quality-first
operators. Q6_K stays the default.

| Quant       | Approx weight | 12 GB VRAM (9B)?  | Quality vs FP16 |
|-------------|---------------|-------------------|-----------------|
| Q4_K_M      | ~5.4 GB       | Yes               | ~95 %           |
| **Q6_K**    | ~7.4 GB       | Yes (primary)     | ~98 %           |
| Q8_0        | ~8.6 GB       | Yes, 64K tight    | ~99 %           |
| AD Q8_0_Q6_K| ~8.6 GB       | Yes, 64K tight    | ~99 % + sparse  |

To switch the default quant, edit the `[primary]` entry in
`scripts/pull-models.sh` and `scripts/benchmark.sh`, and update the `FROM`
line in `config/ollama/Modelfile.ornith-9b` to match. Re-run
`scripts/install-aliases.sh` to recreate the alias.

## Modelfiles

Each named model is a `Modelfile` in `config/ollama/`. A Modelfile specifies
the base (a GGUF path or a library tag), the chat template, the system prompt,
and sampling defaults. `scripts/install-aliases.sh` applies the recipes to the
running Ollama after each `pull-models.sh`; aliases are created with the
Modelfile basename minus the `Modelfile.` prefix (e.g. `Modelfile.ornith-9b` →
alias `ornith-9b`).

Recipes in this repo (v0.4.0+):

| File                                              | Alias                  | Base                                   | Notes                    |
|---------------------------------------------------|------------------------|----------------------------------------|--------------------------|
| `config/ollama/Modelfile.ornith-9b`               | `ornith-9b`            | `/bulk/models/Ornith-1.5-9B-Q6_K.gguf` | **Primary** (manual drop) |
| `config/ollama/Modelfile.ornith-9b-ad`            | `ornith-9b-ad`         | `/bulk/models/Ornith-1.5-9B-AD-Q8_0-Q6_K.gguf` | Primary AD requant (manual drop) |
| `config/ollama/Modelfile.qwen3-27b`               | `qwen3-27b`            | `qwen3.8:27b`                          | Secondary (agentic depth) |
| `config/ollama/Modelfile.qwen3-27b-thinking`      | `qwen3-27b-thinking`   | `qwen3.8:27b`                          | Same base, thinking on |
| `config/ollama/Modelfile.coder-7b`                | `coder-7b`             | `qwen2.5-coder:7b`                     | Low-latency fallback |

The `FROM` for Ornith is a **local GGUF path** (manual drop), which
`install-aliases.sh` handles by checking the file exists on disk rather
than matching a library tag. The v0.2.x legacy recipes (`Modelfile.coder-14b`
and `Modelfile.coder-32b`) were removed in v0.3.1.

All recipes inherit the system prompt `config/ollama/PROMPT.coding.md` so
behaviour is consistent across sizes.

## Sampling defaults

For coding we want low temperature (deterministic-ish) and top-p clamped
narrow. The v0.4.x Modelfiles use:

    temperature        0.2
    top_p              0.95
    top_k              40
    repeat_penalty     1.05
    num_ctx            65536   # 64K

The `qwen3-27b-thinking` variant loosens `temperature` to 0.6 and
`repeat_penalty` to 1.0 because thinking traces repeat common connectors;
tighter penalties truncate the chain-of-thought. The non-thinking models
stay at 0.2 / 1.05 for inline completions where determinism matters.

`num_ctx 65536` (64K) is the v0.3.x+ default. It is the minimum the Hermes
Agent client expects (see `docs/06-networking-and-security.md` → *Hermes
Agent*). The Ornith 1.5 KV cache stays small enough at 64K to remain in
VRAM on the 12 GB card — that is the whole point of the hybrid attention.
The Qwen 3.8 native context is 256K, but a 64K KV cache already takes
~3 GB of RAM with a 27B partial-offload, and operators pushing beyond 64K
are likely to OOM. Operators can override `num_ctx` per request via the
API. The server-side `OLLAMA_CONTEXT_LENGTH` env still applies to new loads.

For brainstorming / doc writing the same Modelfile can be invoked with
override parameters via the API. Defaults are conservative.

## How to add a new model

1. Drop the GGUF into `/bulk/models/<vendor>-<name>-<size>-<quant>.gguf`.
2. Add a `Modelfile.<name>` in `config/ollama/` that points at it.
3. `ollama create <name> -f config/ollama/Modelfile.<name>`.
   (`scripts/install-aliases.sh` will pick up the new Modelfile
   automatically on the next `pull-models.sh` run; re-running it
   standalone also recreates the alias.)
4. Verify with `./scripts/benchmark.sh <name>`.
5. Document in `docs/04-models.md` (this file) under a new heading.

This is intentionally a 5-step process; the friction prevents stale
models from accumulating.

## What we explicitly do not pull

- Any model with a non-open licence.
- Any "uncensored" fine-tune — for code use, the standard instruct
  response is correct.
- Models > 70 B. Out of the box's reach.
- Models without a GGUF quantisation available — building one ourselves
  is possible but out of scope for v1.
