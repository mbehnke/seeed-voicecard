#!/bin/bash
###############################################################################
# Seeed 4-Mic Voicecard Complete Diagnostic Script for Raspberry Pi 5
# Generated: 2025-12-25
#
# This script performs comprehensive diagnostics based on extensive analysis
# of the AC108 codec driver and RPi5 I2S interface.
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# JSON output file
JSON_OUTPUT="diagnostic_results_$(date +%Y%m%d_%H%M%S).json"

echo "=============================================="
echo "Seeed 4-Mic Voicecard Diagnostic Tool"
echo "Raspberry Pi 5 - Kernel $(uname -r)"
echo "=============================================="
echo ""

# Initialize JSON
cat > "$JSON_OUTPUT" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "kernel_version": "$(uname -r)",
  "tests": {},
  "critical_findings": [],
  "fixes_applied": [],
  "status": "unknown"
}
EOF

add_json_result() {
    local test_name="$1"
    local status="$2"
    local details="$3"

    python3 <<PYEOF
import json
with open("$JSON_OUTPUT", "r") as f:
    data = json.load(f)
data["tests"]["$test_name"] = {
    "status": "$status",
    "details": "$details"
}
with open("$JSON_OUTPUT", "w") as f:
    json.dump(data, f, indent=2)
PYEOF
}

add_critical_finding() {
    python3 <<PYEOF
import json
with open("$JSON_OUTPUT", "r") as f:
    data = json.load(f)
data["critical_findings"].append("$1")
with open("$JSON_OUTPUT", "w") as f:
    json.dump(data, f, indent=2)
PYEOF
}

###############################################################################
# TEST 1: Hardware Detection
###############################################################################
echo -e "${BLUE}[TEST 1/10]${NC} I2C Hardware Detection"
if i2cdetect -y 1 | grep -q "UU\|3b"; then
    I2C_ADDR=$(i2cdetect -y 1 | grep "30:" | awk '{print $12}')
    if [ "$I2C_ADDR" = "UU" ] || [ "$I2C_ADDR" = "3b" ]; then
        echo -e "${GREEN}✓${NC} AC108 detected at I2C address 0x3b"
        add_json_result "i2c_detection" "PASS" "AC108 found at 0x3b"
    else
        echo -e "${RED}✗${NC} AC108 NOT found at 0x3b"
        add_json_result "i2c_detection" "FAIL" "No device at 0x3b"
        add_critical_finding "AC108 not detected on I2C bus"
    fi
else
    echo -e "${RED}✗${NC} I2C scan failed"
    add_json_result "i2c_detection" "FAIL" "I2C scan error"
fi

###############################################################################
# TEST 2: Kernel Modules
###############################################################################
echo -e "${BLUE}[TEST 2/10]${NC} Kernel Module Status"
MODULES_OK=true

for mod in snd_soc_ac108 snd_soc_seeed_voicecard designware_i2s; do
    if lsmod | grep -q "^$mod"; then
        echo -e "${GREEN}✓${NC} $mod loaded"
    else
        echo -e "${RED}✗${NC} $mod NOT loaded"
        MODULES_OK=false
    fi
done

if $MODULES_OK; then
    add_json_result "kernel_modules" "PASS" "All required modules loaded"
else
    add_json_result "kernel_modules" "FAIL" "Missing modules"
    add_critical_finding "Required kernel modules not loaded"
fi

###############################################################################
# TEST 3: ALSA Sound Card
###############################################################################
echo -e "${BLUE}[TEST 3/10]${NC} ALSA Sound Card Registration"
if arecord -l 2>/dev/null | grep -q "seeed-4mic-voicecard"; then
    CARD_NUM=$(arecord -l | grep "seeed-4mic-voicecard" | head -1 | awk -F: '{print $1}' | awk '{print $2}')
    echo -e "${GREEN}✓${NC} Sound card registered as card $CARD_NUM"
    add_json_result "alsa_card" "PASS" "Card $CARD_NUM registered"
else
    echo -e "${RED}✗${NC} Sound card NOT registered"
    add_json_result "alsa_card" "FAIL" "No seeed-4mic-voicecard found"
    add_critical_finding "ALSA sound card not registered"
fi

###############################################################################
# TEST 4: AC108 Critical Registers
###############################################################################
echo -e "${BLUE}[TEST 4/10]${NC} AC108 Register Configuration"

