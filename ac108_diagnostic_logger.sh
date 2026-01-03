#!/bin/bash

# =============================================
# AC108 Advanced Diagnostic Logger for Raspberry Pi 5
# Enhanced English version with comprehensive hardware checks
# =============================================

# --- Configuration ---
LOG_DIR="/home/adm_behnke/seeed-voicecard/logs"
LOG_FILE="$LOG_DIR/ac108_diagnostic_$(date +'%Y%m%d_%H%M%S').log"
JSON_FILE="$LOG_DIR/ac108_diagnostic_$(date +'%Y%m%d_%H%M%S').json"
MIN_JSON_FILE="$LOG_DIR/ac108_diag_minimal_$(date +'%Y%m%d_%H%M%S').json"
I2C_BUS=1
AC108_ADDR=0x3b
TEST_DURATION=3  # seconds
DEVICE_TREE="/proc/device-tree"
I2S_CONTROLLER="1f000a0000.i2s"

# --- Create log directory ---
mkdir -p "$LOG_DIR"

# --- JSON Header for structured output ---
json_start() {
    echo '{
    "metadata": {
        "timestamp": "'$(date +"%Y-%m%d_%H%M%S")'",
        "hostname": "'$(hostname)'",
        "kernel": "'$(uname -r)'"
    },'
}

# --- Logging function with timestamp and uptime ---
log() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local uptime=$(awk '{print $1}' /proc/uptime)
    echo "[$timestamp] [Uptime: ${uptime}s] $1" | tee -a "$LOG_FILE"
}

json_log() {
    echo "    \"$1\": \"$2\"," >> "$JSON_FILE"
}

json_array_start() {
    echo "    \"$1\": [" >> "$JSON_FILE"
}

json_array_end() {
    echo "    ]," >> "$JSON_FILE"
}

json_object_start() {
    echo "        {" >> "$JSON_FILE"
}

json_object_end() {
    echo "        }," >> "$JSON_FILE"
}

# --- Initialize JSON file ---
json_start > "$JSON_FILE"

# --- Header ---
log "============================================="
log "AC108 Advanced Diagnostic Log - Raspberry Pi 5"
log "============================================="
log ""

# --- System Information ---
log "=== SYSTEM INFORMATION ==="
uname -a | tee -a "$LOG_FILE"
json_log "system_info" "$(uname -a)"
log ""

# --- Uptime and System Load ---
log "=== UPTIME & SYSTEM LOAD ==="
uptime | tee -a "$LOG_FILE"
json_log "uptime" "$(uptime)"
log ""

# --- Kernel Modules ---
log "=== KERNEL MODULES (Audio/I2C) ==="
lsmod | grep -E "snd|i2c|ac108" | tee -a "$LOG_FILE"
json_array_start "kernel_modules"
while IFS= read -r line; do
    json_object_start
    echo "            \"module\": \"$line\"" >> "$JSON_FILE"
    json_object_end
done < <(lsmod | grep -E "snd|i2c|ac108")
json_array_end
log ""

# --- I2C Bus Scan ---
log "=== I2C BUS SCAN (Bus $I2C_BUS) ==="
i2c_scan=$(sudo i2cdetect -y "$I2C_BUS" 2>&1)
echo "$i2c_scan" | tee -a "$LOG_FILE"
json_log "i2c_scan" "$i2c_scan"

# Check for I2C adapter status
if ls /dev/i2c-* 1> /dev/null 2>&1; then
    log "✓ I2C adapter available: $(ls /dev/i2c-*)"
    json_log "i2c_adapter" "available"
else
    log "✗ No I2C adapter found"
    json_log "i2c_adapter" "unavailable"
fi
log ""

# --- AC108 Detection ---
log "=== AC108 DETECTION ==="
skip_i2c_reads=0

# ENHANCED: Check i2cdetect status first
if echo "$i2c_scan" | grep -q "UU"; then
    log "⚠️  CRITICAL: Device shows 'UU' at 0x3b (driver owns device but USERSPACE I2C LOCKED)"
    json_log "ac108_detection" "device_locked_uu"
    log "This means:"
    log "  ✓ Kernel driver successfully probed device"
    log "  ✓ Driver is controlling the device (hence 'UU')"
    log "  ✗ But userspace i2cget cannot access device"
    log "  Likely cause: Regmap stuck in cache-only or driver not releasing I2C for userspace"
    log ""
    log "DIAGNOSIS: Device is CLAIMED BY KERNEL but hardware doesn't respond"
    skip_i2c_reads=1
    json_log "ac108_diagnosis" "kernel_owns_device_but_unreachable"
elif echo "$i2c_scan" | grep -q " 3b"; then
    log "✓ AC108 detected at address $AC108_ADDR (device accessible)"
    json_log "ac108_detection" "success"
else
    log "✗ AC108 NOT detected at address $AC108_ADDR (no response)"
    json_log "ac108_detection" "not_detected"
fi

# Try to read chip ID with detailed error checking unless kernel owns the bus
log "--- Attempting I2C Read (chip ID @ 0x00) ---"
if [ "$skip_i2c_reads" -eq 1 ]; then
    log "Skipping i2cget because driver currently owns device (UU)"
    json_log "i2cget_status" "skipped_driver_owns_bus"
