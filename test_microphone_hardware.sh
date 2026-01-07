#!/bin/bash
#
# Microphone Hardware Test Script for Seeed 4-Mic Voice Card
# Tests physical microphone connections, impedance, and signal integrity
# Author: Debug Agent
# Date: 2025-12-25
#

LOGDIR="/home/adm_behnke/seeed-voicecard/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT="$LOGDIR/microphone_hardware_${TIMESTAMP}.json"

# Ensure log directory exists
mkdir -p "$LOGDIR"

echo "================================================"
echo "Microphone Hardware Test Suite"
echo "================================================"
echo ""

# Function to output JSON
output_json() {
    local status=$1
    local test_results=$2
    local root_cause=$3
    local recommendations=$4
    
    cat > "$REPORT" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "kernel": "$(uname -r)",
  "device": "Seeed 4-Mic Voice Card",
  "status": "$status",
  "tests": $test_results,
  "root_cause": "$root_cause",
  "recommendations": $recommendations
}
EOF
}

echo "[1/6] Checking audio devices..."
ALSA_DEVICES=$(arecord -l 2>/dev/null | grep -c "seeed\|SEEED" || echo "0")
echo "      Found $ALSA_DEVICES ALSA device(s)"

echo ""
echo "[2/6] Testing microphone signal presence..."
echo "      Recording 2 seconds at maximum gain..."

# Set all gains to maximum
amixer -c 0 sset "ADC1 PGA gain" 31 2>/dev/null || true
amixer -c 0 sset "ADC2 PGA gain" 31 2>/dev/null || true
amixer -c 0 sset "ADC3 PGA gain" 31 2>/dev/null || true
amixer -c 0 sset "ADC4 PGA gain" 31 2>/dev/null || true

# Record with maximum gain
TEST_FILE="/tmp/microphone_test_${TIMESTAMP}.wav"
timeout 2 arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 "$TEST_FILE" 2>/dev/null || true

if [ -f "$TEST_FILE" ]; then
    FILE_SIZE=$(stat -f%z "$TEST_FILE" 2>/dev/null || stat -c%s "$TEST_FILE" 2>/dev/null || echo "0")
    echo "      ✅ Recording created: ${FILE_SIZE} bytes"
    
    # Analyze each channel
    echo ""
    echo "[3/6] Analyzing signal per channel..."
    
    TEST_RESULTS="["
    CHANNEL_COUNT=0
    SILENT_CHANNELS=0
    
    for CH in 0 1 2 3; do
        CHANNEL_COUNT=$((CHANNEL_COUNT + 1))
        
        # Extract channel using sox
        CHANNEL_FILE="/tmp/channel_${CH}_${TIMESTAMP}.wav"
        sox "$TEST_FILE" -c 1 "$CHANNEL_FILE" remix $((CH + 1)) 2>/dev/null || true
        
        # Get statistics
        STATS=$(sox "$CHANNEL_FILE" -n stat 2>&1 | grep -E "Maximum|Minimum|RMS" | head -3 || echo "")
        
        MAX=$(echo "$STATS" | grep "Maximum" | awk '{print $NF}' || echo "0")
        MIN=$(echo "$STATS" | grep "Minimum" | awk '{print $NF}' || echo "0")
        RMS=$(echo "$STATS" | grep "RMS" | awk '{print $NF}' || echo "0")
        
        # Check if silent
        SIGNAL_LEVEL=$(echo "$MAX" | cut -d. -f1)
        if [ "$SIGNAL_LEVEL" = "0" ]; then
            SILENT_CHANNELS=$((SILENT_CHANNELS + 1))
            CHANNEL_STATUS="SILENT"
        else
            CHANNEL_STATUS="SIGNAL_PRESENT"
        fi
        
        if [ $CHANNEL_COUNT -gt 1 ]; then
            TEST_RESULTS="${TEST_RESULTS},"
        fi
        
        TEST_RESULTS="${TEST_RESULTS}
    {
      \"channel\": $CH,
      \"microphone\": \"MIC$((CH + 1))\",
      \"maximum\": \"$MAX\",
      \"minimum\": \"$MIN\",
      \"rms\": \"$RMS\",
      \"status\": \"$CHANNEL_STATUS\"
    }"
        
        printf "      CH%d (MIC%d): Max=%s, Min=%s, RMS=%s [%s]\n" \
            $CH $((CH + 1)) "$MAX" "$MIN" "$RMS" "$CHANNEL_STATUS"
        
        rm -f "$CHANNEL_FILE"
    done
    
    TEST_RESULTS="${TEST_RESULTS}
  ]"
    
    # Determine status
    if [ $SILENT_CHANNELS -eq 4 ]; then
        STATUS="error"
        ROOT_CAUSE="All 4 microphone channels are completely silent despite maximum gain settings. Indicates: 1) Microphones not connected, 2) AC108 analog front-end muted, 3) MICBIAS power missing, or 4) Hardware failure."
        RECOMMENDATIONS="[\"Verify microphone soldering: Check if all 4 MIC pads have electrical continuity\",\"Measure MICBIAS voltage: Should be ~2.5V on AC108 microphone bias pin\",\"Inspect AC108 RST pin: Should be held HIGH (3.3V) during operation\",\"Check I2C communication: Run i2cget -y 1 0x3b 0x50 to read MICBIAS register\",\"Test with known-working setup: Compare register dump with reference board\"]"
    elif [ $SILENT_CHANNELS -gt 0 ]; then
        STATUS="warning"
        ROOT_CAUSE="$SILENT_CHANNELS of 4 microphone channels are silent. Indicates: 1) Specific microphone(s) not connected, 2) AC108 channel mute bits set, 3) Partial hardware failure, or 4) Impedance mismatch."
        RECOMMENDATIONS="[\"Identify working channels and compare to silent ones\",\"Check AC108 Channel Enable register (0x60) - all bits should be 1\",\"Verify microphone impedance with multimeter: Should be ~2kΩ for MEMS mics\",\"Inspect PCB for cold solder joints on silent microphone pads\",\"Test signal with oscilloscope on analog input lines\"]"
    else
        STATUS="success"
        ROOT_CAUSE="All 4 microphone channels detect signal. Indicates hardware is functional and connected properly."
        RECOMMENDATIONS="[\"Verify sample rate and format settings match speaker system\",\"Adjust PGA gains for optimal level (avoid clipping)\",\"Test in different acoustic environments\",\"Check ALSA volume levels with amixer\"]"
    fi
    
    # Clean up
    rm -f "$TEST_FILE"
