#!/bin/bash

##############################################################################
# Enhanced Audio Test Script for Seeed 4-Mic Array on RPi 5
# Purpose: Comprehensive testing with detailed checkpoints and JSON output
# Date: 2025-12-25
##############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGDIR="$SCRIPT_DIR/logs"
TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
LOG_FILE="$LOGDIR/enhanced_test_${TIMESTAMP}.log"
JSON_FILE="$LOGDIR/enhanced_test_${TIMESTAMP}.json"

# Ensure log directory exists
mkdir -p "$LOGDIR"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results storage
declare -A TESTS
declare -a TEST_NAMES
declare -a TEST_STATUS

# Functions
log_test() {
    local name="$1"
    local status="$2"
    local detail="$3"
    
    TEST_NAMES+=("$name")
    TEST_STATUS+=("$status")
    TESTS["$name"]="$detail"
    
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $name" | tee -a "$LOG_FILE"
        [ -n "$detail" ] && echo "  → $detail" | tee -a "$LOG_FILE"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}✗ FAIL${NC}: $name" | tee -a "$LOG_FILE"
        [ -n "$detail" ] && echo "  → $detail" | tee -a "$LOG_FILE"
    else
        echo -e "${YELLOW}⚠ WARN${NC}: $name" | tee -a "$LOG_FILE"
        [ -n "$detail" ] && echo "  → $detail" | tee -a "$LOG_FILE"
    fi
}

checkpoint() {
    local num="$1"
    local desc="$2"
    echo -e "\n${BLUE}[CHECKPOINT $num]${NC} $desc" | tee -a "$LOG_FILE"
    echo "---" >> "$LOG_FILE"
}

##############################################################################
# CHECKPOINT 1: Device Tree Validation
##############################################################################
checkpoint 1 "Device Tree Structure Validation"

# Check if DTB exists
if [ -f /boot/firmware/bcm2712-rpi-5-b.dtb ]; then
    log_test "DTB File Exists" "PASS" "/boot/firmware/bcm2712-rpi-5-b.dtb"
else
    log_test "DTB File Exists" "FAIL" "DTB not found"
    exit 1
fi

# Check sound node in DTB
if dtc -I dtb -O dts /boot/firmware/bcm2712-rpi-5-b.dtb 2>/dev/null | grep -q "compatible = \"seeed-voicecard\""; then
    log_test "Sound Node Compatible" "PASS" "seeed-voicecard found in DTB"
else
    log_test "Sound Node Compatible" "FAIL" "seeed-voicecard not in DTB"
fi

# Check sound node status
SOUND_STATUS=$(dtc -I dtb -O dts /boot/firmware/bcm2712-rpi-5-b.dtb 2>/dev/null | grep -A 20 "sound {" | grep "status" | head -1 | grep -oE '"[^"]*"' | tr -d '"' || echo "unknown")
if [ "$SOUND_STATUS" = "okay" ]; then
    log_test "Sound Node Status" "PASS" "status = okay"
else
    log_test "Sound Node Status" "FAIL" "status = $SOUND_STATUS (expected 'okay')"
fi

# Check format in DTB
FORMAT=$(dtc -I dtb -O dts /boot/firmware/bcm2712-rpi-5-b.dtb 2>/dev/null | grep "seeded-voice-card,format" | grep -oE '"[^"]*"' | tr -d '"' || echo "not found")
if [ "$FORMAT" = "i2s" ]; then
    log_test "DAI Format" "PASS" "format = i2s"
elif [ "$FORMAT" = "dsp_a" ]; then
    log_test "DAI Format" "FAIL" "format = dsp_a (should be i2s)"
else
    log_test "DAI Format" "FAIL" "format = $FORMAT"
fi

# Check clock master
CLOCK_MASTER=$(dtc -I dtb -O dts /boot/firmware/bcm2712-rpi-5-b.dtb 2>/dev/null | grep "seeded-voice-card,bitclock-master" | head -1 || echo "not found")
if echo "$CLOCK_MASTER" | grep -q "0xba"; then
    log_test "Clock Master" "PASS" "CPU (0xba) is clock master"
elif echo "$CLOCK_MASTER" | grep -q "0x106"; then
    log_test "Clock Master" "WARN" "Codec (0x106) is clock master (may cause -22 error)"
else
    log_test "Clock Master" "WARN" "Clock master unclear: $CLOCK_MASTER"
fi

# Check child nodes exist
CPU_NODE=$(dtc -I dtb -O dts /boot/firmware/bcm2712-rpi-5-b.dtb 2>/dev/null | grep "seeded-voice-card,cpu" | wc -l)
CODEC_NODE=$(dtc -I dtb -O dts /boot/firmware/bcm2712-rpi-5-b.dtb 2>/dev/null | grep "seeded-voice-card,codec" | wc -l)

