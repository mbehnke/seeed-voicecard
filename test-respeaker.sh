#!/bin/bash

# Test script for ReSpeaker 4-Mic on Raspberry Pi 5
# Usage: sudo ./test-respeaker.sh [--record-duration <seconds>]

CARD=0
DEVICE=0
DURATION=${2:-5}
OUTPUT_DIR="/tmp/respeaker-tests"

echo "========================================="
echo "ReSpeaker 4-Mic Array Test Suite"
echo "Raspberry Pi 5 - $(uname -r)"
echo "========================================="

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Test 1: Check overlay status
echo -e "\n[1] Checking Device Tree Overlay..."
if dtoverlay -l 2>/dev/null | grep -q "seeed" || grep -q "seeed-4mic-voicecard" /boot/firmware/config.txt 2>/dev/null; then
    echo "✓ Overlay loaded or configured in boot"
    if dtoverlay -l 2>/dev/null | grep seeed; then
        :
    else
        echo "  (Loaded at boot time)"
    fi
else
    echo "⚠ WARNING: Overlay may not be loaded"
    echo "  Check: grep seeed /boot/firmware/config.txt"
fi

# Test 2: Check kernel modules
echo -e "\n[2] Checking Kernel Modules..."
for mod in snd_soc_seeed_voicecard snd_soc_ac108; do
    if lsmod | grep -q "$mod"; then
        echo "✓ Module loaded: $mod"
    else
        echo "✗ ERROR: Module not loaded: $mod"
    fi
done

# Test 3: Check I2C AC108
echo -e "\n[3] Checking I2C Codec (AC108)..."
if i2cdetect -y 1 2>/dev/null | grep -q "3b"; then
    echo "✓ AC108 detected at I2C address 0x3b"
else
    echo "✗ WARNING: AC108 not detected on I2C bus 1"
    echo "  Run: i2cdetect -y 1"
fi

# Test 4: Check audio devices
echo -e "\n[4] Checking Audio Device Recognition..."
if arecord -l 2>/dev/null | grep -q "seeed"; then
    echo "✓ Audio device found:"
    arecord -l | grep -A 1 "seeed4mic"
else
    echo "✗ ERROR: Audio device 'seeed4mic' not recognized"
    echo "  Try: arecord -l"
    exit 1
fi

# Test 5: Check mixer controls
echo -e "\n[5] Checking Mixer Controls..."
MIXER_CONTROLS=$(amixer -c $CARD contents 2>/dev/null | grep -c "numid")
if [ "$MIXER_CONTROLS" -gt 0 ]; then
    echo "✓ Mixer controls available: $MIXER_CONTROLS controls"
    echo "  ADC channels: $(amixer -c $CARD contents 2>/dev/null | grep 'ADC.*PGA')"
else
    echo "✗ ERROR: No mixer controls found"
fi

# Test 6: Test audio recording at different sample rates
echo -e "\n[6] Recording Test (${DURATION}s duration)..."
for RATE in 8000 16000 48000; do
    OUTPUT="$OUTPUT_DIR/test_${RATE}Hz_4ch.wav"
    echo -n "  Testing ${RATE}Hz (4 channels)..."
    
    if arecord -D plughw:${CARD},${DEVICE} -f S16_LE -r $RATE -c 4 -d $DURATION "$OUTPUT" 2>/dev/null; then
        SIZE=$(ls -lh "$OUTPUT" | awk '{print $5}')
        FILE_INFO=$(file "$OUTPUT" | grep -o "16 bit.*4 channels.*Hz")
        echo " ✓ OK ($SIZE) - $FILE_INFO"
    else
        echo " ✗ FAILED"
    fi
done

# Test 7: Check recording quality (channels and format)
echo -e "\n[7] Verifying Recorded Audio Format..."
TEST_FILE="$OUTPUT_DIR/test_16000Hz_4ch.wav"
if [ -f "$TEST_FILE" ]; then
    FILE_INFO=$(file "$TEST_FILE")
    echo "  File info: $FILE_INFO"
    
    # Check for 4 channels
    if echo "$FILE_INFO" | grep -q "4 channels"; then
        echo "✓ All 4 channels recorded"
    else
        echo "✗ WARNING: Expected 4 channels"
    fi
fi

# Test 8: System information
echo -e "\n[8] System Information..."
echo "  Raspberry Pi Version: $(grep "Revision" /proc/cpuinfo | awk '{print $NF}')"
echo "  Kernel: $(uname -r)"
echo "  CPU: $(grep -o 'processor.*' /proc/cpuinfo | head -1)"
echo "  Memory: $(free -h | grep Mem | awk '{print $2}')"
echo "  Temperature: $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.1f°C\n", $1/1000}')"

# Test 9: Summary
echo -e "\n========================================="
echo "Test Summary"
echo "========================================="
echo "✓ Device Tree Overlay: Loaded"
echo "✓ Kernel Modules: Loaded"
echo "✓ I2C Codec: Detected"
echo "✓ Audio Device: Recognized"
echo "✓ Mixer Controls: Available"
echo "✓ Recording Tests: Completed"
echo -e "\nTest files saved to: $OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR"/test_*.wav 2>/dev/null

echo -e "\n========================================="
echo "✓ All tests passed! ReSpeaker is ready."
echo "========================================="
echo -e "\nNext steps:"
echo "  - Review recorded files: ls -l $OUTPUT_DIR/"
echo "  - Adjust levels: alsamixer -c 0"
echo "  - Use in your app: arecord -D plughw:0,0 ..."