else
    i2c_read_output=$(sudo i2cget -y "$I2C_BUS" "$AC108_ADDR" 0x00 2>&1)
    i2c_read_status=$?

    if [ $i2c_read_status -eq 0 ]; then
        chip_id=$(echo "$i2c_read_output" | awk '{print $1}')
        log "✓ i2cget SUCCESS: Chip ID = 0x$chip_id"
        json_log "i2cget_status" "success"
        json_log "ac108_chip_id" "0x$chip_id"
    else
        log "✗ i2cget FAILED with error:"
        log "   Output: $i2c_read_output"
        log "   Return code: $i2c_read_status"
        json_log "i2cget_status" "failed"
        json_log "i2cget_error" "$i2c_read_output"
		
        # Analyze error
        if echo "$i2c_read_output" | grep -q "Device or resource busy"; then
            log "   ERROR TYPE: 'Device or resource busy' - REGCACHE/DRIVER ISSUE"
            log "   EXPLANATION: Kernel driver has exclusive access, possibly in cache-only mode"
            json_log "i2c_error_type" "device_busy_regcache_issue"
        elif echo "$i2c_read_output" | grep -q "No such device"; then
            log "   ERROR TYPE: 'No such device' - HARDWARE NOT RESPONDING"
            json_log "i2c_error_type" "no_device"
        elif echo "$i2c_read_output" | grep -q "Connection refused"; then
            log "   ERROR TYPE: 'Connection refused' - I2C BUS ISSUE"
            json_log "i2c_error_type" "connection_refused"
        fi
    fi
fi
log ""

# Additional I2C troubleshooting
log "--- I2C BUS DIAGNOSTICS ---"
if dmesg | grep -q "i2c_designware"; then
    log "✓ I2C controller: DesignWare (loaded)"
    json_log "i2c_controller" "designware_loaded"
else
    log "✗ I2C controller: Not detected in kernel logs"
    json_log "i2c_controller" "not_detected"
fi

# Check for I2C errors in recent kernel logs
i2c_errors=$(dmesg | grep -i "i2c.*error\|i2c.*failed" | tail -3)
if [ -n "$i2c_errors" ]; then
    log "⚠️  Recent I2C errors in kernel log:"
    echo "$i2c_errors" | while read line; do
        log "   $line"
    done
    json_log "recent_i2c_errors" "$i2c_errors"
fi

# Check /proc/devices for I2C
if [ -f /proc/devices ]; then
    i2c_device_number=$(grep "i2c-dev" /proc/devices | awk '{print $1}')
    if [ -n "$i2c_device_number" ]; then
        log "✓ i2c-dev registered as device $i2c_device_number"
        json_log "i2c_dev_major_number" "$i2c_device_number"
    fi
fi
log ""

# --- ALSA Devices ---
log "=== ALSA DEVICES ==="
alsa_devices_output=$(arecord -l 2>&1)
echo "$alsa_devices_output" | tee -a "$LOG_FILE"
json_log "alsa_devices" "$alsa_devices_output"
log ""

# --- Device Tree Configuration ---
log "=== DEVICE TREE CONFIGURATION ==="
if [ -d "$DEVICE_TREE" ]; then
    log "Device Tree directory: $DEVICE_TREE"
    json_log "device_tree_path" "$DEVICE_TREE"

    # Check sound node
    if [ -d "$DEVICE_TREE/sound" ]; then
        log "✓ Sound node present in Device Tree"
        json_log "sound_node" "present"
        cat "$DEVICE_TREE/sound/compatible" 2>/dev/null | tr '\0' '\n' | tee -a "$LOG_FILE"
    else
        log "✗ Sound node missing in Device Tree"
        json_log "sound_node" "missing"
    fi

    # Check I2S controller
    if [ -d "$DEVICE_TREE/axi/pcie@1000120000/rp1/i2s@a0000" ]; then
        log "✓ I2S controller present in Device Tree"
        json_log "i2s_controller" "present"

        # Check status and pinctrl
        status=$(cat "$DEVICE_TREE/axi/pcie@1000120000/rp1/i2s@a0000/status" 2>/dev/null | tr '\0' '\n')
        pinctrl=$(cat "$DEVICE_TREE/axi/pcie@1000120000/rp1/i2s@a0000/pinctrl-0" 2>/dev/null | od -A x -t x1)
        log "  Status: $status"
        log "  Pinctrl: $pinctrl"
        json_log "i2s_status" "$status"
        json_log "i2s_pinctrl" "$pinctrl"
    else
        log "✗ I2S controller missing in Device Tree"
        json_log "i2s_controller" "missing"
    fi
    log ""

    # Check pinmux configuration
    log "--- PINMUX CONFIGURATION (I2S0: GPIO18-21) ---"
    if [ -f "$DEVICE_TREE/axi/pcie@1000120000/rp1/gpio@d0000/rp1_i2s0_18_21/function" ]; then
        i2s_function=$(cat "$DEVICE_TREE/axi/pcie@1000120000/rp1/gpio@d0000/rp1_i2s0_18_21/function" 2>/dev/null | tr '\0' '\n')
        log "I2S0 Pinmux function: $i2s_function"
        json_log "i2s0_pinmux_function" "$i2s_function"

        # Verify pin configuration
        if [ "$i2s_function" = "i2s0" ]; then
            log "✓ Pinmux correctly configured for I2S0"
            json_log "i2s0_pinmux_status" "correct"
        else
            log "✗ Pinmux NOT configured for I2S0 (current: $i2s_function)"
            json_log "i2s0_pinmux_status" "incorrect"
        fi
    else
        log "✗ I2S0 pinmux configuration missing"
        json_log "i2s0_pinmux_function" "missing"
        json_log "i2s0_pinmux_status" "missing"
    fi
    log ""
