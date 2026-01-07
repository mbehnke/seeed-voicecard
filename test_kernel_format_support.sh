#!/bin/bash
# Test what DAI formats are actually supported by RPi 5's I2S controller
# This helps identify the exact limitation causing error -22

set -e

LOG_FILE="logs/format_support_test_$(date +%Y%m%d_%H%M%S).log"
mkdir -p logs

{
    echo "=== RPi 5 I2S Format Support Test ==="
    echo "Date: $(date)"
    echo ""
    
    # Check kernel version
    KERNEL_VERSION=$(uname -r)
    echo "Kernel Version: $KERNEL_VERSION"
    echo ""
    
    # Check I2S controller capabilities
    echo "--- I2S Controller Debug Info ---"
    if [ -d /sys/kernel/debug/asoc ]; then
        echo "ASOC Debug Interface Available"
        
        # List all DAIs
        if [ -d /sys/kernel/debug/asoc/dais ]; then
            echo "Available DAIs:"
            grep -r "i2s" /sys/kernel/debug/asoc/dais/ 2>/dev/null | head -20
        fi
        
        # Check codec info
        if [ -d /sys/kernel/debug/asoc/codec ]; then
            echo "Codec Info:"
            ls -la /sys/kernel/debug/asoc/codec/ 2>/dev/null || echo "No codec info"
        fi
    else
        echo "ASOC Debug Interface NOT available (enable CONFIG_SND_SOC_DEBUG_FS)"
    fi
    echo ""
    
    # Test actual format with simple test
    echo "--- Testing Format Support ---"
    echo "Attempting to set various formats and observing kernel logs..."
    echo ""
    
    dmesg -c > /dev/null  # Clear kernel log
    
    # List current dmesg for AC108 related messages
    echo "Recent AC108/ASOC messages:"
    dmesg | grep -i "ac108\|asoc\|i2s\|format" | tail -50 || true
    echo ""
    
    # Check which format caused the error
    echo "--- Error Analysis ---"
    if dmesg | grep -q "snd_soc_dai_set_fmt.*-22"; then
        echo "ERROR FOUND: snd_soc_dai_set_fmt returned -22 (EINVAL)"
        echo "This indicates the I2S controller rejected the requested format"
        echo ""
        echo "Possible causes:"
        echo "1. DSP_A/TDM format not supported by designware-i2s"
        echo "2. LR_SYNC format issue"
        echo "3. Incompatible DAI master configuration"
    fi
    echo ""
    
    # Check Device Tree configuration
    echo "--- Device Tree Format Check ---"
    if [ -f /proc/device-tree/sound/seeed-voice-card,format ]; then
        FORMAT=$(tr -d '\0' < /proc/device-tree/sound/seeed-voice-card,format 2>/dev/null)
        echo "Current DT format: $FORMAT"
    else
        echo "seeed-voice-card,format not found in device tree"
    fi
    echo ""
    
    # Suggest fixes
    echo "--- RECOMMENDATIONS ---"
    echo "1. Ensure DTS uses: seeed-voice-card,format = \"i2s\";"
    echo "2. Remove TDM slot configuration from DTS (not supported by RPi 5 I2S)"
    echo "3. Recompile and merge DTBO:"
    echo "   dtc -I dts -O dtb -o seeed-4mic-voicecard-rpi5.dtbo seeed-4mic-voicecard-rpi5.dts"
    echo "   sudo fdtoverlay -i /boot/firmware/bcm2712-rpi-5-b.dtb -o /boot/firmware/bcm2712-rpi-5-b.dtb.merged seeed-4mic-voicecard-rpi5.dtbo"
    echo "4. Reboot and retest"
    
} | tee "$LOG_FILE"

echo ""
echo "Log saved to: $LOG_FILE"
