#!/usr/bin/env bash
# scripts/thermal-monitor.sh — continuous thermal monitor for the guasimo stack.
#
# Unlike scripts/thermal-guard.sh (a one-shot backoff helper), this runs as a
# long-lived daemon under systemd and samples the AMD SoC/GPU junction every
# THERMAL_INTERVAL_S, logging each sample to stdout (journald) and emitting a
# WARN/alert line whenever the soft cap THERMAL_MAX_C is exceeded.
#
# The mini-PC's "capacitor burned out" failure mode is thermal, so this is the
# always-on signal that something is cooking. It does NOT throttle anything by
# itself (that is thermal-guard.sh, called by the warm callers); it observes
# and records so an operator can correlate load with temperature later.
#
# Env (override via systemd override.conf or Environment=):
#   THERMAL_MAX_C       alert threshold in Celsius (default 80 — board Tjmax 95)
#   THERMAL_INTERVAL_S  sample cadence in seconds (default 30)
#   THERMAL_SLOW_TICK   with THERMAL_LOG=n, how often to emit an OK line,
#                       in samples (default 12 → one "OK" line per ~6 min at
#                       30 s, so the journal isn't flooded by quiet idle).

set -uo pipefail

THERMAL_MAX_C="${THERMAL_MAX_C:-80}"
THERMAL_INTERVAL_S="${THERMAL_INTERVAL_S:-30}"
# Emit a periodic OK heartbeat only every N samples to avoid journal spam.
OK_TICK="${THERMAL_SLOW_TICK:-12}"

# Highest temperature across the AMD sensors we care about.
peak_temp() {
  local t max=0 name
  for h in /sys/class/hwmon/hwmon*; do
    name=$(cat "${h}/name" 2>/dev/null || true)
    case "${name}" in
      k10temp|amdgpu|zenpower)
        for f in "${h}"/temp*_input; do
          [ -f "${f}" ] || continue
          t=$(cat "${f}" 2>/dev/null || true)
          t=$((t / 1000))   # hwmon reports millidegrees C
          [ "${t}" -gt "${max}" ] && max=${t}
        done
        ;;
    esac
  done
  echo "${max}"
}

# Per-sensor breakdown for the log line (k10temp + amdgpu).
sensor_line() {
  local t name out=""
  for h in /sys/class/hwmon/hwmon*; do
    name=$(cat "${h}/name" 2>/dev/null || true)
    case "${name}" in
      k10temp|amdgpu|zenpower)
        f="${h}/temp1_input"
        [ -f "${f}" ] || continue
        t=$(cat "${f}" 2>/dev/null || true); t=$((t / 1000))
        out="${out}${name}=${t}C "
        ;;
    esac
  done
  echo "${out% }"
}

echo "thermal-monitor: started (cap ${THERMAL_MAX_C}C, every ${THERMAL_INTERVAL_S}s)"

i=0
while true; do
  T=$(peak_temp)
  SENSORS=$(sensor_line)
  if [ "${T}" -gt "${THERMAL_MAX_C}" ]; then
    echo "thermal-monitor: ALERT peak ${T}C > ${THERMAL_MAX_C}C  [${SENSORS}]"
  else
    i=$((i + 1))
    if [ $((i % OK_TICK)) -eq 0 ]; then
      echo "thermal-monitor: ok peak ${T}C <= ${THERMAL_MAX_C}C  [${SENSORS}]"
    fi
  fi
  sleep "${THERMAL_INTERVAL_S}"
done
