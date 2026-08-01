# 08 — Troubleshooting

## Triage order

Always go through these in order. Skipping ahead wastes time.

1. **Is the host up?** `ping`, `ssh`. If no, it's not an LLM problem.
2. **Are the systemd units active?**
   `systemctl status ollama open-webui nginx`.
3. **Is the model loaded?** `curl http://127.0.0.1:11434/api/tags | jq`.
4. **Does the API respond?** `curl http://127.0.0.1:11434/v1/models`.
5. **Does the web UI load?** `curl -I http://127.0.0.1:8080`.

The problem lives at whichever step first fails.

## Symptom: "Connection refused" on 11434

Ollama is not running.

    systemctl status ollama
    sudo journalctl -u ollama -n 50 --no-pager

Common causes:

- First boot, `guasimo.target` not enabled: `sudo systemctl enable --now guasimo.target`.
- `OLLAMA_LLAMA_SERVER` override points at a missing binary. Check
  `/etc/systemd/system/ollama.service.d/override.conf`. The path should
  exist and be executable by the `guasimo` user.
- Port collision: `ss -ltnp 'sport = :11434'`.

## Symptom: Ollama running, model not loaded

    ollama pull <name>
    ollama list

If `ollama pull` fails with a 404, the model name in the Modelfile is
wrong. Check `config/ollama/Modelfile.<name>` and confirm the `FROM`
line.

If `ollama pull` fails with a network error, check DNS and HTTP proxy.
Ollama pulls from `registry.ollama.ai` by default.

## Symptom: model loaded, but responses are slow (>2 tok/s drop)

- CPU thermal throttle? `sensors | grep Core` (install `lm-sensors`).
- Wrong SIMD build? The install log should say "AVX2" or "AVX-512". If it
  says "fallback", rebuild.
- Another process eating CPU: `htop`.
- KV cache thrash: context length set too high. Drop `num_ctx` to 4096 and
  retry.

## Symptom: OOM kill in dmesg

    dmesg | grep -i 'killed process'

Inference is over-budget. Either:

