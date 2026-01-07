#!/bin/bash

# =============================================
# Detailed I2C Communication Diagnostics
# Minimal JSON output for script analysis
# =============================================

LOG_DIR="/home/adm_behnke/seeed-voicecard/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
JSON_FILE="$LOG_DIR/i2c_diagnostic_${TIMESTAMP}.json"

# --- Helper Functions ---
i2c_cmd() {
    local bus=$1
    local addr=$2
    local reg=$3
    sudo i2cget -y "$bus" "$addr" "$reg" 2>&1
}

json_output() {
    local status=$1
    local error_code=$2
    shift 2
    
    {
        echo "{"
        echo "  \"status\": \"$status\","
        echo "  \"error_code\": $error_code,"
        echo "  \"timestamp\": \"$(date +"%Y-%m%d_%H%M%S")\","
        echo "  \"key_metrics\": {"
        
        # AC108 Detection
        local ac108_detected=0
        if sudo i2cget -y 1 0x3b 0x00 >/dev/null 2>&1; then
            ac108_detected=1
        fi
        echo "    \"ac108_i2c_detect\": $ac108_detected,"
        
        # I2C Adapter Check
        local i2c_adapter=0
        [ -e /dev/i2c-1 ] && i2c_adapter=1
        echo "    \"i2c_adapter_available\": $i2c_adapter,"
        
        # Check for UU in i2cdetect
        local uu_present=0
        sudo i2cdetect -y 1 2>/dev/null | grep -q "UU" && uu_present=1
        echo "    \"device_in_use\": $uu_present,"
        
        # Kernel module check
        local ac108_module=0
        lsmod | grep -q "ac108" && ac108_module=1
        echo "    \"ac108_module_loaded\": $ac108_module,"
        
        # ALSA device check
        local alsa_device=0
        arecord -l 2>/dev/null | grep -q "seeed" && alsa_device=1
        echo "    \"alsa_device_present\": $alsa_device,"
        
        # I2C Controller Check
        local i2c_controller=0
        dmesg | grep -q "i2c_designware" && i2c_controller=1
        echo "    \"i2c_controller_loaded\": $i2c_controller,"
        
        # GPIO I2S Pin Status
        local gpio_correct=0
        gpioinfo 2>/dev/null | grep -q "line.*18.*-" && gpio_correct=1
        echo "    \"gpio_pins_functional\": $gpio_correct"
        echo "  },"
        
        echo "  \"root_cause\": \"$3\","
        echo "  \"required_actions\": ["
        
        # Generate actions based on findings
        if [ $ac108_detected -eq 0 ] && [ $uu_present -eq 1 ]; then
            echo "    \"Device beansprucht aber nicht kommunizierbar: I2C-Bus oder Hardware-Problem\","
            echo "    \"sudo i2cdetect -y 1 | grep -n 3b\","
            echo "    \"sudo dmesg | tail -50 | grep -E 'ac108|i2c'\","
            echo "    \"Prüfe I2C-Adressenkonflikte: lsof /dev/i2c-1\""
        elif [ $ac108_module -eq 1 ] && [ $ac108_detected -eq 0 ]; then
            echo "    \"Treiber lädt aber kann nicht mit Hardware kommunizieren\","
            echo "    \"sudo rmmod snd_soc_ac108\","
            echo "    \"Überprüfe Verdrahtung: I2C_SDA (GPIO2/Pin3), I2C_SCL (GPIO3/Pin5)\","
            echo "    \"Prüfe AC108 Stromversorgung (3.3V auf VDD)\""
        elif [ $uu_present -eq 0 ] && [ $alsa_device -eq 1 ]; then
            echo "    \"ALSA-Gerät existiert aber I2C nicht erreichbar: DTB-Fehler oder Treiber-Binding-Problem\","
            echo "    \"Überprüfe Device-Tree: grep -r ac108 /proc/device-tree\","
            echo "    \"sudo dtc -I fs /proc/device-tree > current_dt.dts | grep -A10 ac108\""
        else
            echo "    \"Unbekannte Konfiguration: Detaillierte Diagnose erforderlich\""
        fi
        
        echo "  ],"
        echo "  \"detailed_checks\": {"
        
        # Detailed checks
        echo "    \"ac108_probe_status\": \"$(dmesg | grep ac108 | tail -5)\","
        echo "    \"i2c_devices_in_use\": \"$(sudo i2cdetect -y 1 2>/dev/null)\","
        echo "    \"loaded_modules\": \"$(lsmod | grep -E 'ac108|seeed|designware' | awk '{print $1}' | paste -sd, -)\""
        echo "  }"
        echo "}"
    } | tee "$JSON_FILE"
}

# =============================================
# Main Diagnostics
# =============================================

echo "=== I2C Detailed Diagnostics ===" >&2
echo "Timestamp: $TIMESTAMP" >&2
echo "" >&2

# Check AC108 via i2cget
echo "1. Testing I2C Communication..." >&2
if sudo i2cget -y 1 0x3b 0x00 >/dev/null 2>&1; then
    chip_id=$(sudo i2cget -y 1 0x3b 0x00 2>/dev/null)
    echo "   ✓ AC108 Chip ID: $chip_id" >&2
    json_output "success" 0 "I2C kommuniziert erfolgreich" "OK"
else
    echo "   ✗ AC108 nicht erreichbar via I2C" >&2
    
    # Check if device is claimed
    if sudo i2cdetect -y 1 2>/dev/null | grep -q "UU"; then
        echo "   ! Gerät ist in Verwendung (UU)" >&2
        json_output "error" -1 "I2C-Gerät beansprucht aber nicht erreichbar - DTB/Treiber-Binding-Problem" "I2C_UNREACHABLE"
    else
        echo "   ! Gerät nicht erkannt" >&2
        json_output "error" -2 "AC108 nicht im I2C-Bus erkannt - Hardware-/Verdrahtungsproblem" "AC108_NOT_DETECTED"
    fi
fi

echo "" >&2
echo "JSON output: $JSON_FILE" >&2
