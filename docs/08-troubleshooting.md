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

- First boot, `ia-lab.target` not enabled: `sudo systemctl enable --now ia-lab.target`.
- `OLLAMA_LLAMA_SERVER` override points at a missing binary. Check
  `/etc/systemd/system/ollama.service.d/override.conf`. The path should
  exist and be executable by the `ia-lab` user.
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
`/opt/ia-lab/webui-venv/bin/pip install -U -r requirements.txt`.

## Symptom: TLS errors in browser

The cert is self-signed. The browser will warn. Click through for v1, or
replace the cert per `docs/06-networking-and-security.md`.

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
    sudo systemctl start ia-lab.target

Then look at the actual error in `journalctl -xe`.