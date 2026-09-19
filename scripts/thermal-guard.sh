#!/usr/bin/env bash
# scripts/thermal-guard.sh — soft thermal throttle for the guasimo stack.
#
# Reads the hottest SoC/GPU junction from the AMD k10temp / amdgpu hwmon
# nodes (the only temperature sources on the Ryzen 5 7640HS mini-PC, which
# has no nvidia-smi). When any temperature exceeds THERMAL_MAX_C it backs
# off to THERMAL_WAIT_S of sleep before returning. Callers poll it between
# heavy operations (benchmark batches, long generation runs) so a sustained
# load eases off instead of cooking the board.
#
# The mini-PC has no dedicated GPU VRAM thermometer exposed via hwmon; the
# SoC junction (k10temp) and the GPU junction (amdgpu) are the two values
# that matter for the "capacitor burned out" failure mode. Keep both below
# the cap.
#
# Usage:
#   scripts/thermal-guard.sh [tries]   # block until cool, up to <tries> waits
#
# Env overrides:
#   THERMAL_MAX_C    soft cap in Celsius (default 80 — conservative for this
#                    board whose Tjmax is 95 C)
#   THERMAL_WAIT_S   seconds to sleep per backoff (default 20)
#
# Exit: 0 if all sensors are at/below the cap, 1 if still hot after <tries>.

set -uo pipefail

THERMAL_MAX_C="${THERMAL_MAX_C:-80}"
THERMAL_WAIT_S="${THERMAL_WAIT_S:-20}"
TRIES="${1:-1}"

# Highest temperature across the AMD sensors we care about.
# hwmon node names on the mini-PC: k10temp (CPU/SoC), amdgpu (iGPU).
# Prints "max sensors" on one line (e.g. "72 2"). sensors=0 → no AMD hwmon.
peak_temp() {
  local t max=0 name sensors=0
  for h in /sys/class/hwmon/hwmon*; do
    name=$(cat "${h}/name" 2>/dev/null || true)
    case "${name}" in
      k10temp|amdgpu|zenpower)
        for f in "${h}"/temp*_input; do
          [ -f "${f}" ] || continue
          sensors=$((sensors + 1))
          t=$(cat "${f}" 2>/dev/null || true)
          [ -n "${t}" ] || continue
          t=$((t / 1000))   # hwmon reports millidegrees C
          [ "${t}" -gt "${max}" ] && max=${t}
        done
        ;;
    esac
  done
  echo "${max} ${sensors}"
}

read -r T SENSORS < <(peak_temp)
# CUDA / non-AMD boxes have no k10temp|amdgpu nodes. Skip rather than
# treating peak=0 as "cold" — callers on those hosts still proceed.
if [ "${SENSORS}" -eq 0 ]; then
  echo "thermal: no AMD hwmon sensors (k10temp/amdgpu) — skipping" >&2
  exit 0
fi

for _ in $(seq 1 "${TRIES}"); do
  read -r T SENSORS < <(peak_temp)
  if [ "${T}" -le "${THERMAL_MAX_C}" ]; then
    echo "thermal: ${T}C OK (<= ${THERMAL_MAX_C}C)" >&2
    exit 0
  fi
  echo "thermal: ${T}C hot — backing off ${THERMAL_WAIT_S}s before retry (cap ${THERMAL_MAX_C}C)" >&2
  sleep "${THERMAL_WAIT_S}"
done

read -r T SENSORS < <(peak_temp)
echo "thermal: STILL HOT ${T}C after ${TRIES} tries — aborting" >&2
exit 1