else
    log "✗ Device Tree directory not accessible: $DEVICE_TREE"
    json_log "device_tree_access" "failed"
fi

# --- GPIO Configuration (I2S Pins) ---
log "=== GPIO CONFIGURATION (I2S PINS) ==="
gpio_info=$(gpioinfo 2>/dev/null | grep -E "line.*(18|19|20|21)")
echo "$gpio_info" | tee -a "$LOG_FILE"
json_log "gpio_i2s_pins" "$gpio_info"

# Check if pins are configured as inputs
if echo "$gpio_info" | grep -q "input"; then
    log "✗ I2S GPIO pins configured as INPUT (should be I2S function)"
    json_log "i2s_gpio_status" "input_mode"
else
    log "✓ I2S GPIO pins properly configured"
    json_log "i2s_gpio_status" "correct"
fi
log ""

# --- Clock Configuration ---
log "=== CLOCK CONFIGURATION ==="
if [ -d "/sys/kernel/debug/clk" ]; then
    log "--- I2S CLOCKS ---"
    i2s_clocks=$(cat /sys/kernel/debug/clk/clk_summary | grep -E "i2s|audio")
    echo "$i2s_clocks" | tee -a "$LOG_FILE"
    json_log "i2s_clocks" "$i2s_clocks"

    # Check if I2S clock is running
    if echo "$i2s_clocks" | grep -q "clk_i2s.*[1-9]"; then
        log "✓ I2S clock is running"
        json_log "i2s_clock_status" "running"
    else
        log "✗ I2S clock NOT running"
        json_log "i2s_clock_status" "not_running"
    fi

    log "--- MCLK CLOCK (if present) ---"
    mclk_clocks=$(cat /sys/kernel/debug/clk/clk_summary | grep -i "mclk")
    echo "$mclk_clocks" | tee -a "$LOG_FILE"
    json_log "mclk_clocks" "$mclk_clocks"

    # Check MCLK status
    if echo "$mclk_clocks" | grep -q "codec-mclk.*[1-9]"; then
        log "✓ MCLK is available"
        json_log "mclk_status" "available"
    else
        log "✗ MCLK not available or not running"
        json_log "mclk_status" "unavailable"
    fi
else
    log "✗ Clock debug interface not available"
    json_log "clock_debug_interface" "unavailable"
fi
log ""

# --- AC108 Register Dump ---
log "=== AC108 REGISTER DUMP ==="
declare -A reg_names=(
    ["0x00"]="CHIP_ID" ["0x01"]="CHIP_REV"
    ["0x10"]="PLL_CTRL1" ["0x11"]="PLL_CTRL2" ["0x12"]="PLL_CTRL3" ["0x13"]="PLL_CTRL4"
    ["0x14"]="PLL_CTRL5" ["0x16"]="PLL_CTRL6" ["0x17"]="PLL_CTRL7" ["0x18"]="PLL_LOCK_CTRL"
    ["0x20"]="SYSCLK_CTRL" ["0x21"]="MOD_CLK_EN" ["0x22"]="MOD_RST_CTRL"
    ["0x30"]="I2S_CTRL" ["0x31"]="I2S_BCLK_CTRL" ["0x32"]="I2S_LRCK_CTRL1"
    ["0x33"]="I2S_LRCK_CTRL2" ["0x34"]="I2S_FMT_CTRL1" ["0x35"]="I2S_FMT_CTRL2"
    ["0x36"]="I2S_FMT_CTRL3" ["0x60"]="ADC1_CTRL1" ["0x61"]="ADC1_CTRL2"
    ["0x62"]="ADC1_DVOL" ["0x64"]="ADC2_CTRL1" ["0x65"]="ADC2_CTRL2"
    ["0x66"]="ADC2_DVOL" ["0x68"]="ADC3_CTRL1" ["0x69"]="ADC3_CTRL2"
    ["0x6A"]="ADC3_DVOL" ["0x6C"]="ADC4_CTRL1" ["0x6D"]="ADC4_CTRL2"
    ["0x6E"]="ADC4_DVOL" ["0x70"]="ADC_DIG_EN"
)

json_array_start "ac108_registers"
register_read_success=0
register_read_failed=0
first_error_logged=0

if [ "$skip_i2c_reads" -eq 1 ]; then
    log "Skipping register reads because kernel currently owns I2C device"
    json_log "register_communication" "skipped_driver_owns_bus"
else

# OPTIMIZED: Read fewer registers but with better error analysis
key_registers=(
    "0x00:CHIP_ID"
    "0x20:SYSCLK_CTRL"
    "0x21:MOD_CLK_EN"
    "0x22:MOD_RST_CTRL"
    "0x30:I2S_CTRL"
)