if [ "$CPU_NODE" -gt 0 ]; then
    log_test "CPU DT Node" "PASS" "seeded-voice-card,cpu found"
else
    log_test "CPU DT Node" "FAIL" "seeded-voice-card,cpu not found in DTB"
fi

if [ "$CODEC_NODE" -gt 0 ]; then
    log_test "Codec DT Node" "PASS" "seeded-voice-card,codec found"
else
    log_test "Codec DT Node" "FAIL" "seeded-voice-card,codec not found in DTB"
fi

##############################################################################
# CHECKPOINT 2: Kernel Module Status
##############################################################################
checkpoint 2 "Kernel Module Verification"

# Check if modules are loaded
for mod in snd_soc_seeed_voicecard snd_soc_ac108 snd_soc_simple_card_utils; do
    if lsmod | grep -q "^$mod "; then
        SIZE=$(lsmod | grep "^$mod " | awk '{print $2}')
        log_test "Module Loaded: $mod" "PASS" "Size: $SIZE"
    else
        log_test "Module Loaded: $mod" "FAIL" "Module not loaded"
    fi
done

# Check module file timestamps
for mod_file in snd-soc-seeed-voicecard.ko snd-soc-ac108.ko; do
    MOD_PATH="/lib/modules/$(uname -r)/kernel/sound/soc/bcm/$mod_file"
    if [ -f "$MOD_PATH" ]; then
        MOD_TIME=$(stat -c %y "$MOD_PATH" | cut -d' ' -f1,2)
        log_test "Module File: $mod_file" "PASS" "Modified: $MOD_TIME"
    else
        log_test "Module File: $mod_file" "FAIL" "File not found at $MOD_PATH"
    fi
done

##############################################################################
# CHECKPOINT 3: I2C and AC108 Detection
##############################################################################
checkpoint 3 "I2C Hardware Detection"

# Check I2C bus 1
if i2cdetect -y 1 2>&1 | grep -q "0x3b"; then
    log_test "AC108 I2C Detection" "PASS" "AC108 found at address 0x3b"
else
    log_test "AC108 I2C Detection" "FAIL" "AC108 not detected at 0x3b"
fi

# Check I2C driver loaded
if lsmod | grep -q "^i2c_brcm"; then
    log_test "I2C Driver" "PASS" "i2c_brcm loaded"
else
    log_test "I2C Driver" "WARN" "i2c_brcm not loaded"
fi

##############################################################################
# CHECKPOINT 4: Kernel Messages and Errors
##############################################################################
checkpoint 4 "Kernel Message Analysis"

# Clear old logs for clarity
DMESG_OUTPUT=$(dmesg | tail -100)

# Check for -22 errors
if echo "$DMESG_OUTPUT" | grep -q "error at snd_soc_dai_set_fmt.*-22"; then
    COUNT=$(echo "$DMESG_OUTPUT" | grep -c "error at snd_soc_dai_set_fmt.*-22")
    log_test "DAI Format -22 Error" "FAIL" "$COUNT occurrences of EINVAL (-22) error"
    log_test "Root Cause -22" "WARN" "I2S controller rejecting format - check clock master config"
else
    log_test "DAI Format -22 Error" "PASS" "No -22 errors found"
fi

# Check for deferred probe
if echo "$DMESG_OUTPUT" | grep -q "deferred probe"; then
    log_test "Deferred Probe" "WARN" "Deferred probe detected"
else
    log_test "Deferred Probe" "PASS" "No deferred probe"
fi

# Check for AC108 sysclk messages
if echo "$DMESG_OUTPUT" | grep -q "ac108_set_sysclk.*24000000"; then
    log_test "AC108 SYSCLK" "PASS" "AC108 sysclk set to 24MHz"
else
    log_test "AC108 SYSCLK" "FAIL" "AC108 sysclk not configured"
fi

# Check for seeded-voicecard probe messages
if echo "$DMESG_OUTPUT" | grep -q "seeded_voice_card_dai_link_of"; then
    log_test "DAI Link Parsing" "PASS" "seeded_voice_card_dai_link_of called"
    
    # Check what the error was
    if echo "$DMESG_OUTPUT" | grep -q "Can't find cpu DT node"; then
        log_test "CPU Node Finding" "FAIL" "Child node iteration failed"
        log_test "DT Structure Issue" "WARN" "seeded-voice-card,cpu node not found by iterator"
    fi
else
    log_test "DAI Link Parsing" "FAIL" "seeded_voice_card_dai_link_of never called"
    log_test "Root Cause" "WARN" "Device tree parsing code not executing"
fi

##############################################################################
# CHECKPOINT 5: ALSA Card Registration
##############################################################################
checkpoint 5 "ALSA Card Status"

