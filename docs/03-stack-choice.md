# 03 — Stack choice

## Decision matrix

We considered four end-to-end stacks. All four can deliver a local coding LLM.
The differences are operational, not functional.

| Stack                              | API surface   | Process model     | Build flexibility | Verdict       |
|------------------------------------|---------------|-------------------|-------------------|---------------|
| **llama.cpp + Ollama + Open WebUI** | OpenAI-compat | 3 systemd units   | Build llama.cpp per box | **Chosen** |
| LM Studio (desktop)                | OpenAI-compat | One desktop app   | None (binary)      | Rejected     |
| vLLM standalone                    | OpenAI-compat | One process       | Python wheel      | Rejected     |
| Ollama alone (no web UI)           | OpenAI-compat | One systemd unit  | Prebuilt binary    | Insufficient |

## Why llama.cpp + Ollama + Open WebUI

### llama.cpp

- The reference CPU inference engine for GGUF. Used by everyone from
  Hugging Face's `text-generation-inference` to consumer apps.
- Builds from source on the exact CPU, so we get the matching SIMD path
  (AVX2 vs AVX-512 matters ~15–25 % at the token level).
- Server mode is mature: HTTP, SSE streaming, slot-based concurrency.
- Plays well with Ollama as a backend (`OLLAMA_LLAMA_SERVER` override) or
  standalone.

### Ollama

- Provides a stable, versioned OpenAI-compatible API on top of llama.cpp
  (or its own backend, our choice).
- Modelfile format is a thin, Git-trackable recipe layer over GGUF blobs.
  This is what makes "add a new model" a single file + a pull command.
- Active project, fast release cadence, broadly supported by IDE plugins.
- Optional: in v1 we point Ollama at our locally-built llama.cpp binary
  (`OLLAMA_LLAMA_SERVER=/opt/ia-lab/llama-server`) so we get one build,
  not two.

### Open WebUI

- State-of-the-art local chat UX. Multi-conversation, file upload, image
  paste, model picker, system prompt per conversation.
- Talks to Ollama via its native API; no plugin layer needed.
- Single-user mode by default. Multi-user is opt-in via env vars; not used
  in v1.
- Maintained; small enough to run from pip or container.

## Why not LM Studio

LM Studio is excellent for a single developer playing with models. It is not
suitable for this project because:

- It is a desktop app, not a service. Rebooting the box does not bring it
  back without login.
- No command-line surface for "pull this model, restart, hand me the
  OpenAI-compatible URL".
- No systemd unit. No headless mode.
- The binary is closed-source; we cannot audit or tune it for our CPU.

We get none of those problems with the chosen stack.

## Why not vLLM

vLLM is the right answer for a production server serving many users. It is
overkill for a single-user workstation:

- Requires Python 3.10+, a CUDA toolkit, and a specific wheel matrix per
  PyTorch release. CPU support exists but is not the project's focus.
- The PagedAttention scheduler is a huge win at high concurrency and a
  small win at concurrency 1.
- We would still need Open WebUI (or similar) for the chat UX. vLLM gives
  no advantage over llama.cpp + Ollama for this workload.

## Why not Ollama alone

Ollama is enough for IDE integration (its `/v1/chat/completions` works with
Continue, Cline, etc.). It is not enough for the chat UX we want; Ollama's
built-in web UI is functional but minimal compared to Open WebUI. Adding
Open WebUI costs one extra systemd unit and gets us the chat UX we want.

## Layer integration

Ollama normally bundles its own llama.cpp. We override this so the whole
stack uses the single binary we built in `deploy/install.sh`:

    Environment="OLLAMA_LLAMA_SERVER=/opt/ia-lab/llama-server"

This means: one CPU-tuned build, no second inference engine to keep in
sync, and the model behaviour is uniform between direct llama.cpp calls and
Ollama-served calls.

## Version pinning policy

- llama.cpp: track the latest tagged release at install time; pin via the
  git SHA written into `deploy/install.sh`. Upgrade deliberately.
- Ollama: track Ubuntu-distributed `.deb` until that lags more than one
  minor; fall back to upstream install script.
- Open WebUI: track upstream `pip install`. Pin in `requirements.txt` for
  reproducible upgrades.

Each component is upgraded by editing one variable and re-running
`deploy/install.sh`.