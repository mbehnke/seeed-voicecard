#!/bin/bash

# Early boot capture: collect minimal audio state plus a machine-readable status
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/early_boot_${TS}.log"
STATUS_FILE="$LOG_DIR/early_boot_${TS}.json"

mkdir -p "$LOG_DIR"

device_detected=0
controls_found=0
i2c_status="unknown"
recording_max="n/a"

{
  echo "=== timestamp ==="
  date -u +"%Y-%m-%dT%H:%M:%SZ"

  echo
  echo "=== kernel version ==="
  uname -r

  echo
  echo "=== loaded kernel modules (ac108/seeed) ==="
  lsmod | grep -E "(ac108|seeed)" || echo "no ac108/seeed modules loaded"

  echo
  echo "=== device tree overlays ==="
  sudo dtoverlay -l 2>/dev/null || echo "dtoverlay command not available"

  echo
  echo "=== dmesg (ac108/seeed/i2s/asoc, last 200) ==="
  dmesg | grep -Ei "ac108|seeed|i2s|asoc" | tail -200

  echo
  echo "=== lsmod (ac108/voicecard) ==="
  lsmod | grep -E "(ac108|seeed)" || echo "no ac108/seeed modules listed"

  echo
  echo "=== arecord -l ==="
  arecord -l

  echo
  echo "=== amixer scontrols (first 40) ==="
  amixer -c 0 scontrols 2>/dev/null | head -40 || echo "amixer failed"

  echo
  echo "=== i2cdetect -y 1 ==="
  i2cdetect -y 1 2>/dev/null || echo "i2cdetect failed"

  echo
  echo "=== I2C device check (AC108 @ 0x3b) ==="
  if i2cdetect -y 1 2>/dev/null | grep -qE "3b|UU"; then
    echo "AC108 detected on I2C bus (0x3b)"
  else
    echo "WARNING: AC108 NOT detected on I2C bus"
  fi

  echo
  echo "=== clock configuration ==="
  if [ -f /sys/kernel/debug/clk/clk_summary ]; then
    sudo cat /sys/kernel/debug/clk/clk_summary 2>/dev/null | grep -i i2s || echo "no I2S clocks found"
  else
    echo "clk_summary not available"
  fi

  echo
  echo "=== /sys/kernel/debug/asoc/cards ==="
  sudo cat /sys/kernel/debug/asoc/cards 2>/dev/null || echo "asoc cards not available"

  echo
  echo "=== /sys/kernel/debug/asoc/dais (filtered ac108/i2s) ==="
  sudo cat /sys/kernel/debug/asoc/dais 2>/dev/null | grep -Ei "ac108|i2s" || echo "no dais entries"

  echo
  echo "=== DAI formats (TDM check) ==="
  sudo find /sys/kernel/debug/asoc/ -name formats 2>/dev/null | while read -r f; do
    echo "--- $f ---"
    sudo cat "$f" 2>/dev/null || echo "error reading formats"
  done

  echo
  echo "=== /sys/kernel/debug/asoc/codec (if present) ==="
  sudo find /sys/kernel/debug/asoc -name codec 2>/dev/null | while read -r f; do
    echo "--- $f ---"
    sudo cat "$f" 2>/dev/null | head -40
  done

  echo
  echo "=== Testaufnahme 1s (S32_LE, 16k, 4ch) ==="
  echo "--- Hardware parameters check ---"
  timeout 2 arecord -D hw:0,0 --dump-hw-params -f S32_LE -r 16000 -c 4 /dev/null 2>&1 || echo "hwparams dump failed"
  echo
  echo "--- Recording test ---"
  timeout 2 arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 "$LOG_DIR/early_boot_${TS}.wav" 2>&1 || echo "arecord failed or timed out"
  if [ -f "$LOG_DIR/early_boot_${TS}.wav" ]; then
    echo "--- Audio statistics ---"
    sox "$LOG_DIR/early_boot_${TS}.wav" -n stat 2>&1 | grep -E "Max level|Length|RMS" || echo "sox stat failed"
  fi
} > "$LOG_FILE" 2>&1

# Metrics extraction for JSON
if arecord -l 2>/dev/null | grep -qi seeed; then
  device_detected=1
fi
controls_found=$(amixer -c 0 scontrols 2>/dev/null | grep -c "ADC[1-4]" || true)
[ -z "$controls_found" ] && controls_found=0
if i2cdetect -y 1 2>/dev/null | grep -q "UU"; then
  i2c_status="in_use"
fi
if [ -f "$LOG_DIR/early_boot_${TS}.wav" ]; then
  recording_max=$(sox "$LOG_DIR/early_boot_${TS}.wav" -n stat 2>&1 | awk '/Max level/ {print $3}' | head -1)
  [ -z "$recording_max" ] && recording_max="0.000000"
fi

status="success"
error_code=0
root_cause="ok"
required_actions=()

if [ "$device_detected" -eq 0 ]; then
  status="error"
  error_code=-1
  root_cause="ALSA card missing"
  required_actions+=("arecord -l" "dmesg | grep -i asoc")
elif [ "$controls_found" -eq 0 ]; then
  status="error"
  error_code=-2
  root_cause="AC108 controls missing"
  required_actions+=("amixer -c 0 scontrols" "sudo alsactl init")
elif awk 'BEGIN {exit !("'$recording_max'"+0==0)}'; then
  status="error"
  error_code=-3
  root_cause="capture silent"
  required_actions+=("amixer -c 0 sset \"ADC1 PGA gain\" 31" "timeout 3 arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 /tmp/test.wav")
fi

actions_json="[]"
if [ ${#required_actions[@]} -gt 0 ]; then
  actions_json="["
  for i in "${!required_actions[@]}"; do
    action=${required_actions[$i]}
    action_esc=$(printf '%s' "$action" | sed 's/\\/\\\\/g; s/"/\\"/g')
    if [ "$i" -gt 0 ]; then
      actions_json+=",";
    fi
    actions_json+="\"$action_esc\""
  done
  actions_json+="]"
fi

cat > "$STATUS_FILE" <<EOF
{
  "status": "$status",
  "error_code": $error_code,
  "key_metrics": {
    "device_detected": $( [ "$device_detected" -eq 1 ] && echo true || echo false ),
    "i2c_status": "$i2c_status",
    "alsa_controls": $controls_found,
    "recording_max_level": "$recording_max"
  },
  "root_cause": "$root_cause",
  "required_actions": $actions_json
}
EOF

echo "Log: $LOG_FILE"
echo "Status JSON: $STATUS_FILE"
