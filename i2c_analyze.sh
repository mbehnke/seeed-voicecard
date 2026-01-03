#!/bin/bash

# =============================================
# Minimal I2C Analysis Script
# Machine-readable JSON with minimal output
# =============================================

LOG_DIR="/home/adm_behnke/seeed-voicecard/logs"
mkdir -p "$LOG_DIR"

# Collect raw data
I2C_BUS=1
AC108_ADDR=0x3b
TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
JSON_FILE="$LOG_DIR/i2c_analysis_${TIMESTAMP}.json"

# Detect AC108
AC108_DETECTED=0
sudo i2cget -y "$I2C_BUS" "$AC108_ADDR" 0x00 >/dev/null 2>&1 && AC108_DETECTED=1

# Check device in use
DEVICE_IN_USE=0
sudo i2cdetect -y "$I2C_BUS" 2>/dev/null | grep -q "UU" && DEVICE_IN_USE=1

# Check modules
AC108_MODULE=0
lsmod | grep -q "ac108" && AC108_MODULE=1

# Check ALSA
ALSA_DEVICE=0
arecord -l 2>/dev/null | grep -q "seeed" && ALSA_DEVICE=1

# Check kernel logs
KERNEL_SUCCESS=0
dmesg | grep -q "startup.*COMPLETE" && KERNEL_SUCCESS=1

# Determine root cause and status
STATUS="unknown"
ERROR_CODE=0
ROOT_CAUSE="Unbekannte Konfiguration"

if [ $AC108_DETECTED -eq 1 ]; then
    STATUS="success"
    ERROR_CODE=0
    ROOT_CAUSE="I2C funktioniert korrekt"
elif [ $DEVICE_IN_USE -eq 1 ] && [ $AC108_MODULE -eq 1 ]; then
    STATUS="error"
    ERROR_CODE=-1
    ROOT_CAUSE="Device-Tree-Binding-Fehler: Treiber beansprucht aber kann nicht kommunizieren"
elif [ $AC108_MODULE -eq 0 ]; then
    STATUS="error"
    ERROR_CODE=-2
    ROOT_CAUSE="AC108-Treiber nicht geladen oder DTB-Fehler"
elif [ $DEVICE_IN_USE -eq 0 ]; then
    STATUS="error"
    ERROR_CODE=-3
    ROOT_CAUSE="AC108 im I2C-Bus nicht erkannt - Hardware/Verdrahtungsproblem"
else
    STATUS="error"
    ERROR_CODE=-99
    ROOT_CAUSE="Unbekanntes Fehler-Szenario"
fi

# Output minimal JSON
cat > "$JSON_FILE" <<EOF
{
  "status": "$STATUS",
  "error_code": $ERROR_CODE,
  "key_metrics": {
    "ac108_i2c_detected": $AC108_DETECTED,
    "device_in_use": $DEVICE_IN_USE,
    "ac108_module_loaded": $AC108_MODULE,
    "alsa_device_present": $ALSA_DEVICE,
    "kernel_startup_success": $KERNEL_SUCCESS
  },
  "root_cause": "$ROOT_CAUSE",
  "required_actions": [
    $(
        if [ $ERROR_CODE -eq -1 ]; then
            echo "\"Debug I2C-Kommunikation zwischen Treiber und Hardware\","
            echo "\"Prüfe Device-Tree ac108@3b Node (Adresse und Bus)\","
            echo "\"sudo lsof /dev/i2c-1 (wer hält das Device)\","
            echo "\"dmesg | grep -E 'ac108|regmap' (Treiber-Fehler)\""
        elif [ $ERROR_CODE -eq -2 ]; then
            echo "\"Überprüfe DTB-Overlay ist korrekt installiert\","
            echo "\"sudo dtc -I fs /proc/device-tree | grep -A5 ac108\","
            echo "\"Stelle sicher dass ac108 in Device-Tree definiert ist\""
        elif [ $ERROR_CODE -eq -3 ]; then
            echo "\"Prüfe physische I2C-Verdrahtung (GPIO2/3 oder Pin3/5)\","
            echo "\"Überprüfe AC108 Stromversorgung (3.3V)\","
            echo "\"Lese AC108 Adresse mit i2cdetect\","
            echo "\"Versuche sudo i2cget -y 1 0x3b 0x00 manuell\""
        else
            echo "\"Führe erweiterte Diagnose durch\","
            echo "\"Überprüfe dmesg auf Fehler\","
            echo "\"Konsultiere Dokumentation zu Device-Tree\""
        fi
    )
  ]
}
EOF

# Output to stdout
cat "$JSON_FILE"
echo ""
echo "[ Logs gespeichert: $JSON_FILE ]"