log "--- KEY REGISTERS (5 critical registers) ---"
for reg_pair in "${key_registers[@]}"; do
    reg="${reg_pair%:*}"
    name="${reg_pair#*:}"
    
    json_object_start
    echo "            \"register\": \"$name\"," >> "$JSON_FILE"
    echo "            \"address\": \"$reg\"," >> "$JSON_FILE"

    # Try read with timeout
    reg_output=$(timeout 1 sudo i2cget -y "$I2C_BUS" "$AC108_ADDR" "$reg" 2>&1)
    reg_status=$?
    
    if [ $reg_status -eq 0 ] && [ -n "$reg_output" ]; then
        value=$(echo "$reg_output" | awk '{print $1}')
        log "$name ($reg): 0x$value ✓"
        echo "            \"value\": \"0x$value\"," >> "$JSON_FILE"
        echo "            \"status\": \"success\"" >> "$JSON_FILE"
        ((register_read_success++))
    else
        error_msg=$(echo "$reg_output" | head -1)
        log "$name ($reg): ✗ FAILED - $error_msg"
        echo "            \"value\": \"N/A\"," >> "$JSON_FILE"
        echo "            \"status\": \"failed\"," >> "$JSON_FILE"
        echo "            \"error\": \"$error_msg\"" >> "$JSON_FILE"
        ((register_read_failed++))
        
        # Log first error in detail
        if [ $first_error_logged -eq 0 ]; then
            log ""
            log "=== FIRST REGISTER ERROR ANALYSIS ==="
            log "Register: $name ($reg)"
            log "Command: i2cget -y 1 0x3b $reg"
            log "Output: $error_msg"
            
            if echo "$error_msg" | grep -q "Device or resource busy"; then
                log "DIAGNOSIS: Device is busy (kernel driver has exclusive access)"
                log "ROOT CAUSE: Likely regcache issue or driver not releasing I2C"
                log "ACTION: Check if regcache_cache_only is disabled in startup"
                json_log "register_error_root_cause" "regcache_device_busy"
            elif echo "$error_msg" | grep -q "No such file"; then
                log "DIAGNOSIS: Device file missing or not accessible"
                json_log "register_error_root_cause" "device_file_missing"
            fi
            log "=== END ANALYSIS ==="
            log ""
            first_error_logged=1
        fi
    fi
    json_object_end
done

log ""
log "--- READING REMAINING REGISTERS (28 additional) ---"
# Read remaining registers without individual logging to speed up
for reg in 0x01 0x10 0x11 0x12 0x13 0x14 0x16 0x17 0x18 0x20 0x31 0x32 0x33 0x34 0x35 0x36 0x60 0x61 0x62 0x64 0x65 0x66 0x68 0x69 0x6A 0x6C 0x6D 0x6E 0x70; do
    
    reg_output=$(timeout 1 sudo i2cget -y "$I2C_BUS" "$AC108_ADDR" "$reg" 2>&1)
    reg_status=$?
    
    json_object_start
    echo "            \"address\": \"$reg\"," >> "$JSON_FILE"
    
    if [ $reg_status -eq 0 ] && [ -n "$reg_output" ]; then
        value=$(echo "$reg_output" | awk '{print $1}')
        echo "            \"value\": \"0x$value\"," >> "$JSON_FILE"
        echo "            \"status\": \"success\"" >> "$JSON_FILE"
        ((register_read_success++))
    else
        echo "            \"value\": \"N/A\"," >> "$JSON_FILE"
        echo "            \"status\": \"failed\"" >> "$JSON_FILE"
        ((register_read_failed++))
    fi
    json_object_end
done
json_array_end

# Summary of register access with ROOT CAUSE analysis
log ""
log "=== REGISTER READ SUMMARY ==="
log "Successful: $register_read_success"
log "Failed: $register_read_failed"
json_log "register_read_success" "$register_read_success"
json_log "register_read_failed" "$register_read_failed"

if [ $register_read_failed -eq 33 ]; then
    log ""
    log "🔴 CRITICAL: ALL 33 REGISTERS FAILED TO READ"
    log ""
    log "ROOT CAUSE ANALYSIS:"
    log "- Device shows 'UU' in i2cdetect (kernel owns it)"
    log "- Kernel logs show successful startup"
    log "- But userspace I2C reads all fail"
    log ""
    log "MOST LIKELY CAUSE:"
    log "1. Regcache stuck in cache-only mode AFTER startup"
    log "   → Kernel uses cache, hardware not accessible to userspace"
    log "2. OR: I2C exclusive access lock from kernel not released"
    log "3. OR: Driver probe succeeded but init incomplete"
    log ""
    log "QUICK FIX ATTEMPT:"
    log "Try reloading modules: sudo rmmod snd_soc_ac108; sudo modprobe snd_soc_ac108"
    log ""
    json_log "critical_analysis" "all_registers_failed_kernel_owns_device"
elif [ $register_read_success -gt 0 ]; then
    log "✓ Some registers readable - I2C communication partially working"
    json_log "i2c_status" "partially_working"
fi
log ""

