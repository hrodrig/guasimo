# 01 — Architecture

## Goal

Run a self-hosted coding LLM on an Ubuntu 26.04 workstation. The model must
be reachable from a browser on the same LAN, must expose an OpenAI-compatible
HTTP API for IDE plugins (Continue, Cline, etc.), and must survive a reboot
without operator intervention.

## Component diagram

    ┌──────────────┐     HTTPS       ┌────────────────┐
    │  Browser /   │ ──────────────▶ │  Open WebUI    │
    │  IDE plugin  │  (LAN or local) │  (systemd)     │
    └──────────────┘                 └────────────────┘
                                              │
                                              │ HTTP (loopback)
                                              ▼
                                     ┌────────────────┐
                                     │    Ollama      │
                                     │  (systemd)     │
                                     │  OpenAI API +  │
                                     │  /api/chat     │
                                     └────────────────┘
                                              │
                                              │ HTTP (loopback)
                                              ▼
                                     ┌────────────────┐
                                     │  llama.cpp     │
                                     │  (systemd)     │
                                     │  server mode   │
                                     └────────────────┘
                                              │
                                              ▼
                                          GGUF blob on
                                       NVMe (hot) or SSD

## Responsibilities

| Component       | Responsibility                                              | Does NOT do                         |
|-----------------|-------------------------------------------------------------|-------------------------------------|
| llama.cpp       | Tensor maths, KV cache, sampling, prompt eval               | API, model discovery                |
| Ollama         | Model lifecycle, Modelfiles, OpenAI-compatible API surface  | Tokenisation tuning                 |
| Open WebUI     | Chat history, RAG over uploaded files, multimodal input (image paste, file upload)  | Inference |
| nginx           | TLS termination, single entry point on 443                  | Auth (delegated to Open WebUI)      |
| systemd         | Process supervision, restart policy, dependency ordering    | Config management                   |

The v0.3.0 primary model (`qwen3.8:27b`, vision-language) adds a
multimodal path: image inputs from the browser reach Open WebUI,
which forwards them to Ollama, which in turn hands them to the GGUF
model. The data flow on the right of the diagram is unchanged;
multimodal is an additional content type, not a new layer.

## Data flow (chat completion request)

1. Browser POSTs `/api/chat` to Open WebUI (authenticated session).
2. Open WebUI rewrites the request as an OpenAI-style payload to Ollama.
3. Ollama resolves the requested model name to a Modelfile + GGUF tag.
4. Ollama ensures the model is loaded; if not, asks llama.cpp to load it.
5. llama.cpp streams tokens back; Ollama re-streams to Open WebUI; Open WebUI
   streams to the browser via SSE.

## Why three layers

A single-layer approach (one of: LM Studio desktop app, raw llama.cpp CLI,
custom Python wrapper) fails one of the three real requirements:

- **IDE integration** needs an OpenAI-compatible HTTP API. Raw llama.cpp exposes
  a different API surface; LM Studio is desktop-only.
- **Multi-session chat UX** needs a stateful web app. llama.cpp is stateless.
- **Process supervision** needs a service manager. A tmux session is not enough.

Ollama is the smallest layer that gives us a stable HTTP API and a model
catalog. Open WebUI is the smallest web layer that gives us a real chat UX.
llama.cpp is the smallest inference layer that lets us tune build flags for
the actual CPU in the box.

## Failure isolation

- If Open WebUI is down: `curl http://localhost:11434/api/tags` should still
  answer. Ollama is independent.
- If Ollama is down: no chat, but the box still boots and SSH still works.
  This is the contract — never couple systemd ordering so tightly that one
  failure takes the others with it.
- If llama.cpp crashes: Ollama returns 5xx; Open WebUI shows a clear error.
  systemd restarts llama.cpp; Ollama reconnects on next request.

## What this architecture explicitly excludes

- **CPU-only as default**. The RTX 3060 is the primary target. CPU is the
  documented fallback if the driver is broken or the GPU is busy.
- **Apple Silicon / AMD ROCM / Intel Arc**: out of scope for v1. The build
  matrix only handles NVIDIA + AVX2 CPU.
- **No RAG database** (no vector store) in v1. Open WebUI ships with simple
  file-upload RAG. That's enough until it isn't.
- **No model fine-tuning pipeline**. Models come pre-trained from upstream.
- **No multi-tenant auth.** Single user on the LAN. Add SSO if/when the box
  becomes multi-tenant.