if [ -d /sys/kernel/debug/regmap/1-003b ]; then
    # Enable cache bypass for direct hardware read
    echo 1 | sudo tee /sys/kernel/debug/regmap/1-003b/cache_bypass >/dev/null 2>&1

    # Read critical registers
    REG_30=$(sudo cat /sys/kernel/debug/regmap/1-003b/registers 2>/dev/null | grep "^30:" | awk '{print $2}')
    REG_39=$(sudo cat /sys/kernel/debug/regmap/1-003b/registers 2>/dev/null | grep "^39:" | awk '{print $2}')
    REG_3C=$(sudo cat /sys/kernel/debug/regmap/1-003b/registers 2>/dev/null | grep "^3c:" | awk '{print $2}')
    REG_61=$(sudo cat /sys/kernel/debug/regmap/1-003b/registers 2>/dev/null | grep "^61:" | awk '{print $2}')
    REG_A0=$(sudo cat /sys/kernel/debug/regmap/1-003b/registers 2>/dev/null | grep "^a0:" | awk '{print $2}')
    REG_90=$(sudo cat /sys/kernel/debug/regmap/1-003b/registers 2>/dev/null | grep "^90:" | awk '{print $2}')

    echo "  I2S_CTRL (0x30):         0x$REG_30"
    echo "  I2S_TX1_CTRL2 (0x39):    0x$REG_39"
    echo "  I2S_TX1_CHMP_CTRL1 (0x3C): 0x$REG_3C"
    echo "  ADC_DIG_EN (0x61):       0x$REG_61"
    echo "  ANA_ADC1_CTRL1 (0xA0):   0x$REG_A0"
    echo "  ADC1_PGA_CTRL (0x90):    0x$REG_90"

    # Validate critical fix
    if [ "$REG_3C" = "e4" ] || [ "$REG_3C" = "E4" ]; then
        echo -e "${GREEN}✓${NC} Channel mapping CORRECT (0xE4)"
        add_json_result "channel_mapping" "PASS" "0x3C = 0xE4 (correct)"
    else
        echo -e "${RED}✗${NC} Channel mapping WRONG (0x$REG_3C, expected 0xE4)"
        add_json_result "channel_mapping" "FAIL" "0x3C = 0x$REG_3C (wrong)"
        add_critical_finding "Channel mapping incorrect - driver fix not applied"
    fi

    # Check PGA gains
    PGA_GAIN=$((16#$REG_90 & 0x1F))
    if [ $PGA_GAIN -eq 0 ]; then
        echo -e "${YELLOW}⚠${NC} PGA Gain is 0 - no amplification!"
        add_critical_finding "PGA gains set to 0 - run: for i in 5 6 7 8; do amixer -c 0 cset numid=\$i 31; done"
    else
        echo -e "${GREEN}✓${NC} PGA Gain: $PGA_GAIN/31"
    fi

else
    echo -e "${YELLOW}⚠${NC} Cannot access regmap debug (need root or debugfs)"
    add_json_result "registers" "SKIP" "No debugfs access"
fi

###############################################################################
# TEST 5: DAI Format Configuration
###############################################################################
echo -e "${BLUE}[TEST 5/10]${NC} DAI Format Configuration"
DAI_FMT=$(dmesg | grep "dai_fmt=" | tail -1 | sed 's/.*dai_fmt=\(0x[0-9a-f]*\).*/\1/')
if [ ! -z "$DAI_FMT" ]; then
    echo "  Current DAI Format: $DAI_FMT"

    # Decode
    if [ "$DAI_FMT" = "0x4001" ]; then
        echo -e "${GREEN}✓${NC} Codec (AC108) is clock master (correct for RPi5)"
        add_json_result "dai_format" "PASS" "0x4001 - AC108 master"
    elif [ "$DAI_FMT" = "0x1001" ]; then
        echo -e "${RED}✗${NC} CPU set as master - will fail on designware-i2s!"
        add_json_result "dai_format" "FAIL" "0x1001 - CPU master not supported"
        add_critical_finding "DAI format wrong - RPi5 designware-i2s requires codec as master"
    else
        echo -e "${YELLOW}⚠${NC} Unknown DAI format: $DAI_FMT"
        add_json_result "dai_format" "WARN" "Unknown format $DAI_FMT"
    fi
fi

###############################################################################
# TEST 6: Audio Recording Test
###############################################################################
echo -e "${BLUE}[TEST 6/10]${NC} Audio Recording Test (3 seconds)"

# Ensure PGA gains are set
for i in 5 6 7 8; do
    amixer -c 0 cset numid=$i 31 >/dev/null 2>&1 || true
done

TEST_FILE="/tmp/diagnostic_test_$(date +%s).wav"
if timeout 3 arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 "$TEST_FILE" >/dev/null 2>&1; then
    if [ -f "$TEST_FILE" ]; then
        MAX_AMP=$(sox "$TEST_FILE" -n stat 2>&1 | grep "Maximum amplitude" | awk '{print $3}')
        RMS_AMP=$(sox "$TEST_FILE" -n stat 2>&1 | grep "RMS.*amplitude" | awk '{print $3}')

        echo "  Maximum amplitude: $MAX_AMP"
        echo "  RMS amplitude:     $RMS_AMP"

        if [ "$MAX_AMP" = "0.000000" ]; then
            echo -e "${RED}✗${NC} NO AUDIO SIGNAL - all samples are zero!"
            add_json_result "audio_recording" "FAIL" "Zero amplitude - no signal"
            add_critical_finding "No audio signal despite correct register configuration"
        else
            echo -e "${GREEN}✓${NC} Audio signal detected!"
            add_json_result "audio_recording" "PASS" "Max: $MAX_AMP, RMS: $RMS_AMP"
        fi

        rm -f "$TEST_FILE"
    fi
else
    echo -e "${RED}✗${NC} Recording failed or timed out"
    add_json_result "audio_recording" "FAIL" "arecord error"
fi

###############################################################################
# TEST 7: ALSA Mixer Controls
###############################################################################
echo -e "${BLUE}[TEST 7/10]${NC} ALSA Mixer Controls"
for i in 5 6 7 8; do
    GAIN=$(amixer -c 0 cget numid=$i 2>/dev/null | grep ": values=" | sed 's/.*values=\([0-9]*\)/\1/')
    echo "  ADC$((i-4)) PGA gain: $GAIN/31"
done

###############################################################################
# TEST 8: Device Tree Status
###############################################################################
echo -e "${BLUE}[TEST 8/10]${NC} Device Tree Configuration"
if [ -f /proc/device-tree/sound/compatible ]; then
    DT_COMPAT=$(cat /proc/device-tree/sound/compatible 2>/dev/null)
    echo "  Sound compatible: $DT_COMPAT"

    if [ -f /proc/device-tree/sound/seeed-voice-card,format ]; then
        DT_FMT=$(cat /proc/device-tree/sound/seeed-voice-card,format 2>/dev/null)
        echo "  Format from DT: $DT_FMT"
    fi

    add_json_result "device_tree" "PASS" "DT nodes present"
else
    echo -e "${YELLOW}⚠${NC} No device tree sound node found"
    add_json_result "device_tree" "WARN" "No DT node"
fi

###############################################################################
# TEST 9: I2S Interface Status
###############################################################################
echo -e "${BLUE}[TEST 9/10]${NC} I2S Interface (designware-i2s)"
if dmesg | grep -q "designware-i2s.*error"; then
    echo -e "${RED}✗${NC} designware-i2s reported errors"
    dmesg | grep "designware-i2s" | tail -3
    add_json_result "i2s_interface" "FAIL" "Errors in dmesg"
else
    echo -e "${GREEN}✓${NC} No I2S interface errors"
    add_json_result "i2s_interface" "PASS" "No errors"
fi

###############################################################################
# TEST 10: Known Fixes Verification
###############################################################################
echo -e "${BLUE}[TEST 10/10]${NC} Verification of Applied Fixes"

echo ""
echo "Checking for known fixes in driver code:"

# Check ac108.c for channel mapping fix
if grep -q "0x0 << 0 | 0x1 << 2 | 0x2 << 4 | 0x3 << 6" ac108.c 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Channel mapping fix (0xE4) present in ac108.c:630"
    python3 <<PYEOF
import json
with open("$JSON_OUTPUT", "r") as f:
    data = json.load(f)
data["fixes_applied"].append("ac108.c:630 - Channel mapping corrected to 0xE4")
with open("$JSON_OUTPUT", "w") as f:
    json.dump(data, f, indent=2)
PYEOF
else
    echo -e "${YELLOW}⚠${NC} Channel mapping fix NOT found in source code"
fi

# Check seeed-voicecard.c for DAI format handling
if grep -q "Keeping codec.*as I2S clock master" seeed-voicecard.c 2>/dev/null; then
    echo -e "${GREEN}✓${NC} DAI format fix present in seeed-voicecard.c"
    python3 <<PYEOF
import json
with open("$JSON_OUTPUT", "r") as f:
    data = json.load(f)
data["fixes_applied"].append("seeed-voicecard.c - Keep AC108 as clock master for RPi5")
with open("$JSON_OUTPUT", "w") as f:
    json.dump(data, f, indent=2)
PYEOF
else
    echo -e "${YELLOW}⚠${NC} DAI format comment NOT found"
fi

###############################################################################
# SUMMARY AND RECOMMENDATIONS
###############################################################################
echo ""
echo "=============================================="
echo "DIAGNOSTIC SUMMARY"
echo "=============================================="

# Determine overall status
OVERALL_STATUS="UNKNOWN"
CRITICAL_COUNT=$(python3 -c "import json; data=json.load(open('$JSON_OUTPUT')); print(len(data.get('critical_findings', [])))")

if [ "$CRITICAL_COUNT" -eq 0 ]; then
    if [ "$MAX_AMP" != "0.000000" ]; then
        OVERALL_STATUS="WORKING"
        echo -e "${GREEN}✓ System Status: WORKING${NC}"
    else
        OVERALL_STATUS="CONFIGURED_NO_SIGNAL"
        echo -e "${YELLOW}⚠ System Status: CONFIGURED BUT NO AUDIO SIGNAL${NC}"
    fi
else
    OVERALL_STATUS="ERRORS"
    echo -e "${RED}✗ System Status: ERRORS DETECTED${NC}"
    echo ""
    echo "Critical Issues Found:"
    python3 -c "import json; data=json.load(open('$JSON_OUTPUT')); [print(f'  - {f}') for f in data.get('critical_findings', [])]"
fi

# Update final status
python3 <<PYEOF
import json
with open("$JSON_OUTPUT", "r") as f:
    data = json.load(f)
data["status"] = "$OVERALL_STATUS"
data["max_amplitude"] = "${MAX_AMP:-0.0}"
data["rms_amplitude"] = "${RMS_AMP:-0.0}"
with open("$JSON_OUTPUT", "w") as f:
    json.dump(data, f, indent=2)
PYEOF

echo ""
echo "Results saved to: $JSON_OUTPUT"

###############################################################################
# RECOMMENDATIONS
###############################################################################
echo ""
echo "=============================================="
echo "RECOMMENDATIONS"
echo "=============================================="

if [ "$MAX_AMP" = "0.000000" ] && [ "$REG_3C" = "e4" ]; then
    echo ""
    echo "DIAGNOSIS: Software configuration is CORRECT, but no audio signal."
    echo ""
    echo "This indicates a HARDWARE or LOW-LEVEL CLOCK issue:"
    echo ""
    echo "1. MCLK (24MHz) Check:"
    echo "   - AC108 requires 24MHz master clock from RPi5"
    echo "   - Use oscilloscope to verify MCLK on HAT pin"
    echo "   - Check: /proc/device-tree/codec-mclk/clock-frequency"
    echo ""
    echo "2. I2S Clock Generation:"
    echo "   - AC108 should generate BCLK and LRCK as master"
    echo "   - Verify with oscilloscope during recording"
    echo "   - Expected: BCLK = 1.024 MHz, LRCK = 16 kHz"
    echo ""
    echo "3. Hardware Connection:"
    echo "   - Check HAT physical connection to GPIO header"
    echo "   - Verify I2S pins: GPIO18(BCLK), GPIO19(LRCK), GPIO20(SDI), GPIO21(SDO)"
    echo "   - Try reseating the HAT"
    echo ""
    echo "4. Alternative Test:"
    echo "   - Try different sample rates: 8000, 44100, 48000 Hz"
    echo "   - Test with: arecord -D hw:0,0 -f S32_LE -r 48000 -c 4 test48k.wav"
    echo ""
elif [ "$REG_3C" != "e4" ]; then
    echo ""
    echo "CRITICAL: Channel mapping fix NOT applied!"
    echo ""
    echo "Run these commands to fix:"
    echo "  cd /home/adm_behnke/seeed-voicecard"
    echo "  make clean && make && sudo make install"
    echo "  sudo modprobe -r snd_soc_seeed_voicecard snd_soc_ac108"
    echo "  sudo modprobe snd_soc_ac108 && sudo modprobe snd_soc_seeed_voicecard"
    echo ""
fi

echo ""
echo "For detailed analysis, review: $JSON_OUTPUT"
echo "=============================================="
