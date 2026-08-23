# 02 — Hardware decisions

## Detected target

| Component | Spec                        | Notes                                      |
|-----------|-----------------------------|--------------------------------------------|
| CPU       | Intel i5-10xxx (Comet Lake-S, 6c) | Z590 board; AVX2 only — AVX-512 fused off |
| GPU       | NVIDIA GA106 RTX 3060 LHR (12 GB) | CUDA primary inference target        |
| RAM       | 32 GB DDR4                  | 28 GB usable after OS (~4 GB)              |
| SSD       | 2 TB SATA/NVMe              | Cold storage for downloaded blobs          |
| NVMe      | 500 GB                      | Hot: runtime, model in use, logs           |
| OS        | Ubuntu 26.04                | New kernel, modern GCC, CUDA 12.x          |

The GPU is present and is the **primary** inference target. `install.sh`
detects the hardware via `lspci` (works before the proprietary driver is
loaded) and via `nvidia-smi` (runtime confirmation). CPU remains a fallback
for when the GPU is busy or unavailable. AMD and Intel Arc are explicitly
out of scope.

## Why GPU-primary, CPU as fallback

Two reasons.

**One**: the box has a 12 GB RTX 3060. The primary model (14 B Q4_K_M) is
~9 GB on disk and ~10 GB resident (weights + KV cache at 8 K context). It
fits in 12 GB of VRAM with ~2 GB of headroom, which means fully offloaded
inference and ~3-5× the tokens/s of pure CPU on this i5. There is no reason
to leave the GPU idle.

**Two**: keeping CPU as a working fallback means the stack still functions
if the NVIDIA driver breaks after a kernel upgrade, the GPU is busy with
another job, or the user wants to test a 32 B parameter model with partial
CPU offload. The architecture is GPU-first, not GPU-only.

For v1 we stay at 14 B / Q4 because that is the sweet spot for both GPU
fit and code quality. Going past that needs measured VRAM, not guesses.

## RAM budget (32 GB system)

| Allocation                                          | GB     |
|-----------------------------------------------------|--------|
| Ubuntu 26.04 + desktop (if installed)               | 2–4    |
| llama.cpp + Ollama (resident model, 27B Q4 partial) | ~20–22 |
| Open WebUI (Python + Node, modest)                  | 0.5    |
| nginx                                               | 0.05   |
| Headroom for browser, IDE, kernel cache             | 5–9    |

The 27B partial offload in v0.3.0 raises the resident model weight
from ~10 GB (v0.2.x 14B, full VRAM) to ~20–22 GB (27B split between
VRAM and RAM). With a 32K `num_ctx` the KV cache adds ~1–2 GB
on top. Total at idle sits around 24–27 GB; under load with a long
context it can climb to ~29 GB. We never enable swap beyond the
Ubuntu default — OOM is the correct signal when an operator pushes
`num_ctx` past the available headroom.

## VRAM math (RTX 3060, 12 GB)

| Model size (B params) | Q4_K_M weight | Q4 KV cache (8K ctx) | Total fit | Fits 12 GB? | Notes                                            |
|-----------------------|---------------|----------------------|-----------|-------------|--------------------------------------------------|
| 7                     | ~5 GB         | ~1 GB                | ~6 GB     | Yes         | Plenty of headroom; v0.3.0 secondary, full VRAM  |
| 14                    | ~9 GB         | ~1.5 GB              | ~10.5 GB  | Yes         | Legacy primary (v0.2.x); ~1.5 GB free on GPU     |
| 27                    | ~18 GB        | ~2.5 GB              | ~20.5 GB  | No          | **v0.3.0 primary**: partial offload, ~3-5 tok/s  |
| 32                    | ~20 GB        | ~2.5 GB              | ~22.5 GB  | No          | LEGACY (v0.3.0+): not pulled by default           |

For v0.3.0 we ship with **partial offload** on the RTX 3060 as the
default. The 27 B Q4_K_M is ~18 GB and the card has 12 GB of VRAM, so
~6 GB of weights stay on the CPU side of the system RAM. The previous
v0.2.x primary (14 B, ~9 GB) fit fully in VRAM and ran at ~18 gen
tok/s; the v0.3.0 primary trades speed for agentic coding, multimodal
input, and 256K context. The 32 B option is documented as a
"pull-on-demand, partial offload" scenario but no longer in the
default pull set. Going past that needs measured VRAM, not guesses.

## Disk layout

| Mount      | Content                                                       |
|------------|---------------------------------------------------------------|
| `/`        | Ubuntu install + cloned repo                                  |
| NVMe `/data`| `models/` (hot, symlink target), `runtime/` for sockets      |
| SSD `/bulk`| Downloaded GGUF blobs not currently in use (quiescent cache)  |

`deploy/install.sh` creates both mountpoints if absent and symlinks
`$REPO/models/blobs` to `/data/models` for hot path. Quiescent cache lives at
`/bulk/models/`. `scripts/pull-models.sh` writes to `/bulk/` and the active
model is hardlinked or copied to `/data/` on first load.

Why: a 14 B Q4 GGUF is ~9 GB. Pulling the latest 32 B model for a quick test
should not evict the active one. NVMe is the speed layer; SSD is the volume
layer.

## Build flags matrix

| Detected at install time           | llama.cpp CMake flags                                                    |
|-----------------------------------|--------------------------------------------------------------------------|
| RTX 3060 + driver working         | `-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 -DGGML_NATIVE=OFF`         |
| RTX 3060 hardware but no driver   | Log a clear warning, fall through to CPU row, leave driver install as a follow-up |
| AVX2 CPU only (no NVIDIA)         | `-DGGML_NATIVE=ON` (defaults to host CPU flags)                           |
| Vulkan-only fallback              | `-DGGML_VULKAN=ON` (used as last resort, not primary)                    |

`install.sh` probes in this order:

1. `lspci | grep -i nvidia` — hardware present, works without the driver.
2. `nvidia-smi -L` — runtime confirmation; if it works we can build with
   `-DGGML_CUDA=ON`.
3. `/proc/cpuinfo` flags — for the CPU fallback path.

The selected flags are logged and echoed at the end of the build so the
operator can audit what was compiled. The CUDA arch list is pinned to the
known set for this box (SM 86 = GA106) — not `native` — to keep the build
reproducible on rebuild.

### Driver install timing

`install.sh` installs the NVIDIA driver (the package name is detected
from `apt-cache`, not pinned — Ubuntu releases ship different versions)
but **cannot load the module** during the install — a running kernel
won't pick it up until the next reboot. The script:

1. Installs the driver package.
2. Runs `nvidia-smi` to test. If it fails, the script logs a clear
   message: "Reboot required for the NVIDIA driver. Re-run
   `install.sh` after reboot to finish the llama.cpp CUDA build." and
   exits with code 0 for the apt phase.

Phase 3 (llama.cpp build) is then skipped on this run, and the user
re-runs `install.sh` after reboot. The second run detects the working
driver and proceeds with the CUDA build.

## What we explicitly do not optimise for

- **NUMA**: only relevant on multi-socket servers. A single i5 box is
  uniform memory access for our purposes.
- **Hugepages**: kernel default works; tuning is premature.
- **CPU governor**: the installer leaves `schedutil` alone. The user may
  switch to `performance` if they want; not scripted in v1.