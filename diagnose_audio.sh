#!/bin/bash
# AC108 Hardware Diagnostics for Seeed ReSpeaker
# Checks driver status, I2C communication, and performs test recording

LOG_FILE="/tmp/diagnose_audio.log"
run_ts="$(date '+%Y-%m-%d %H:%M:%S')"

log_msg() {
    echo -e "$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

echo "==========================================" | tee -a "$LOG_FILE"
echo "  AC108 ReSpeaker Hardware Diagnostics" | tee -a "$LOG_FILE"
echo "==========================================" | tee -a "$LOG_FILE"
echo "Run start: $run_ts" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 1. Kernel Module Check
log_msg "1️⃣  Checking Kernel Modules..."
if lsmod | grep -q snd_soc_ac108; then
    log_msg "✅ snd_soc_ac108 loaded"
else
    log_msg "❌ snd_soc_ac108 NOT loaded"
    log_msg "   Run: sudo modprobe snd_soc_ac108"
fi

if lsmod | grep -q snd_soc_seeed_voicecard; then
    log_msg "✅ snd_soc_seeed_voicecard loaded"
else
    log_msg "❌ snd_soc_seeed_voicecard NOT loaded"
fi
echo "" | tee -a "$LOG_FILE"

# 2. Hardware Detection
log_msg "2️⃣  Checking Hardware Detection..."
if arecord -l 2>&1 | tee -a "$LOG_FILE" | grep -qi seeed; then
    log_msg "✅ Seeed device detected by ALSA"
else
    log_msg "❌ No Seeed device found"
fi
echo "" | tee -a "$LOG_FILE"

# 3. I2C Communication
log_msg "3️⃣  Checking I2C Communication..."
I2C_ADDR=$(i2cdetect -y 1 | grep -o "UU" | head -1)
if [ -n "$I2C_ADDR" ]; then
    log_msg "✅ Codec responding on I2C bus 1 (address shows UU - driver in use)"
else
    log_msg "⚠️  No codec detected on I2C bus 1"
fi
echo "" | tee -a "$LOG_FILE"

# 4. Kernel Logs Check
log_msg "4️⃣  Recent Kernel Logs (errors/warnings)..."
if ! dmesg | grep -iE "(ac108|seeed)" | grep -iE "(error|fail|warn)" | tail -5 | tee -a "$LOG_FILE"; then
    log_msg "✅ No errors in kernel logs"
fi
echo "" | tee -a "$LOG_FILE"

# 5. Mixer Settings
log_msg "5️⃣  Current Mixer Settings..."
for i in 1 2 3 4; do
    GAIN=$(amixer -c 0 sget "ADC${i} PGA gain" 2>/dev/null | grep -o "Mono: [0-9]*" | awk '{print $2}')
    if [ -n "$GAIN" ]; then
        PERCENT=$((GAIN * 100 / 31))
        log_msg "   ADC${i} PGA gain: ${GAIN}/31 (${PERCENT}%)"
    fi
done
echo "" | tee -a "$LOG_FILE"

# 6. Set Optimal Gains
log_msg "6️⃣  Setting Optimal Mixer Gains (90%)..."
for i in 1 2 3 4; do
    amixer -c 0 sset "ADC${i} PGA gain" 28 > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log_msg "✅ ADC${i} set to 28/31 (90%)"
    else
        log_msg "❌ Failed to set ADC${i}"
    fi
done
echo "" | tee -a "$LOG_FILE"

# 7. Test Recording
log_msg "7️⃣  Performing Test Recording (3 seconds)..."
log_msg "   🎤 Please speak or make noise now..."
arecord -D plughw:0,0 -f S32_LE -r 16000 -c 4 -d 3 /tmp/test_ac108.wav 2>&1 | grep -v "^$" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 8. Analyze Recording
log_msg "8️⃣  Analyzing Recording..."
if [ -f /tmp/test_ac108.wav ]; then
    FILE_SIZE=$(stat -f%z /tmp/test_ac108.wav 2>/dev/null || stat -c%s /tmp/test_ac108.wav)
    log_msg "   File size: ${FILE_SIZE} bytes"
    
    # Python analysis
    python3 << 'EOF' | tee -a "$LOG_FILE"
import wave
import struct
import sys

try:
    with wave.open('/tmp/test_ac108.wav', 'rb') as w:
        frames = w.readframes(5000)
        if w.getsampwidth() == 4:
            samples = struct.unpack('<' + 'i' * (len(frames)//4), frames)
            min_val = min(samples)
            max_val = max(samples)
            signal_range = max_val - min_val
            
            print(f'   Min value: {min_val}')
            print(f'   Max value: {max_val}')
            print(f'   Signal range: {signal_range}')
            
            if signal_range < 100:
                print('   ❌ SILENT - No audio detected')
                print('   ')
                print('   Possible causes:')
                print('   • Microphone not connected')
                print('   • Wrong input routing (check DTS overlay)')
                print('   • Codec not initialized (I2C issue)')
                print('   • Hardware fault')
            elif signal_range < 100000:
                print('   ⚠️  QUIET - Very low signal')
                print('   • Check microphone gain settings')
                print('   • Verify input is not muted')
            else:
                print('   ✅ AUDIO DETECTED - Hardware working!')
except Exception as e:
    print(f'   ❌ Error analyzing file: {e}')
EOF
else
    log_msg "   ❌ Test file not created"
fi
echo "" | tee -a "$LOG_FILE"

# 9. Device Tree Check
log_msg "9️⃣  Checking Device Tree Overlay..."
if dtoverlay -l | tee -a "$LOG_FILE" | grep -qi seeed; then
    log_msg "✅ Seeed overlay loaded"
else
    log_msg "⚠️  No seeed overlay in dtoverlay list"
    log_msg "   Check /boot/firmware/config.txt for dtoverlay=seeed-*mic-voicecard"
fi
echo "" | tee -a "$LOG_FILE"

echo "==========================================" | tee -a "$LOG_FILE"
echo "  Diagnostic Complete" | tee -a "$LOG_FILE"
echo "==========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "💡 Quick Fixes:" | tee -a "$LOG_FILE"
echo "   • Reload modules: sudo modprobe -r snd_soc_ac108 && sudo modprobe snd_soc_ac108" | tee -a "$LOG_FILE"
echo "   • Reboot: sudo reboot" | tee -a "$LOG_FILE"
echo "   • Check config: cat /boot/firmware/config.txt | grep seeed" | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
