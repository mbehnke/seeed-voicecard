#!/bin/bash
#
# AC108 Register Debug Script for Raspberry Pi 5
# Stops driver, reads AC108 registers, generates JSON report
# Author: Debug Agent
# Date: 2025-12-25
#

set -e

LOGDIR="/home/adm_behnke/seeed-voicecard/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT="$LOGDIR/ac108_debug_${TIMESTAMP}.json"
I2C_BUS=1
I2C_ADDR=0x3b
KERNEL_LOG="/tmp/ac108_kernel_log_${TIMESTAMP}.txt"

# Ensure log directory exists
mkdir -p "$LOGDIR"

# Function to output JSON
output_json() {
    local status=$1
    local error_code=$2
    local device_detected=$3
    local i2c_status=$4
    local registers=$5
    local root_cause=$6
    local actions=$7
    
    cat > "$REPORT" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "kernel": "$(uname -r)",
  "status": "$status",
  "error_code": $error_code,
  "i2c_bus": $I2C_BUS,
  "i2c_addr": "$I2C_ADDR",
  "key_metrics": {
    "device_detected": $device_detected,
    "i2c_bus_status": "$i2c_status",
    "driver_loaded": false
  },
  "registers_read": $registers,
  "root_cause": "$root_cause",
  "required_actions": $actions,
  "kernel_log": "$KERNEL_LOG"
}
EOF
}

echo "================================================"
echo "AC108 Register Debug Tool"
echo "================================================"
echo ""
echo "[1/5] Capturing kernel logs before driver stop..."
dmesg > "$KERNEL_LOG" 2>&1
echo "      Kernel logs saved to: $KERNEL_LOG"

echo ""
echo "[2/5] Stopping audio driver stack..."
echo "      - Stopping arecord/aplay processes..."
killall -9 arecord aplay 2>/dev/null || true
sleep 1

echo "      - Removing kernel modules..."
sudo modprobe -r snd_soc_seeed_voicecard 2>/dev/null || true
sudo modprobe -r snd_soc_ac108 2>/dev/null || true
sudo modprobe -r designware_i2s 2>/dev/null || true
sleep 2

echo ""
echo "[3/5] Checking I2C bus..."
if i2cdetect -y $I2C_BUS 2>/dev/null | grep -q "3b"; then
    echo "      ✅ AC108 detected at $I2C_ADDR"
    DEVICE_DETECTED=true
    I2C_STATUS="device_present"
else
    echo "      ❌ AC108 NOT detected at $I2C_ADDR"
    DEVICE_DETECTED=false
    I2C_STATUS="device_not_found"
fi

echo ""
echo "[4/5] Reading AC108 registers..."

# Create JSON array for register reads
REGISTERS_JSON="["

# Critical registers for audio path
declare -a REGISTERS=(
    "0x00:Power Management 1"
    "0x01:Power Management 2"
    "0x02:Power Management 3"
    "0x03:Power Management 4"
    "0x10:Mode Control"
    "0x11:Clock Control"
    "0x12:Clock Control 2"
    "0x20:Sample Rate"
    # Digital volume per channel
    "0x70:ADC1 Digital Volume"
    "0x71:ADC2 Digital Volume"
    "0x72:ADC3 Digital Volume"
    "0x73:ADC4 Digital Volume"
    # Analog PGA gain controls (per AC108.h)
    "0x90:ANA_PGA1_CTRL (ADC1 PGA)"
    "0x91:ANA_PGA2_CTRL (ADC2 PGA)"
    "0x92:ANA_PGA3_CTRL (ADC3 PGA)"
    "0x93:ANA_PGA4_CTRL (ADC4 PGA)"
    # Analog MICBIAS enable bits are in ANA_ADCx_CTRL1
    "0xA0:ANA_ADC1_CTRL1 (MICBIAS/Enable)"
    "0xA7:ANA_ADC2_CTRL1 (MICBIAS/Enable)"
    "0xAE:ANA_ADC3_CTRL1 (MICBIAS/Enable)"
    "0xB5:ANA_ADC4_CTRL1 (MICBIAS/Enable)"
)

REG_COUNT=0
for reg_entry in "${REGISTERS[@]}"; do
    REG_ADDR=${reg_entry%%:*}
    REG_NAME=${reg_entry#*:}
    REG_DEC=$((16#${REG_ADDR#0x}))
    
    # Try to read register
    if $DEVICE_DETECTED; then
        # Convert address string to integer (remove 0x prefix)
        ADDR_INT=$((16#${I2C_ADDR#0x}))
        VALUE=$(sudo i2cget -y $I2C_BUS $ADDR_INT $REG_DEC 2>/dev/null || echo "0xFF")
        STATUS="ok"
        if [ "$VALUE" = "0xFF" ]; then
            STATUS="read_error"
        fi
    else
        VALUE="N/A"
        STATUS="not_readable"
    fi
    
    # Add to JSON
    if [ $REG_COUNT -gt 0 ]; then
        REGISTERS_JSON="${REGISTERS_JSON},"
    fi
    
    REGISTERS_JSON="${REGISTERS_JSON}
    {
      \"address\": \"$REG_ADDR\",
      \"decimal\": $REG_DEC,
      \"name\": \"$REG_NAME\",
      \"value\": \"$VALUE\",
      \"status\": \"$STATUS\"
    }"
    
    REG_COUNT=$((REG_COUNT + 1))
    
    if $DEVICE_DETECTED; then
        printf "      [%2d] 0x%02X (%s): %s\n" $REG_COUNT "$REG_DEC" "$REG_NAME" "$VALUE"
    fi
done

REGISTERS_JSON="${REGISTERS_JSON}
  ]"

echo ""
echo "[5/5] Generating JSON report..."

# Determine status and root cause
if $DEVICE_DETECTED; then
    STATUS="warning"
    ERROR_CODE=0
    ROOT_CAUSE="Driver removed, AC108 detected on I2C bus. Check register values for muting/configuration issues."
    ACTIONS="[\"sudo i2cset -y 1 0x3b <reg> <value> to configure AC108\",\"Check Power Management registers (0x00-0x03) - all bits must be non-zero\",\"Check Mode Control (0x10) - ADC enable bits\",\"Check Microphone Bias (0x50) - must be non-zero\"]"
else
    STATUS="error"
    ERROR_CODE=-19
    ROOT_CAUSE="AC108 not responding on I2C bus after driver removal. Possible: incorrect I2C address, hardware disconnection, or device hang."
    ACTIONS="[\"Verify I2C wiring and AC108 power supply\",\"Check RST pin on AC108 (should be high 3.3V)\",\"Run: i2cdetect -y 1 to confirm device address\",\"If still not found: measure voltage on I2C lines with multimeter\"]"
fi

# Write JSON report
output_json "$STATUS" "$ERROR_CODE" "$DEVICE_DETECTED" "$I2C_STATUS" "$REGISTERS_JSON" "$ROOT_CAUSE" "$ACTIONS"

echo ""
echo "================================================"
echo "✅ Debug Report Generated"
echo "================================================"
echo ""
echo "Report: $REPORT"
echo ""
cat "$REPORT" | python3 -m json.tool 2>/dev/null || cat "$REPORT"

echo ""
echo "Kernel Log: $KERNEL_LOG"
echo ""
echo "IMPORTANT: Driver modules are currently UNLOADED"
echo "To restore audio: sudo modprobe snd_soc_ac108 && sudo modprobe snd_soc_seeed_voicecard"
echo ""