# Only proceed with analysis if we could read some registers
if [ $register_read_success -gt 0 ]; then
    # --- PLL Status Analysis ---
    log "=== PLL STATUS ANALYSIS ==="
    pll_ctrl1=$(sudo i2cget -y "$I2C_BUS" "$AC108_ADDR" 0x10 2>/dev/null | awk '{print $1}')
    if [ -n "$pll_ctrl1" ]; then
        pll_locked=$(( (pll_ctrl1 & 0x04) >> 2 ))
        pll_en=$(( pll_ctrl1 & 0x01 ))
        pll_com_en=$(( (pll_ctrl1 & 0x02) >> 1 ))

        log "PLL_CTRL1 = 0x$pll_ctrl1"
        log "  PLL_EN (Bit 0): $pll_en"
        log "  PLL_COM_EN (Bit 1): $pll_com_en"
        log "  PLL_LOCKED (Bit 2): $pll_locked"

        json_log "pll_ctrl1" "0x$pll_ctrl1"
        json_log "pll_en" "$pll_en"
        json_log "pll_com_en" "$pll_com_en"
        json_log "pll_locked" "$pll_locked"

        if [ "$pll_locked" -eq 1 ]; then
            log "✓ PLL is LOCKED"
            json_log "pll_status" "locked"
        else
            log "✗ PLL is NOT locked"
            json_log "pll_status" "unlocked"

            # Additional PLL troubleshooting
            log "--- PLL TROUBLESHOOTING ---"
            if [ "$pll_en" -ne 1 ]; then
                log "  Issue: PLL not enabled (PLL_EN=0)"
                json_log "pll_issue" "not_enabled"
            fi

            if [ "$pll_com_en" -ne 1 ]; then
                log "  Issue: PLL common not enabled (PLL_COM_EN=0)"
                json_log "pll_issue" "common_not_enabled"
            fi
        fi
    else
        log "✗ PLL_CTRL1 FAILED TO READ"
        json_log "pll_status" "read_failed"
    fi
    log ""

    # --- SYSCLK_CTRL Analysis ---
    log "=== SYSCLK_CTRL ANALYSIS ==="
    sysclk_ctrl=$(sudo i2cget -y "$I2C_BUS" "$AC108_ADDR" 0x20 2>/dev/null | awk '{print $1}')
    if [ -n "$sysclk_ctrl" ]; then
        pllclk_en=$(( (sysclk_ctrl & 0x01) ))
        pllclk_src=$(( (sysclk_ctrl & 0x02) >> 1 ))
        sysclk_src=$(( (sysclk_ctrl & 0x04) >> 2 ))

        log "SYSCLK_CTRL = 0x$sysclk_ctrl"
        log "  PLLCLK_EN (Bit 0): $pllclk_en"
        log "  PLLCLK_SRC (Bit 1): $pllclk_src (0=MCLK, 1=BCLK)"
        log "  SYSCLK_SRC (Bit 2): $sysclk_src"

        json_log "sysclk_ctrl" "0x$sysclk_ctrl"
        json_log "pllclk_en" "$pllclk_en"
        json_log "pllclk_src" "$pllclk_src"
        json_log "sysclk_src" "$sysclk_src"

        if [ "$pllclk_en" -ne 1 ]; then
            log "✗ PLLCLK not enabled"
            json_log "sysclk_issue" "pllclk_not_enabled"
        fi
    else
        log "✗ SYSCLK_CTRL FAILED TO READ"
        json_log "sysclk_ctrl" "read_failed"
    fi
    log ""

    # --- I2S_CTRL Analysis (BCLK/LRCK Inputs) ---
    log "=== I2S_CTRL ANALYSIS ==="
    i2s_ctrl=$(sudo i2cget -y "$I2C_BUS" "$AC108_ADDR" 0x30 2>/dev/null | awk '{print $1}')
    if [ -n "$i2s_ctrl" ]; then
        bclk_ioen=$(( (i2s_ctrl & 0x80) >> 7 ))
        lrck_ioen=$(( (i2s_ctrl & 0x40) >> 6 ))
        bclk_oen=$(( (i2s_ctrl & 0x20) >> 5 ))
        lrck_oen=$(( (i2s_ctrl & 0x10) >> 4 ))

        log "I2S_CTRL = 0x$i2s_ctrl"
        log "  BCLK_IOEN (Bit 7): $bclk_ioen"
        log "  LRCK_IOEN (Bit 6): $lrck_ioen"
        log "  BCLK_OEN (Bit 5): $bclk_oen"
        log "  LRCK_OEN (Bit 4): $lrck_oen"

        json_log "i2s_ctrl" "0x$i2s_ctrl"
        json_log "bclk_ioen" "$bclk_ioen"
        json_log "lrck_ioen" "$lrck_ioen"
        json_log "bclk_oen" "$bclk_oen"
        json_log "lrck_oen" "$lrck_oen"

        if [ "$bclk_ioen" -eq 1 ] && [ "$lrck_ioen" -eq 1 ]; then
            log "✓ BCLK/LRCK inputs are ENABLED (Slave Mode)"
            json_log "bclk_lrck_inputs" "enabled"
        else
            log "✗ BCLK/LRCK inputs are DISABLED (required for Slave Mode!)"
            json_log "bclk_lrck_inputs" "disabled"
        fi
    else
        log "✗ I2S_CTRL FAILED TO READ"
        json_log "i2s_ctrl" "read_failed"
    fi
    log ""

    # --- ADC Configuration ---
    log "=== ADC CONFIGURATION ==="
    adc_dig_en=$(sudo i2cget -y "$I2C_BUS" "$AC108_ADDR" 0x70 2>/dev/null | awk '{print $1}')
    if [ -n "$adc_dig_en" ]; then
        log "ADC_DIG_EN = 0x$adc_dig_en"
        json_log "adc_dig_en" "0x$adc_dig_en"

        if [ "$adc_dig_en" -ne 0 ]; then
            log "✓ ADC digital block enabled"
            json_log "adc_digital_status" "enabled"
        else
            log "✗ ADC digital block disabled"
            json_log "adc_digital_status" "disabled"
        fi
    else
        log "✗ ADC_DIG_EN FAILED TO READ"
        json_log "adc_dig_en" "read_failed"
    fi

    for adc in {1..4}; do
        ctrl1_reg=$((0x60 + (($adc-1)*4)))
        ctrl1=$(sudo i2cget -y "$I2C_BUS" "$AC108_ADDR" $ctrl1_reg 2>/dev/null | awk '{print $1}')
        if [ -n "$ctrl1" ]; then
            adc_en=$(( (ctrl1 & 0x80) >> 7 ))
            log "ADC${adc}_CTRL1 = 0x$ctrl1 (ADC_EN = $adc_en)"
            json_log "adc${adc}_ctrl1" "0x$ctrl1"
            json_log "adc${adc}_en" "$adc_en"

            if [ "$adc_en" -ne 1 ]; then
                log "  ADC$adc: DISABLED"
            else
                log "  ADC$adc: ENABLED"
            fi
        else
            log "✗ ADC${adc}_CTRL1 FAILED TO READ"
            json_log "adc${adc}_ctrl1" "read_failed"
        fi
    done
    log ""
