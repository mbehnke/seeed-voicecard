#!/bin/bash

# =============================================
# Deep Hardware AC108 Diagnostics
# Check if device truly responds or if it's a ghost
# =============================================

LOG_DIR="/home/adm_behnke/seeed-voicecard/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
JSON_FILE="$LOG_DIR/hardware_diagnosis_${TIMESTAMP}.json"

echo "=== AC108 Hardware Diagnosis ===" >&2
echo "Timestamp: $TIMESTAMP" >&2
echo ""  >&2

# Check which I2C buses exist
echo "1. Checking available I2C buses..." >&2
I2C_BUSES=$(ls /dev/i2c-* 2>/dev/null | grep -oE "[0-9]+$" | sort -u)
echo "   Found buses: $I2C_BUSES" >&2

# Try AC108 on all buses at expected address
AC108_FOUND=0
for bus in $I2C_BUSES; do
    echo ""  >&2
    echo "2. Scanning bus $bus for AC108 at 0x3b..." >&2
    
    result=$(sudo i2cdetect -y "$bus" 2>&1 | grep -A10 "30:")
    echo "$result"  >&2
    
    if echo "$result" | grep -q "3b"; then
        status=$(echo "$result" | grep -oE "3b.*" | awk '{print $2}')
        echo "   Found at 0x3b: $status" >&2
        
        if [ "$status" = "UU" ]; then
            AC108_FOUND=1
            AC108_BUS=$bus
            echo "   ✓ Device in use (normal when kernel driver loaded)" >&2
        fi
    fi
done

echo "" >&2
echo "3. Attempting hardware communication..." >&2

if [ $AC108_FOUND -eq 1 ]; then
    echo "   AC108 claimed on bus $AC108_BUS" >&2
    
    # Try to read via i2cdump (block read)
    echo "   Trying i2cdump (block I2C read)..." >&2
    dump=$(sudo i2cdump -f -y "$AC108_BUS" 0x3b 2>&1 | head -20)
    echo "$dump" | tee -a "$LOG_FILE" >&2
    
    if echo "$dump" | grep -q "XX\|permission\|busy"; then
        echo "   ✗ i2cdump blocked (driver has exclusive access)" >&2
    else
        echo "   ✓ i2cdump succeeded - hardware responds!" >&2
    fi
else
    echo "   ! AC108 not found on any I2C bus" >&2
fi

# Generate JSON output
{
    echo "{"
    echo "  \"status\": \"hardware_check\","
    echo "  \"timestamp\": \"$TIMESTAMP\","
    echo "  \"i2c_buses\": \"$I2C_BUSES\","
    echo "  \"ac108_detected\": $AC108_FOUND,"
    echo "  \"ac108_bus\": ${AC108_BUS:-1},"
    echo "  \"possible_issues\": ["
    
    if [ $AC108_FOUND -eq 0 ]; then
        echo "    \"AC108 chip not detected on any I2C bus\","
        echo "    \"Check physical connections (SDA/SCL lines)\","
        echo "    \"Verify chip power supply (3.3V)\","
        echo "    \"Check for short circuits\""
    else
        echo "    \"AC108 detected but not responding (ghost device)\","
        echo "    \"I2C address might be wrong\","
        echo "    \"Hardware may be powered down\","
        echo "    \"I2C lines may be stuck (SDA/SCL)\""
    fi
    
    echo "  ]"
    echo "}"
} | tee "$JSON_FILE"

echo "" >&2
echo "4. Checking Device Tree for I2C configuration..." >&2
if [ -d /proc/device-tree ]; then
    DT_I2C=$(cat /proc/device-tree/axi/pcie@1000120000/rp1/i2c@74000/status 2>/dev/null | tr '\0' '\n')
    echo "   I2C status: $DT_I2C" >&2
    
    if grep -q "ac108" /proc/device-tree/model 2>/dev/null; then
        echo "   ✓ AC108 referenced in device tree" >&2
    else
        echo "   ! AC108 may not be properly configured in device tree" >&2
    fi
fi

echo "" >&2
echo "JSON output: $JSON_FILE" >&2