- Drop to a smaller model (7 B instead of 14 B).
- Lower `num_ctx`.
- Reduce concurrent requests (Ollama's `num_parallel`).

A 32 GB system should not OOM on a single 14 B Q4 model with 8K context.
If it does, something else is resident — `ps aux --sort -%mem | head`.

## Symptom: nginx 502 to Open WebUI

Open WebUI crashed or is still starting.

    sudo journalctl -u open-webui -n 50 --no-pager

If the venv is broken (e.g. after a Python upgrade), re-run
`/opt/guasimo/webui-venv/bin/pip install -U -r requirements.txt`.

## Symptom: TLS errors in browser

The cert is self-signed. The browser will warn. Click through for v1, or
replace the cert per `docs/06-networking-and-security.md`.

## Symptom: `No matching distribution found for open-webui==…`

Ubuntu 26.04's system `python3` is 3.13+. Open WebUI still declares
`Requires-Python >=3.11,<3.13`, so pip on a 3.13 venv ignores every
release (including the pin) and reports "from versions: none".

`install.sh` installs `python3.12` / `python3.12-venv` and builds the
WebUI venv with that interpreter. Manual recovery:

    sudo apt-get install -y python3.12 python3.12-venv
    sudo rm -rf /opt/guasimo/webui-venv
    sudo ./deploy/install.sh

## Symptom: llama.cpp build fails with `uint32_t` does not name a type

On Ubuntu 26.04 (GCC 15), building pinned llama.cpp `b4568` dies in
`src/llama-mmap.h`:

```
error: ‘uint32_t’ does not name a type
   26 |     uint32_t read_u32() const;
note: ‘uint32_t’ is defined in header ‘<cstdint>’; this is probably
      fixable by adding ‘#include <cstdint>’
```

GCC 15 stopped leaking fixed-width types through `<vector>` /
`<memory>`. Upstream fixed it in ggml-org/llama.cpp#11796; our pin is
older. `install.sh` patches the header after clone when `<cstdint>` is
missing.

Manual recovery if you hit this mid-build:

    sudo sed -i '/#pragma once/a\
\
#include <cstdint>' /opt/guasimo/llama.cpp/src/llama-mmap.h
    sudo ./deploy/install.sh

Or one-shot rebuild without re-running the full install:

    cd /opt/guasimo/llama.cpp
    sudo cmake --build build --parallel

## Symptom: NVIDIA GPU detected but ignored

`install.sh` only enables CUDA when `nvidia-smi` works **as a non-root
user**. If the driver is installed but `nvidia-smi` requires root, fix the
driver:

    sudo usermod -aG video $LOGNAME
    newgrp video
    nvidia-smi

Re-run `install.sh`. Phase 1 will re-detect.

## Symptom: `Sub-process /usr/bin/dpkg returned an error code (1)` during install

The NVIDIA driver unpack failed on packages like `nvidia-firmware-610`,
`libnvidia-cfg1-610`, `libnvidia-gl-610`. The most common cause is a
`dpkg` database left half-configured by a previous interrupted run
(Ctrl-C, power loss, or an earlier failed driver install).

`install.sh` now repairs this automatically at the start of phase 2
(`dpkg --configure -a` + `apt-get -f install`), and the driver failure
no longer kills the whole install — the box falls back to a CPU build
of `llama.cpp` for that run. To retry CUDA:

    sudo dpkg --configure -a
    sudo apt-get -f install
    sudo apt-get install -y nvidia-driver-610   # or whatever apt-cache found
    sudo reboot
    sudo ./deploy/install.sh                    # re-run to enable CUDA

If the driver unpack still fails after the repair, look for:

- An older driver still installed: `dpkg -l | grep nvidia-driver` and
  `sudo apt-get remove --purge nvidia-driver-*` (keep the one you want).
- Secure Boot / MOK enrollment blocking the kernel module: the driver
  package unpacks but the module never loads. `mokutil --sb-state` tells
  you. Enroll the MOK or disable Secure Boot.
- Out of space on `/`: `df -h /`. The driver packages are large.

After the driver loads (`nvidia-smi` works as a non-root user), re-run
`install.sh`. Phase 3 will build the CUDA variant.

## Symptom: `trying to overwrite` between `nvidia-firmware` and `nvidia-firmware-610`

Validated on Ubuntu 26.04 (`resolute`) with RTX 3060 during the first
real `install.sh` run (2026-07-31). This is **not** a half-configured
dpkg database — it is a packaging-scheme collision. `apt-get -f install`
alone cannot fix it.

### Root cause

Two packaging schemes ship the same NVIDIA files under different package
names:

| Scheme | Source | Version suffix | Example packages |
|--------|--------|----------------|------------------|
| Unversioned | Ubuntu archive | `…-1ubuntu1` | `nvidia-firmware`, `libnvidia-cfg1`, `libnvidia-egl-wayland21` |
| Versioned | NVIDIA CUDA repo | `…-0ubuntu0.26.04.1` | `nvidia-firmware-610-*`, `libnvidia-cfg1-610`, `libnvidia-gl-610` |

Shared paths (examples):

- `/lib/firmware/nvidia/610.43.02/gsp_ga10x.bin`
- `/usr/lib/x86_64-linux-gnu/libnvidia-cfg.so.610.43.02`
- `/usr/lib/x86_64-linux-gnu/libnvidia-egl-wayland2.so.1.0.1`

How the box gets stuck: an earlier install left the unversioned Ubuntu
packages; later `nvidia-driver-610` from the CUDA repo (or a partial
install) needs the versioned siblings. dpkg refuses the overwrite → apt
reports unmet Depends forever.

### How it looks in the wild

Real console excerpts from Ubuntu 26.04 / driver 610.43.02 (2026-07-31).

**Phase A — unmet Depends after a half-broken install:**

```
nvidia-driver-610 is already the newest version (610.43.02-0ubuntu0.26.04.1).
nvidia-cuda-toolkit is already the newest version (12.4.131~12.4.1-8).
You might want to run 'apt --fix-broken install' to correct these.
The following packages have unmet dependencies:
 nvidia-dkms-610 : Depends: nvidia-firmware-610-610.43.02 but it is not going to be installed
 nvidia-driver-610 : Depends: libnvidia-gl-610 (= 610.43.02-0ubuntu0.26.04.1) but it is not going to be installed
                     Depends: libnvidia-cfg1-610 (= 610.43.02-0ubuntu0.26.04.1) but it is not going to be installed
 nvidia-kernel-common-610 : Depends: nvidia-firmware-610-610.43.02 but it is not going to be installed
 xserver-xorg-video-nvidia-610 : Depends: libnvidia-cfg1-610 (= 610.43.02-0ubuntu0.26.04.1) but it is not going to be installed
E: Unmet dependencies. Try 'apt --fix-broken install' with no packages (or specify a solution).
```

**Phase B — `apt-get -f install` hits the file collision:**

```
Preparing to unpack …/nvidia-firmware-610-610.43.02_610.43.02-0ubuntu0.26.04.1_amd64.deb…
dpkg: error processing archive …/nvidia-firmware-610-610.43.02_….deb (--unpack):
 trying to overwrite '/lib/firmware/nvidia/610.43.02/gsp_ga10x.bin', which is also in package nvidia-firmware (610.43.02-1ubuntu1)
Preparing to unpack …/libnvidia-gl-610_610.43.02-0ubuntu0.26.04.1_amd64.deb…
dpkg: error processing archive …/libnvidia-gl-610_….deb (--unpack):
 trying to overwrite '/usr/lib/x86_64-linux-gnu/libnvidia-egl-wayland2.so.1.0.1', which is also in package libnvidia-egl-wayland21:amd64 (1.0.1-1ubuntu1)
Preparing to unpack …/libnvidia-cfg1-610_610.43.02-0ubuntu0.26.04.1_amd64.deb…
dpkg: error processing archive …/libnvidia-cfg1-610_….deb (--unpack):
 trying to overwrite '/usr/lib/x86_64-linux-gnu/libnvidia-cfg.so.610.43.02', which is also in package libnvidia-cfg1:amd64 (610.43.02-1ubuntu1)
E: Sub-process /usr/bin/dpkg returned an error code (1)
```

**Phase C — `apt-get remove --purge` does NOT work** while the graph is
broken (packages stay installed; same unmet Depends message as Phase A).

### Fix (prefer versioned CUDA-repo scheme)

Bypass apt's resolver with `dpkg`, then let apt finish the graph:

    sudo dpkg --purge --force-depends \
      nvidia-firmware libnvidia-cfg1 libnvidia-egl-wayland21 \
      libnvidia-egl-xcb1 libnvidia-egl-xlib1 libnvidia-gpucomp \
      nvidia-modprobe
    sudo apt-get -f install -y
    sudo apt-get autoremove -y
    # then reboot — see "After the fix" below
    sudo reboot

**Phase D — successful recovery (real output, abbreviated):**

```
Removing nvidia-firmware (610.43.02-1ubuntu1)…
dpkg: warning: while removing nvidia-firmware, directory '/lib/firmware/nvidia' not empty so not removed
Removing libnvidia-cfg1:amd64 (610.43.02-1ubuntu1)…
Removing libnvidia-egl-wayland21:amd64 (1.0.1-1ubuntu1)…
…
The following NEW packages will be installed:
  libnvidia-cfg1-610 libnvidia-gl-610 nvidia-firmware-610-610.43.02
…
Setting up nvidia-dkms-610 (610.43.02-0ubuntu0.26.04.1)…
Building for 7.0.0-14-generic and 7.0.0-28-generic
Building initial module nvidia/610.43.02 for 7.0.0-14-generic
… Signing module …/nvidia.ko …
Installing /lib/modules/7.0.0-14-generic/updates/dkms/nvidia.ko.zst
…
Building initial module nvidia/610.43.02 for 7.0.0-28-generic
…
Setting up nvidia-driver-610 (610.43.02-0ubuntu0.26.04.1)…
Setting up nvidia-cuda-toolkit (12.4.131~12.4.1-8)…
```

The `directory '/lib/firmware/nvidia' not empty` warning is harmless —
versioned firmware files land in the same tree a moment later.

Fallback if purge is awkward — overwrite first, then drop the orphaned
unversioned records:

    sudo apt-get -o Dpkg::Options::="--force-overwrite" -f install -y
    sudo dpkg --purge --force-depends \
      nvidia-firmware libnvidia-cfg1 libnvidia-egl-wayland21 \
      libnvidia-egl-xcb1 libnvidia-egl-xlib1 libnvidia-gpucomp \
      nvidia-modprobe

### After the fix — reboot before trusting `nvidia-smi`

DKMS just built and signed the modules. Until reboot (or a careful
`modprobe nvidia`), `nvidia-smi` still fails even though packages are
healthy:

```
NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA
driver. Make sure that the latest NVIDIA driver is installed and running.
```

That message here means **module not loaded yet**, not "packages still
broken". Reboot, then verify:

    sudo reboot
    # after reboot:
    nvidia-smi
    cd ~/guasimo && git pull && sudo ./deploy/install.sh

Expected post-reboot `nvidia-smi` (real capture, prompt anonymized):

![nvidia-smi after mixed-repo fix — RTX 3060, driver 610.43.02](assets/nvidia-smi-rtx3060-after-fix.png)

`install.sh` automates the purge path inside `recover_dpkg` /
`purge_unversioned_nvidia_conflict` when it detects this state.

### Prevention

Pick **one** driver source. On Ubuntu 26.04 the documented path is the
NVIDIA CUDA repo (see `docs/05-deployment.md` pre-flight). Do not also
install unversioned Ubuntu-archive NVIDIA packages (`nvidia-firmware`,
`libnvidia-cfg1`, …) on the same box.

## Symptom: IDE plugin can't reach the API

- Is the plugin pointed at `http://127.0.0.1:11434/v1`? (Not `https` — Ollama
  is HTTP-only on loopback.)
- Is the LAN IP used instead? Ollama is loopback-only. The IDE plugin must
  run on the host or use SSH port forwarding:
  `ssh -L 11434:127.0.0.1:11434 user@host`.

## Symptom: model answers look "stuck" or repeat

- Lower the temperature in the request.
- Set `repeat_penalty` higher (`1.1` is a common bump).
- Check the chat template — an off-the-shelf Modelfile inherits the model's
  chat template; a custom one may have lost the stop tokens.

## Symptom: out of disk on /data

Models are too big or too many. Audit:

    du -sh /data/models/* /bulk/models/*

Drop unused models with `ollama rm` and manually `rm` the underlying blob
in `/bulk/models/`.

## Symptom: systemd unit "failed" on boot

    sudo systemctl reset-failed
    sudo systemctl daemon-reload
    sudo systemctl start guasimo.target

Then look at the actual error in `journalctl -xe`.