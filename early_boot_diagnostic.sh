#!/bin/bash

# =============================================
# Early Boot AC108 Diagnostics (systemd service)
# Runs at boot time to capture initialization state
# =============================================

LOG_DIR="/home/adm_behnke/seeed-voicecard/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
JSON_FILE="$LOG_DIR/early_boot_diagnostic_${TIMESTAMP}.json"
LOG_FILE="$LOG_DIR/early_boot_diagnostic_${TIMESTAMP}.log"

{
    echo "=== Early Boot AC108 Diagnostic ==="
    echo "Timestamp: $(date)"
    echo "Kernel: $(uname -r)"
    echo ""
    
    echo "=== Kernel Messages (first 30s) ==="
    dmesg | tail -50
    echo ""
    
    echo "=== Loaded Modules ==="
    lsmod | grep -E "snd|ac108|i2c"
    echo ""
    
    echo "=== I2C Bus Status ==="
    sudo i2cdetect -y 1
    echo ""
    
    echo "=== AC108 Probe Status ==="
    dmesg | grep -E "ac108|seeed_voice_card|failed|error" | tail -20
    echo ""
    
    echo "=== ALSA Devices ==="
    arecord -l 2>&1
    echo ""
    
    echo "=== Clock Status ==="
    cat /sys/kernel/debug/clk/clk_summary 2>/dev/null | grep -E "i2s|audio|mclk" | head -10
    echo ""
    
} | tee "$LOG_FILE"

# JSON output
{
    echo "{"
    echo "  \"status\": \"boot_capture\","
    echo "  \"timestamp\": \"$TIMESTAMP\","
    echo "  \"kernel\": \"$(uname -r)\","
    echo "  \"uptime_seconds\": $(awk '{print int($1)}' /proc/uptime),"
    echo "  \"ac108_module_loaded\": $(lsmod | grep -q 'ac108' && echo 1 || echo 0),"
    echo "  \"ac108_i2c_detected\": $(sudo i2cdetect -y 1 2>/dev/null | grep -q 'UU' && echo 1 || echo 0),"
    echo "  \"ac108_probe_messages\": ["
    
    dmesg | grep -E "ac108|startup|probe" | tail -5 | while read line; do
        echo "    \"$line\","
    done | sed '$s/,$//'
    
    echo "  ],"
    echo "  \"alsa_devices_count\": $(arecord -l 2>/dev/null | grep -c 'card'),"
    echo "  \"seeed_device_detected\": $(arecord -l 2>/dev/null | grep -q 'seeed' && echo 1 || echo 0)"
    echo "}"
} | tee "$JSON_FILE"

echo ""
echo "Log: $LOG_FILE"
echo "JSON: $JSON_FILE"
