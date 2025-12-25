#!/bin/bash
# Manually enable AC108 module clocks and test recording
# Format: echo [flag]reg[val] > /sys/bus/i2c/devices/1-003b/ac108_debug/ac108
# flag=1: write, flag=0: read
# Example: echo 121091 > ac108  => write 0x91 to reg 0x21 (MOD_CLK_EN)

set -e

DEVICE="/sys/bus/i2c/devices/1-003b/ac108_debug/ac108"
PROJECT_DIR="/home/adm_behnke/seeed-voicecard"
LOG_DIR="$PROJECT_DIR/logs"

mkdir -p "$LOG_DIR"

echo "Enable AC108 module clocks via sysfs..."
echo 121091 | sudo tee "$DEVICE" >/dev/null  # Write 0x91 to MOD_CLK_EN (0x21)
echo 122091 | sudo tee "$DEVICE" >/dev/null  # Write 0x91 to MOD_RST_CTRL (0x22)

sleep 0.2

echo "Recording with manually enabled clocks..."
arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 -d 3 -t wav -q "$LOG_DIR/test_manual_clk_enable.wav"

echo "Analyzing recording..."
sox "$LOG_DIR/test_manual_clk_enable.wav" -n stat 2>&1 | head -n 12 | tee "$LOG_DIR/test_manual_clk_enable_stat.txt"

echo ""
echo "Diagnostic report:"
/home/adm_behnke/seeed-voicecard/diagnose_ac108_json.sh 2>&1 | tail -n 20