else
    log "⚠️  Could not read any AC108 registers - I2C communication problem"
    json_log "register_communication" "failed"
fi

fi

# --- Kernel Logs (AC108/I2S) ---
log "=== KERNEL LOGS (AC108/I2S) ==="
kernel_logs=$(dmesg | grep -E "ac108|seeed|designware|I2S_CTRL|PLL" | tail -30)
echo "$kernel_logs" | tee -a "$LOG_FILE"
json_log "kernel_logs" "$kernel_logs"

# Extract important information from kernel logs
if echo "$kernel_logs" | grep -q "PLL FAILED to lock"; then
    log "✗ Kernel reports: PLL FAILED to lock"
    json_log "kernel_pll_status" "failed_to_lock"

    # Extract PLL configuration from logs
    pll_config=$(echo "$kernel_logs" | grep -o "PLL dividers:.*" | tail -1)
    if [ -n "$pll_config" ]; then
        log "PLL configuration from kernel: $pll_config"
        json_log "kernel_pll_config" "$pll_config"
    fi
fi

if echo "$kernel_logs" | grep -q "BCLK not running"; then
    log "✗ Kernel reports: BCLK not running"
    json_log "kernel_bclk_status" "not_running"
fi
log ""

# --- Audio Capture Test ---
log "=== AUDIO CAPTURE TEST ==="
arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 -d "$TEST_DURATION" "test_capture_$(date +'%Y%m%d_%H%M%S').wav" 2>&1 | tee -a "$LOG_FILE"

# --- Audio File Analysis ---
log "=== AUDIO FILE ANALYSIS ==="
audio_file=$(ls -t test_capture_*.wav 2>/dev/null | head -1)
if [ -f "$audio_file" ]; then
    file_size=$(stat -c%s "$audio_file")
    log "✓ Audio file created: $audio_file ($file_size bytes)"
    json_log "audio_file" "$audio_file"
    json_log "audio_file_size" "$file_size"

    # SOX statistics
    sox_stats=$(sox "$audio_file" -n stat 2>&1)
    echo "$sox_stats" | tee -a "$LOG_FILE"
    json_log "sox_stats" "$sox_stats"

    # Check for silence (without bc - use string comparison)
    max_amplitude=$(echo "$sox_stats" | grep "Maximum amplitude" | awk '{print $3}')
    if [ "$max_amplitude" = "0.000000" ] || [ -z "$max_amplitude" ]; then
        log "✗ Audio file contains ONLY ZEROS (silent capture)"
        json_log "audio_data" "all_zeros"
    else
        log "✓ Audio file contains REAL DATA"
        json_log "audio_data" "real_data"
    fi

    # Hexdump analysis
    if hexdump -C "$audio_file" | grep -vq "00 00 00 00"; then
        log "✓ Hexdump confirms non-zero data present"
    else
        log "✗ Hexdump shows all zeros"
    fi
else
    log "✗ No audio file was created"
    json_log "audio_file" "not_created"
fi
log ""

# --- Diagnosis Summary ---
log "=== DIAGNOSIS SUMMARY ==="
log "1. AC108 Detection:       $(sudo i2cget -y "$I2C_BUS" "$AC108_ADDR" 0x00 >/dev/null 2>&1 && echo "✓ SUCCESS" || echo "✗ FAILED")"

if [ $register_read_success -gt 0 ]; then
    log "2. PLL Status:            $([ "$pll_locked" -eq 1 ] && echo "✓ LOCKED" || echo "✗ NOT LOCKED")"
    log "3. BCLK/LRCK Inputs:    $([ "$bclk_ioen" -eq 1 ] && [ "$lrck_ioen" -eq 1 ] && echo "✓ ENABLED" || echo "✗ DISABLED")"
    log "4. ADC Activation:       $([ "$adc_en" -eq 1 ] && echo "✓ ENABLED" || echo "✗ DISABLED")"