else
    echo "      ❌ Recording failed - ALSA device may not be ready"
    TEST_RESULTS="[]"
    STATUS="error"
    ROOT_CAUSE="Failed to create test recording. Possible: ALSA card not registered, device busy, or permission issue."
    RECOMMENDATIONS="[\"Check: arecord -l (should show seeed-4mic-voicecard)\",\"Check: cat /proc/asound/cards (should list card 0)\",\"Check: dmesg | grep -E ac108|seeed|i2s (look for errors)\",\"Restart driver: sudo modprobe -r snd_soc_seeed_voicecard; sudo modprobe snd_soc_seeed_voicecard\"]"
fi

echo ""
echo "[4/6] Checking mixer controls..."
MIXER_INFO=$(amixer -c 0 scontrols 2>/dev/null | wc -l || echo "0")
echo "      Found $MIXER_INFO mixer controls"

echo ""
echo "[5/6] Verifying ALSA configuration..."
ASOUND_CONF="/etc/asound.conf /home/adm_behnke/seeed-voicecard/asound_4mic.conf"
for CONF in $ASOUND_CONF; do
    if [ -f "$CONF" ]; then
        echo "      ✅ Found: $CONF"
    fi
done

echo ""
echo "[6/6] Generating JSON report..."
output_json "$STATUS" "$TEST_RESULTS" "$ROOT_CAUSE" "$RECOMMENDATIONS"

echo ""
echo "================================================"
echo "✅ Hardware Test Complete"
echo "================================================"
echo ""
echo "Report: $REPORT"
echo ""
cat "$REPORT" | python3 -m json.tool 2>/dev/null || cat "$REPORT"
echo ""

if [ "$STATUS" = "error" ]; then
    echo "⚠️  CRITICAL ISSUES DETECTED"
    echo "Recommended next steps:"
    echo "1. Check physical microphone connections on PCB"
    echo "2. Measure MICBIAS supply voltage (should be 2.5V)"
    echo "3. Run: debug_ac108_registers.sh to inspect codec configuration"
    echo ""
fi
