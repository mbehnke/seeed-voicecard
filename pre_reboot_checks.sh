#!/bin/bash

# Pre-reboot checks for RPi 5 + AC108 to ensure DTB/overlay and buses are ready
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
TS="$(date +%Y%m%d_%H%M%S)"
STATUS_FILE="$LOG_DIR/pre_reboot_${TS}.json"
mkdir -p "$LOG_DIR"

# Defaults
status="success"
error_code=0
root_cause="ok"
required_actions=()

# Metrics
dtb_has_sound_node=false
i2s_status_okay="unknown"
i2c1_status_okay="unknown"
overlay_listed=false
ac108_i2c_detected=false

# Detect overlay presence (may be merged into DTB)
if sudo dtoverlay -l 2>/dev/null | grep -qi "seeed-4mic-voicecard"; then
  overlay_listed=true
fi

# DTB sound node presence
if [ -r /proc/device-tree/sound/compatible ]; then
  dtb_has_sound_node=true
fi

# Try to infer node status from fdtdump (best-effort)
DTB_PATH="/boot/firmware/bcm2712-rpi-5-b.dtb"
if [ -r "$DTB_PATH" ] && command -v fdtdump >/dev/null 2>&1; then
  dump=$(sudo fdtdump -p "$DTB_PATH" 2>/dev/null || true)
  if printf '%s' "$dump" | grep -q "sound"; then
    dtb_has_sound_node=true
  fi
  if printf '%s' "$dump" | grep -q "i2s"; then
    i2s_status_okay="present"
  fi
  if printf '%s' "$dump" | grep -q "i2c1"; then
    i2c1_status_okay="present"
  fi
fi

# I2C AC108 device detect (UU or 3b)
if i2cdetect -y 1 2>/dev/null | grep -qE "UU|3b"; then
  ac108_i2c_detected=true
fi

# Root cause classification
if [ "$dtb_has_sound_node" != true ]; then
  status="error"; error_code=-10; root_cause="DTB missing sound node";
  required_actions+=("sudo fdtdump /boot/firmware/bcm2712-rpi-5-b.dtb | grep -A20 'sound'" "sudo fdtoverlay -i /boot/firmware/bcm2712-rpi-5-b.dtb -o /boot/firmware/bcm2712-rpi-5-b.dtb.merged \"$PROJECT_DIR/seeed-4mic-voicecard-rpi5-overlay.dts\"")
elif [ "$i2s_status_okay" = "unknown" ]; then
  status="error"; error_code=-11; root_cause="I2S node unknown (debugfs/DTB check)";
  required_actions+=("dmesg | grep -i i2s" "grep -R i2s /proc/device-tree 2>/dev/null")
elif [ "$i2c1_status_okay" = "unknown" ]; then
  status="error"; error_code=-12; root_cause="I2C1 node unknown (debugfs/DTB check)";
  required_actions+=("dmesg | grep -i i2c" "grep -R i2c1 /proc/device-tree 2>/dev/null")
elif [ "$ac108_i2c_detected" != true ]; then
  status="error"; error_code=-13; root_cause="AC108 not detected on I2C bus";
  required_actions+=("i2cdetect -y 1" "sudo modprobe -r snd_soc_ac108; sudo modprobe snd_soc_ac108")
fi

# Serialize actions
actions_json="[]"
if [ ${#required_actions[@]} -gt 0 ]; then
  actions_json="["
  for i in "${!required_actions[@]}"; do
    a=${required_actions[$i]}
    esc=$(printf '%s' "$a" | sed 's/\\/\\\\/g; s/"/\\"/g')
    if [ "$i" -gt 0 ]; then actions_json+=","; fi
    actions_json+="\"$esc\""
  done
  actions_json+="]"
fi

cat > "$STATUS_FILE" <<EOF
{
  "status": "$status",
  "error_code": $error_code,
  "key_metrics": {
    "dtb_has_sound_node": $dtb_has_sound_node,
    "i2s_status": "$i2s_status_okay",
    "i2c1_status": "$i2c1_status_okay",
    "overlay_listed": $overlay_listed,
    "ac108_i2c_detected": $ac108_i2c_detected
  },
  "root_cause": "$root_cause",
  "required_actions": $actions_json
}
EOF

echo "$STATUS_FILE"
