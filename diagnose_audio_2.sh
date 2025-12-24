#!/bin/bash

# Log-Pfade immer ins Projektverzeichnis schreiben (auch bei sudo)
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$PROJECT_DIR/logs/ac108_debug_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"
START_TIME=$(date +%s)
STATUS_FILE="$LOG_DIR/status.json"

# Schritt-Ausführung mit Laufzeitmessung; gibt nur die Dauer auf STDOUT zurück
step_timer() {
  local step_name="$1"
  local step_cmd="$2"
  local start_step=$(date +%s)
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] 🕒 Start: $step_name" >&2
  eval "$step_cmd"
  local end_step=$(date +%s)
  local duration=$((end_step - start_step))
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ Fertig: $step_name ($duration Sekunden)" >&2
  echo "$duration"
}

# 0. Kernel-Module und Device Tree prüfen
module_duration=$(step_timer "Kernel-Module und Device Tree prüfen" "
  {
    echo '[Kernel Modules - $(date +'%Y-%m-%d %H:%M:%S')]'
    lsmod | grep -E '(snd_soc_ac108|snd_soc_seeed_voicecard|snd_soc)' || echo '⚠️ Keine AC108/Seeed-Module geladen'
    echo ''
    echo '[Module Info]'
    modinfo snd_soc_ac108 2>/dev/null || echo '⚠️ snd_soc_ac108 module info nicht verfügbar'
    echo ''
    echo '[Device Tree]'
    sudo dtoverlay -l 2>/dev/null || echo '⚠️ Device Tree Overlay list nicht verfügbar'
    echo ''
    echo '[dmesg - seeed/ac108/i2s]'
    dmesg | grep -Ei 'seeed|ac108|i2s' | tail -100 || echo '⚠️ Keine relevanten dmesg-Einträge'
  } > '$LOG_DIR/0_kernel_modules.log'
")

# 1. DAI-Formate prüfen
dai_duration=$(step_timer "DAI-Formate prüfen" "
  {
    echo '[DAI Formats - $(date +'%Y-%m-%d %H:%M:%S')]'
    find /sys/kernel/debug/asoc/ -name formats 2>/dev/null | while read -r f; do
      echo '---' \$f '---'
      cat \$f 2>/dev/null || echo '⚠️ Fehler beim Lesen von' \$f
    done
  } > '$LOG_DIR/1_dai_formats.log'
")

# 2. DAPM-Widgets/Routen
dapm_duration=$(step_timer "DAPM-Widgets/Routen prüfen" "
  {
    echo '[DAPM Widgets/Routes - $(date +'%Y-%m-%d %H:%M:%S')]'
    sudo find /sys/kernel/debug/asoc/ \( -name widget -o -name route \) 2>/dev/null | while read -r f; do
      echo '---' \$f '---'
      content=$(sudo cat \$f 2>/dev/null || true)
      if echo "\$content" | grep -qi ac108; then
        echo "\$content" | grep -i ac108
      else
        echo '⚠️ Keine AC108-Einträge in' \$f
      fi
    done
  } > '$LOG_DIR/2_dapm.log'
")

# 3. TDM/Slot-Logs
tdm_duration=$(step_timer "TDM/Slot-Kernel-Logs prüfen" "
  {
    echo '[TDM/Slot Logs - $(date +'%Y-%m-%d %H:%M:%S')]'
    dmesg | grep -i 'tdm\\|slot\\|fmt' | tail -40 2>/dev/null || echo '⚠️ Keine TDM/Slot-Logs gefunden'
  } > '$LOG_DIR/3_tdm_logs.log'
")

# 4. ALSA hwparams-Test (mit Timeout für Aufnahme-Abbruch)
hwparams_duration=$(step_timer "ALSA hwparams-Test (5s Timeout)" "
  {
    echo '[ALSA hwparams Test - $(date +'%Y-%m-%d %H:%M:%S')]'
    timeout 5 arecord -D hw:0,0 --dump-hw-params -f S32_LE -r 16000 -c 4 /dev/null 2>&1
    if [ \${PIPESTATUS[0]} -ne 0 ]; then
      echo '⚠️ hwparams-Test abgebrochen (Timeout oder Fehler)'
    fi
  } > '$LOG_DIR/4_hwparams.log'
")

# 5. Mixer-Controls
mixer_duration=$(step_timer "Mixer-Controls prüfen" "
  {
    echo '[Mixer Controls - $(date +'%Y-%m-%d %H:%M:%S')]'
    amixer -c 0 scontrols 2>/dev/null || echo '⚠️ Keine Mixer-Controls gefunden'
    amixer -c 0 contents 2>/dev/null | head -40
  } > '$LOG_DIR/5_mixer.log'
")

# 6. I2C-Dump (mit Fehlerbehandlung)
i2c_duration=$(step_timer "I2C-Register-Dump" "
  {
    echo '[I2C Register Dump - $(date +'%Y-%m-%d %H:%M:%S')]'
    echo '--- I2C Detection ---'
    i2cdetect -y 1 2>/dev/null || echo '⚠️ i2cdetect fehlgeschlagen'
    echo ''
    echo '--- I2C Register Dump (AC108 @ 0x3b) ---'
    if sudo i2cdump -y 1 0x3b 2>&1; then
      echo 'I2C_DUMP_STATUS=ok'
    else
      echo 'I2C_DUMP_STATUS=busy_or_failed'
    fi
  } > '$LOG_DIR/6_i2c_dump.log'
")

# 6a. I2S und Clock-Konfiguration
i2s_clock_duration=$(step_timer "I2S und Clock-Konfiguration prüfen" "
  {
    echo '[I2S und Clock Config - $(date +'%Y-%m-%d %H:%M:%S')]'
    echo '--- Clock Tree ---'
    cat /sys/kernel/debug/clk/clk_summary 2>/dev/null | grep -i i2s || echo '⚠️ Keine I2S-Clocks gefunden'
    echo ''
    echo '--- I2S Status ---'
    sudo find /sys/kernel/debug/asoc/ -name 'state' 2>/dev/null | while read -r f; do
      echo '---' \$f '---'
      sudo cat \$f 2>/dev/null || echo '⚠️ Fehler beim Lesen'
    done
  } > '$LOG_DIR/6a_i2s_clock.log'
")

# 7. ALSA-Status und Testaufnahme (mit Abbruch nach 3s)
alsa_duration=$(step_timer "ALSA-Status und Testaufnahme (3s)" "
  {
    echo '[ALSA Status - $(date +'%Y-%m-%d %H:%M:%S')]'
    arecord -l 2>/dev/null
    amixer -c 0 controls 2>/dev/null
    echo '--- Testaufnahme (3s) ---'
    timeout 3 arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 '$LOG_DIR/test_recording.wav' 2>&1
    if [ \${PIPESTATUS[0]} -ne 0 ]; then
      echo '⚠️ Testaufnahme abgebrochen (Timeout oder Fehler)'
    else
      sox '$LOG_DIR/test_recording.wav' -n stat 2>&1 | grep -E 'Max level|Length' || echo '⚠️ Aufnahme ist silent oder fehlerhaft'
    fi
  } > '$LOG_DIR/7_alsa_status.log'
")

# Gesamtzeit berechnen
END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

# Metriken erfassen
arecord_list=$(arecord -l 2>/dev/null || true)

# Device detection: accept the common Pi5 names seen in arecord -l
device_detected=$(printf '%s\n' "$arecord_list" | grep -Eci '(seeed4mic|seeed-4mic|ac10x-codec|ac108)' || true)
controls_found=$(amixer -c 0 scontrols 2>/dev/null | grep -c 'ADC[1-4]' || true)
[ -z "$device_detected" ] && device_detected=0
[ -z "$controls_found" ] && controls_found=0
i2c_status=$(grep -m1 'I2C_DUMP_STATUS' "$LOG_DIR/6_i2c_dump.log" 2>/dev/null | cut -d= -f2)
[ -z "$i2c_status" ] && i2c_status="unknown"
recording_max=$(sox "$LOG_DIR/test_recording.wav" -n stat 2>&1 | awk '/Max level/ {print $3}' | head -1)
[ -z "$recording_max" ] && recording_max="0.000000"

# Runtime DT binding detection
dt_sound_compatible=""
dt_binding="unknown"
if [ -r /proc/device-tree/sound/compatible ]; then
  dt_sound_compatible=$(tr '\0' '\n' < /proc/device-tree/sound/compatible 2>/dev/null | sed '/^$/d' | paste -sd ',' -)
  if printf '%s' "$dt_sound_compatible" | grep -q 'simple-audio-card'; then
    dt_binding="simple-audio-card"
  elif printf '%s' "$dt_sound_compatible" | grep -q 'seeed-voicecard'; then
    dt_binding="seeed-voicecard"
  fi
fi

# Root-Cause und Aktionen ableiten
status="success"
error_code=0
root_cause="ok"
required_actions=()

if [ "$device_detected" -eq 0 ]; then
  status="error"
  error_code=-1
  root_cause="ALSA card not detected"
  required_actions+=("arecord -l" "dmesg | grep -i asoc" "sudo dtoverlay seeed-4mic-voicecard-rpi5")
elif [ "$controls_found" -eq 0 ]; then
  status="error"
  error_code=-2
  root_cause="AC108 mixer controls missing"
  required_actions+=("amixer -c 0 scontrols" "sudo alsactl init" "dmesg | grep -i ac108")
elif awk 'BEGIN {exit !("'$recording_max'"+0==0)}'; then
  status="error"
  error_code=-3
  root_cause="capture silent (max level 0)"
  required_actions+=("amixer -c 0 sset \"ADC1 PGA gain\" 31" "timeout 3 arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 /tmp/test.wav" "dmesg | grep -i ac108")
fi

# If DTB was merged but runtime DT is still old, a reboot is required.
if [ "$dt_binding" != "simple-audio-card" ]; then
  required_actions+=("tr -d '\\0' < /proc/device-tree/sound/compatible; echo" "sudo reboot")
fi

# required_actions als JSON-Array
if [ ${#required_actions[@]} -gt 0 ]; then
  actions_json="["
  for i in "${!required_actions[@]}"; do
    action=${required_actions[$i]}
    action_escaped=$(printf '%s' "$action" | sed 's/\\/\\\\/g; s/"/\\"/g')
    if [ "$i" -gt 0 ]; then
      actions_json+="," 
    fi
    actions_json+="\"$action_escaped\""
  done
  actions_json+="]"
else
  actions_json="[]"
fi

# Status-JSON (minimal maschinenlesbar)
cat > "$STATUS_FILE" <<EOF
{
  "status": "$status",
  "error_code": $error_code,
  "key_metrics": {
    "device_detected": $( [ "$device_detected" -gt 0 ] && echo true || echo false ),
    "dt_binding": "$dt_binding",
    "dt_sound_compatible": "$dt_sound_compatible",
    "i2c_status": "$i2c_status",
    "alsa_controls": $controls_found,
    "recording_max_level": "$recording_max"
  },
  "root_cause": "$root_cause",
  "required_actions": $actions_json
}
EOF

# Konsolenausgabe
echo "=========================================="
echo "📊 DIAGNOSE ABGESCHLOSSEN"
echo "=========================================="
echo "📁 Logs gespeichert in: $LOG_DIR/"
echo "⏱️ Gesamtzeit: $TOTAL_DURATION Sekunden"
echo "📋 Schrittzeiten:"
echo "   - Kernel-Module/DT: $module_duration s"
echo "   - DAI-Formate: $dai_duration s"
echo "   - DAPM-Widgets: $dapm_duration s"
echo "   - TDM-Logs: $tdm_duration s"
echo "   - hwparams-Test: $hwparams_duration s"
echo "   - Mixer-Controls: $mixer_duration s"
echo "   - I2C-Dump: $i2c_duration s"
echo "   - I2S/Clock: $i2s_clock_duration s"
echo "   - ALSA-Status/Aufnahme: $alsa_duration s"
echo "📄 Maschinenlesbarer Status: $STATUS_FILE"
echo "=========================================="

if command -v jq >/dev/null 2>&1; then
  jq . "$STATUS_FILE"
else
  cat "$STATUS_FILE"
fi