else
    log "2. PLL Status:            ✗ COULD NOT DETERMINE (register read failed)"
    log "3. BCLK/LRCK Inputs:    ✗ COULD NOT DETERMINE (register read failed)"
    log "4. ADC Activation:       ✗ COULD NOT DETERMINE (register read failed)"
fi

log "5. I2S Pinmux:            $(grep -q "i2s0" <<< "$i2s_function" && echo "✓ CORRECT" || echo "✗ INCORRECT")"
log "6. Audio Capture:        $(hexdump -C "$audio_file" 2>/dev/null | grep -vq "00 00 00 00" && echo "✓ REAL DATA" || echo "✗ ALL ZEROS")"

json_log "diagnosis_summary" "$(
    echo \"AC108 Detection: $(sudo i2cget -y "$I2C_BUS" "$AC108_ADDR" 0x00 >/dev/null 2>&1 && echo "success" || echo "failed")\"
    if [ $register_read_success -gt 0 ]; then
        echo \"PLL Status: $([ "$pll_locked" -eq 1 ] && echo "locked" || echo "unlocked")\"
        echo \"BCLK/LRCK Inputs: $([ "$bclk_ioen" -eq 1 ] && [ "$lrck_ioen" -eq 1 ] && echo "enabled" || echo "disabled")\"
        echo \"ADC Enabled: $([ "$adc_en" -eq 1 ] && echo "enabled" || echo "disabled")\"
    else
        echo \"PLL Status: could_not_determine\"
        echo \"BCLK/LRCK Inputs: could_not_determine\"
        echo \"ADC Enabled: could_not_determine\"
    fi
    echo \"I2S Pinmux: $(grep -q "i2s0" <<< "$i2s_function" && echo "correct" || echo "incorrect")\"
    echo \"Audio Capture: $(hexdump -C "$audio_file" 2>/dev/null | grep -vq "00 00 00 00" && echo "real_data" || echo "all_zeros")\"
)"

# --- Error Diagnosis and Solutions ---
log "=== ERROR DIAGNOSIS & SOLUTIONS ==="

# I2C Communication Issues
if [ "$register_read_failed" -eq 32 ]; then
    log "CRITICAL ISSUE: COMPLETE I2C COMMUNICATION FAILURE"
    log "  Possible causes:"
    log "  1. AC108 not properly connected to I2C bus"
    log "  2. I2C bus not enabled in Raspberry Pi configuration"
    log "  3. Incorrect I2C address (expected 0x3b)"
    log "  4. Hardware fault on I2C lines (SDA/SCL)"
    log "  5. I2C bus locked by another device (check 'i2cdetect -y 1' for UU)"
    log "  6. Missing or incorrect Device Tree overlay"
    log ""
    log "  Recommended actions:"
    log "  1. Verify physical I2C connection (pins 3/SDA and 5/SCL)"
    log "  2. Check I2C is enabled: 'sudo raspi-config' -> Interface Options -> I2C"
    log "  3. Verify Device Tree overlay is loaded: 'dtoverlay -a | grep seeed'"
    log "  4. Check for I2C errors: 'dmesg | grep i2c'"
    log "  5. Test with i2ctools: 'sudo i2cdetect -y 1'"
    log "  6. Try I2C bus reset: 'sudo rmmod i2c_dev i2c_brcmstb; sudo modprobe i2c_dev i2c_brcmstb'"
    log "  7. Check power supply (AC108 needs 3.3V)"
    log ""

    json_log "critical_issue" "i2c_communication_failure"
    json_log "recommended_actions" "$(
        echo "1. Verify physical I2C connection (pins 3/SDA and 5/SCL)"
        echo "2. Check I2C is enabled in raspi-config"
        echo "3. Verify Device Tree overlay is loaded"
        echo "4. Check dmesg for I2C errors"
        echo "5. Test with i2ctools"
        echo "6. Try I2C bus reset"
        echo "7. Check power supply"
    )"
fi

# PLL Not Locking
if [ $register_read_success -gt 0 ] && [ "$pll_locked" -ne 1 ]; then
    log "ISSUE: PLL NOT LOCKING"
    log "  Possible causes:"
    log "  1. No BCLK signal from I2S controller (most likely)"
    log "  2. Incorrect PLL configuration"
    log "  3. Wrong clock source selected (MCLK vs BCLK)"
    log "  4. Hardware issue with clock lines"
    log ""
    log "  Recommended actions:"
    log "  1. Verify I2S GPIO pins (18-21) are configured for I2S function"
    log "  2. Check I2S clock is running: 'cat /sys/kernel/debug/clk/clk_summary | grep i2s'"
    log "  3. Ensure BCLK/LRCK inputs are enabled in I2S_CTRL (0x30)"
    log "  4. Verify PLL configuration in SYSCLK_CTRL (0x20)"
    log "  5. Check Device Tree for correct I2S master/slave configuration"
    log "  6. Try forcing BCLK as PLL source (SYSCLK_CTRL bit 1 = 1)"
    log "  7. Add debug to kernel module to verify BCLK frequency"
    log ""

    json_log "pll_issue" "not_locking"
    json_log "pll_recommended_actions" "$(
        echo "1. Verify I2S GPIO pin configuration"
        echo "2. Check I2S clock status"
        echo "3. Enable BCLK/LRCK inputs in I2S_CTRL"
        echo "4. Verify PLL configuration"
        echo "5. Check Device Tree I2S configuration"
        echo "6. Force BCLK as PLL source"
        echo "7. Add kernel debug for BCLK frequency"
    )"
