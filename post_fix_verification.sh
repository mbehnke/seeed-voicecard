#!/bin/bash

# ===========================
# Post-Fix Reboot Test Script
# ===========================

LOG_DIR="/home/adm_behnke/seeed-voicecard/logs"
TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
LOG_FILE="$LOG_DIR/post_fix_test_${TIMESTAMP}.log"

{
    echo "=== POST-FIX VERIFICATION TEST ===" 
    echo "Timestamp: $TIMESTAMP"
    echo ""
    
    echo "1. Kernel Version:"
    uname -a
    echo ""
    
    echo "2. Sound Devices Detected:"
    cat /proc/asound/cards
    echo ""
    
    echo "3. AC108 I2C Status:"
    sudo i2cdetect -y 1 2>/dev/null | grep -A2 "30:"
    echo ""
    
    echo "4. Loaded Modules:"
    lsmod | grep -E "ac108|seeed|designware"
    echo ""
    
    echo "5. Kernel Messages (AC108):"
    dmesg | grep -E "ac108|seeed_voice_card|startup" | tail -30
    echo ""
    
    echo "6. ALSA Capture Devices:"
    arecord -l 2>&1 || echo "arecord error (expected if no device)"
    echo ""
    
    echo "7. Test Recording (3 seconds):"
    timeout 3 arecord -D hw:0,0 -f S16_LE -r 16000 -c 4 /tmp/audio_test_${TIMESTAMP}.wav 2>&1 || echo "Recording attempt completed"
    echo ""
    
    if [ -f /tmp/audio_test_${TIMESTAMP}.wav ]; then
        echo "8. Audio File Analysis:"
        sox /tmp/audio_test_${TIMESTAMP}.wav -n stat 2>&1
        echo ""
        
        echo "9. Hexdump Check (first 200 bytes):"
        hexdump -C /tmp/audio_test_${TIMESTAMP}.wav | head -10
    else
        echo "8. No audio file generated"
    fi
    
} | tee "$LOG_FILE"

echo ""
echo "Detailed log saved to: $LOG_FILE"