# Check arecord devices
ARECORD_OUT=$(arecord -l 2>&1)
if echo "$ARECORD_OUT" | grep -q "seeed"; then
    CARD=$(echo "$ARECORD_OUT" | grep seeed | head -1 | awk '{print $1}')
    log_test "ALSA Card Registered" "PASS" "Card found: $CARD"
elif echo "$ARECORD_OUT" | grep -q "No such file"; then
    log_test "ALSA Card Registered" "FAIL" "No ALSA devices found"
else
    log_test "ALSA Card Registered" "FAIL" "seeed-voicecard not in ALSA"
fi

# Check amixer controls
AMIXER_OUT=$(amixer scontrols 2>&1 | head -5)
if echo "$AMIXER_OUT" | grep -q "ADC"; then
    log_test "ALSA Controls" "PASS" "ADC controls detected"
else
    log_test "ALSA Controls" "FAIL" "No AC108 controls found"
fi

##############################################################################
# CHECKPOINT 6: Clock Tree
##############################################################################
checkpoint 6 "Clock Configuration"

# Check I2S clock
if [ -f /sys/kernel/debug/clk/clk_summary ]; then
    if grep -q "i2s" /sys/kernel/debug/clk/clk_summary; then
        I2S_CLK=$(grep "i2s" /sys/kernel/debug/clk/clk_summary | head -1)
        log_test "I2S Clock" "PASS" "$(echo $I2S_CLK | awk '{print $1, $3, $4}')"
    else
        log_test "I2S Clock" "WARN" "i2s clock not in summary"
    fi
else
    log_test "Clock Summary" "SKIP" "/sys/kernel/debug/clk not available"
fi

##############################################################################
# Summary Statistics
##############################################################################
checkpoint 7 "Test Summary"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

for status in "${TEST_STATUS[@]}"; do
    case "$status" in
        PASS) ((PASS_COUNT++)) ;;
        FAIL) ((FAIL_COUNT++)) ;;
        WARN) ((WARN_COUNT++)) ;;
    esac
done

TOTAL=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))

echo "" | tee -a "$LOG_FILE"
echo "═══════════════════════════════════════" | tee -a "$LOG_FILE"
echo "Test Results: $PASS_COUNT/$TOTAL Passed" | tee -a "$LOG_FILE"
echo "═══════════════════════════════════════" | tee -a "$LOG_FILE"
echo "  ✓ Passed: $PASS_COUNT" | tee -a "$LOG_FILE"
echo "  ✗ Failed: $FAIL_COUNT" | tee -a "$LOG_FILE"
echo "  ⚠ Warnings: $WARN_COUNT" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

##############################################################################
# JSON Output
##############################################################################
{
    cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "kernel_version": "$(uname -r)",
  "test_results": {
    "total": $TOTAL,
    "passed": $PASS_COUNT,
    "failed": $FAIL_COUNT,
    "warnings": $WARN_COUNT
  },
  "critical_checks": {
    "dtb_sound_node": "$([ "$SOUND_STATUS" = "okay" ] && echo "OK" || echo "FAIL")",
    "dai_format": "$([ "$FORMAT" = "i2s" ] && echo "I2S" || echo "$FORMAT")",
    "clock_master": "$([ "$CLOCK_MASTER" =~ "0xba" ] && echo "CPU" || echo "CODEC")",
    "ac108_detected": "$(i2cdetect -y 1 2>&1 | grep -q 0x3b && echo "YES" || echo "NO")",
    "alsa_card": "$(arecord -l 2>&1 | grep -q seeed && echo "REGISTERED" || echo "MISSING")",
    "module_loaded": "$(lsmod | grep -q snd_soc_seeed_voicecard && echo "YES" || echo "NO")"
  },
  "recommendations": [
EOF
    
    if [ "$FAIL_COUNT" -gt 0 ]; then
        if [ "$FORMAT" != "i2s" ]; then
            echo '    "Rebuild DTB with format=i2s",'
        fi
        if ! i2cdetect -y 1 2>&1 | grep -q 0x3b; then
            echo '    "Check AC108 I2C wiring",'
        fi
        if ! arecord -l 2>&1 | grep -q seeed; then
            echo '    "Verify DTB dai-link structure - check node names",'
            echo '    "Ensure child nodes have correct names (seeded-voice-card,cpu/codec)",'
        fi
        if echo "$DMESG_OUTPUT" | grep -q "Can't find cpu DT node"; then
            echo '    "Fix: Node finding logic - use of_get_child_by_name or for_each_child_of_node",'
        fi
    fi
    
    cat << 'EOF'
    "Run: dmesg | grep -i seeed for detailed probe messages"
  ],
  "log_file": "$(basename $LOG_FILE)"
}
EOF
} | tee "$JSON_FILE"

echo ""
echo "Full log: $LOG_FILE"
echo "JSON output: $JSON_FILE"
