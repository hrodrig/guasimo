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
for when the GPU is busy or unavailable.

A second target — the AMD Radeon 760M iGPU (Phoenix / RDNA3) in mini-PC
form factors — is now supported via Vulkan. It is selected automatically
when no NVIDIA GPU is present but an AMD APU shows in `lspci`. Intel Arc
is the only accelerator explicitly out of scope.

### Secondary target: AMD mini-PC (Vulkan)

| Component | Spec                                  | Notes                                        |
|-----------|---------------------------------------|----------------------------------------------|
| CPU       | AMD Ryzen 5 7640HS (Zen4, 6c/12t, 5.0 GHz) | AVX2 + AVX-512 (incl. VNNI/bf16); strong SIMD |
| iGPU      | AMD Radeon 760M (Phoenix1, RDNA3)     | Vulkan via Mesa radv/aco; no ROCm needed     |
| RAM       | 96 GB total, ~16 GB reserved for iGPU | ~80 GB usable; APU shares RAM as VRAM        |
| NVMe      | Kingston OM8PGP4 (PCIe 4.0 QLC)       | DRAM-less; fine for read-mostly GGUF loads   |
| NIC       | Realtek RTL8125 2.5GbE + MT7902 WiFi  | 2.5 GbE preferred for LAN                    |
| OS        | Ubuntu 26.04                          | Same contract as the reference box           |

The Radeon 760M has no dedicated VRAM: firmware carves a share of system
RAM as GPU memory (set to ~16 GB in BIOS on this box — generous for a
mini-PC). llama.cpp's Vulkan backend offloads as many layers as fit in
that carve-out and keeps the rest on CPU/RAM. With a ~16 GB carve-out the
9B primary (Q6_K, ~6-7 GB weights) fits fully in GPU memory, and the
~80 GB of system RAM leaves ample headroom for the 27B secondary plus a
64K KV cache without paging.

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
| KV cache (64K `num_ctx` on 27B Q4)                  | ~3     |
| Open WebUI (Python + Node, modest)                  | 0.5    |
| nginx                                               | 0.05   |
| Headroom for browser, IDE, kernel cache             | 2–6    |

The 27B partial offload in v0.3.x raises the resident model weight
from ~10 GB (v0.2.x 14B, full VRAM) to ~20–22 GB (27B split between
VRAM and RAM). The Modelfile ships with a 64K `num_ctx` (the Hermes
Agent floor), which adds ~3 GB of KV cache on top. Total at idle
sits around 26–28 GB; under load with a long context it can climb
to ~30 GB. We never enable swap beyond the Ubuntu default — OOM is
the correct signal when an operator pushes `num_ctx` past the
available headroom. Operators who do not run Hermes can drop the
Modelfile `num_ctx` to 8K (for inline completions) or 16K (a middle
ground) and reclaim ~1–2 GB of RAM.

## VRAM math (RTX 3060, 12 GB)

| Model size (B params) | Q4_K_M weight | Q4 KV cache (8K ctx) | Total fit | Fits 12 GB? | Notes                                            |
|-----------------------|---------------|----------------------|-----------|-------------|--------------------------------------------------|
| 7                     | ~5 GB         | ~1 GB                | ~6 GB     | Yes         | Plenty of headroom; v0.3.0 secondary, full VRAM  |
| 14                    | ~9 GB         | ~1.5 GB              | ~10.5 GB  | Yes         | Legacy primary (v0.2.x); ~1.5 GB free on GPU     |
| 27                    | ~18 GB        | ~2.5 GB              | ~20.5 GB  | No          | **v0.3.0 primary**: partial offload, ~4 gen tok/s @ 64K |
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

## Why we do not pull large MoEs (≥125B) on the mini-PC

Documented so this decision is recorded and not re-evaluated each session.
`Qwen3.8-Flash-Next` is a 125B-total MoE (6B active) that is frequently
proposed as a "flagship" drop-in. It does not fit the mini-PC's memory and
no quantisation brings it inside budget once KV cache and compute buffers
are counted. Measured sizes from `unsloth/Qwen3.8-Flash-Next-GGUF`:

| Quantisation | Weight on disk (GB) | Fits ~80 GB usable?                                    |
|--------------|---------------------|--------------------------------------------------------|
| Q8_0         | ~125                | No                                                     |
| Q6_K_XL      | ~95                 | No                                                     |
| Q5_K_XL      | ~82                 | No (KV cache pushes it over)                           |
| Q4_K_XL      | ~68                 | Borderline — no headroom for a 64K KV cache            |
| Q3_K_XL      | ~90                 | No                                                     |
| Q2_K_XL      | ~79                 | No                                                     |
| IQ1_M        | ~75                 | No                                                     |
| IQ1_S        | ~72.5               | Borderline — model loads, then pages on any real ctx   |

The base is 125B: the aggressive low-bit quants (IQ1/IQ2/Q2) that would
nominally fit degrade quality so far that the 27B dense (`qwen3.8:27b` Q4,
~18 GB) delivers far better *usable* quality at a fraction of the RAM and
without paging. At those lossy quants the KV cache for a useful 64K context
still overflows into swap and inference collapses to unusable speed on an
APU sharing its video carve-out with system RAM.

**Decision**: the mini-PC target is capped at ~35B-total MoE. The natural
step up from `primary` (Ornith-1.5-9B) is `Ornith-1.5-35B-A3B` (Q4_K_M,
~20 GB), which leaves ~50 GB of headroom for a 64K KV cache and OS. Models
of 125B+ are explicitly out of scope for this target and belong on GPU
datacenter hardware.

## Build flags matrix

| Detected at install time           | llama.cpp CMake flags                                                    |
|-----------------------------------|--------------------------------------------------------------------------|
| RTX 3060 + driver working         | `-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 -DGGML_NATIVE=OFF`         |
| RTX 3060 hardware but no driver   | Log a clear warning, fall through to CPU row, leave driver install as a follow-up |
| AMD Radeon iGPU (Phoenix/RDNA3)   | `-DGGML_VULKAN=ON -DGGML_NATIVE=ON`                                      |
| AVX2/AVX-512 CPU only (no GPU)    | `-DGGML_NATIVE=ON` (defaults to host CPU flags)                           |

`install.sh` probes in this order:

1. `lspci | grep -i nvidia` — NVIDIA hardware present, works without the driver.
2. `nvidia-smi -L` — runtime confirmation; if it works we can build with
   `-DGGML_CUDA=ON`.
3. `lspci` for an AMD APU (`amd/ati` + `vga`) — if present and no NVIDIA,
   select the Vulkan backend (`-DGGML_VULKAN=ON`).
4. `/proc/cpuinfo` flags — for the CPU fallback path.

The selected flags are logged and echoed at the end of the build so the
operator can audit what was compiled. The CUDA arch list is pinned to the
known set for this box (SM 86 = GA106) — not `native` — to keep the build
reproducible on rebuild. The Vulkan backend keeps `-DGGML_NATIVE=ON` so
the CPU kernels (which carry the layers that don't fit the APU's VRAM
carve-out) stay tuned for the host.

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