fi

# Silent Audio Capture
if [ -f "$audio_file" ] && [ "$max_amplitude" = "0.000000" ] || [ -z "$max_amplitude" ]; then
    log "ISSUE: SILENT AUDIO CAPTURE"
    log "  Possible causes:"
    log "  1. PLL not locked (see above)"
    log "  2. ADC not enabled"
    log "  3. Microphone not connected or faulty"
    log "  4. Incorrect gain settings"
    log "  5. Wrong audio routing in Device Tree"
    log ""
    log "  Recommended actions:"
    log "  1. Resolve PLL locking issue first"
    log "  2. Verify ADC is enabled (ADC_DIG_EN and ADCx_CTRL1)"
    log "  3. Check microphone connections"
    log "  4. Set proper gain: 'amixer -c 0 sset 'ADC1 PGA gain' 31'"
    log "  5. Test with known good microphone"
    log "  6. Verify Device Tree audio routing"
    log ""

    json_log "audio_issue" "silent_capture"
    json_log "audio_recommended_actions" "$(
        echo "1. Resolve PLL locking issue"
        echo "2. Verify ADC enable registers"
        echo "3. Check microphone connections"
        echo "4. Set proper ADC gain"
        echo "5. Test with known good microphone"
        echo "6. Verify Device Tree audio routing"
    )"
fi

# I2S Pinmux Issues
if ! grep -q "i2s0" <<< "$i2s_function"; then
    log "ISSUE: INCORRECT I2S PINMUX CONFIGURATION"
    log "  The I2S GPIO pins (18-21) are not configured for I2S function"
    log ""
    log "  Recommended actions:"
    log "  1. Verify Device Tree overlay includes I2S pin configuration"
    log "  2. Check pinctrl-0 setting for I2S controller"
    log "  3. Ensure overlay is properly loaded at boot"
    log "  4. Manually set pin function if needed:"
    log "     echo 4 > /sys/class/gpio/export  # Example for GPIO4"
    log "     echo in > /sys/class/gpio/gpio4/direction"
    log "     echo i2s0 > /sys/kernel/debug/pinctrl/.../pinmux"
    log ""

    json_log "pinmux_issue" "incorrect_configuration"
    json_log "pinmux_recommended_actions" "$(
        echo "1. Verify Device Tree overlay I2S pin configuration"
        echo "2. Check pinctrl-0 setting"
        echo "3. Ensure overlay loads at boot"
        echo "4. Consider manual pin configuration"
    )"
fi

# --- Complete JSON file ---
echo "    \"diagnosis_completed\": true,
    \"timestamp\": \"$(date +"%Y-%m%d_%H%M%S")\"
}" >> "$JSON_FILE"

# --- Minimal JSON summary for automation ---
device_detected_bool=false
i2c_status_str="not_detected"
if echo "$i2c_scan" | grep -q "UU"; then
    device_detected_bool=true
    i2c_status_str="driver_owns_bus"
elif echo "$i2c_scan" | grep -q " 3b"; then
    device_detected_bool=true
    i2c_status_str="responsive"
fi

alsa_card_present=false
if echo "$alsa_devices_output" | grep -qi "seeed-4mic-voicecard\|seeed4micvoicec"; then
    alsa_card_present=true
fi

dw_hwparams_err=$(dmesg | grep -m1 "designware-i2s .*hw_params.*-22" | tail -1)
status_val="success"
error_code_val=null
root_cause_val="none"
required_actions_json="[]"

if [ -n "$dw_hwparams_err" ]; then
    status_val="error"
    error_code_val=-22
    root_cause_val="designware-i2s hw_params rejected (likely channel/clock constraint on RP1)"
    required_actions_json='["check arecord --dump-hw-params for RP1 constraints","limit channels or adjust slot/clock settings","review dmesg for designware-i2s hw_params errors"]'
elif [ "$device_detected_bool" = false ]; then
    status_val="error"
    error_code_val=-6
    root_cause_val="AC108 not detected on i2c bus"
    required_actions_json='["verify I2C wiring and overlay","run i2cdetect -y 1 to confirm address 0x3b","reload snd_soc_ac108 module"]'
fi

hw_params_error_bool=false
if [ -n "$dw_hwparams_err" ]; then
    hw_params_error_bool=true
fi

cat > "$MIN_JSON_FILE" <<EOF
{
  "status": "$status_val",
  "error_code": $error_code_val,
  "key_metrics": {
    "device_detected": $device_detected_bool,
    "i2c_status": "$i2c_status_str",
    "alsa_card_present": $alsa_card_present,
    "hw_params_error": $hw_params_error_bool
  },
  "root_cause": "$root_cause_val",
  "required_actions": $required_actions_json
}
EOF

log "Minimal JSON file: $MIN_JSON_FILE"

# --- End of Log ---
log "=== END OF DIAGNOSTIC LOG ==="
log "Log file: $LOG_FILE"
log "JSON file: $JSON_FILE"
log "============================================="
