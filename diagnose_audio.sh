#!/bin/bash
# AC108 Hardware Diagnostics for Seeed ReSpeaker
# Checks driver status, I2C communication, and performs test recording

LOG_DIR="$(cd "$(dirname "$0")" && pwd)/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/diagnose_audio_$(date '+%Y%m%d_%H%M%S').log"
run_ts="$(date '+%Y-%m-%d %H:%M:%S')"

log_msg() {
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S.%3N')]"
    echo -e "$1"
    echo "$timestamp $1" >> "$LOG_FILE"
}

log_cmd() {
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S.%3N')]"
    echo "$timestamp CMD: $1" >> "$LOG_FILE"
    eval "$1" 2>&1 | while IFS= read -r line; do
        echo "$timestamp OUT: $line" >> "$LOG_FILE"
    done
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
log_msg "   Running: arecord -l"
arecord -l 2>&1 | while IFS= read -r line; do
    log_msg "   $line"
done
if arecord -l 2>&1 | grep -qi seeed; then
    log_msg "✅ Seeed device detected by ALSA"
    CARD_NUM=$(arecord -l | grep -i seeed | grep -oP 'card \K[0-9]+')
    log_msg "   Card number: $CARD_NUM"
else
    log_msg "❌ No Seeed device found"
    log_msg "   Available cards:"
    cat /proc/asound/cards | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"

# 3. I2C Communication
log_msg "3️⃣  Checking I2C Communication..."
log_msg "   Running: i2cdetect -y 1"
i2cdetect -y 1 2>&1 | tee -a "$LOG_FILE"
I2C_ADDR=$(i2cdetect -y 1 | grep -o "UU" | head -1)
if [ -n "$I2C_ADDR" ]; then
    log_msg "✅ Codec responding on I2C bus 1 (address shows UU - driver in use)"
    log_msg "   Checking I2C device binding:"
    if [ -d /sys/bus/i2c/devices/1-003b ]; then
        log_msg "   Device path: /sys/bus/i2c/devices/1-003b"
        log_msg "   Driver: $(cat /sys/bus/i2c/devices/1-003b/name 2>/dev/null || echo 'N/A')"
        log_msg "   Modalias: $(cat /sys/bus/i2c/devices/1-003b/modalias 2>/dev/null || echo 'N/A')"
    fi
else
    log_msg "⚠️  No codec detected on I2C bus 1"
    log_msg "   Expected: UU at address 0x3b"
fi
echo "" | tee -a "$LOG_FILE"

# 4. Kernel Logs Check
log_msg "4️⃣  Recent Kernel Logs (errors/warnings)..."
log_msg "   Last 10 AC108/Seeed messages:"
dmesg | grep -iE "(ac108|seeed|asoc-simple|sound)" | tail -10 | while IFS= read -r line; do
    log_msg "   $line"
done
echo "" | tee -a "$LOG_FILE"
log_msg "   Filtering errors/warnings:"
if dmesg | grep -iE "(ac108|seeed)" | grep -iE "(error|fail|warn)" | tail -5 | tee -a "$LOG_FILE"; then
    log_msg "⚠️  Errors found in kernel logs (see above)"
else
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
log_msg "   Running: dtoverlay -l"
dtoverlay -l | tee -a "$LOG_FILE"
if dtoverlay -l | grep -qi seeed; then
    log_msg "✅ Seeed overlay loaded"
else
    log_msg "⚠️  No seeed overlay in dtoverlay list (may be merged into DTB)"
    log_msg "   Checking if sound node exists in device tree:"
    if [ -d /proc/device-tree/sound ]; then
        log_msg "   ✅ /proc/device-tree/sound exists"
        COMPAT=$(tr '\0' ' ' < /proc/device-tree/sound/compatible 2>/dev/null)
        log_msg "   Compatible: $COMPAT"
        NAME=$(tr '\0' ' ' < /proc/device-tree/sound/seeed-voice-card,name 2>/dev/null || tr '\0' ' ' < /proc/device-tree/sound/simple-audio-card,name 2>/dev/null || echo "N/A")
        log_msg "   Card name: $NAME"
    else
        log_msg "   ❌ /proc/device-tree/sound NOT found"
    fi
fi
echo "" | tee -a "$LOG_FILE"

# 10. Codec Register Dump
log_msg "🔟 Checking Codec Register Status..."
if command -v i2cdump &> /dev/null; then
    log_msg "   Dumping AC108 registers (I2C 0x3b):"
    if ! i2cdump -y 1 0x3b 2>&1 | head -20 | tee -a "$LOG_FILE"; then
        log_msg "   ⚠️  i2cdump failed (bus busy or permission)"
    fi
else
    log_msg "   ⚠️  i2cdump not available (install i2c-tools)"
fi
echo "" | tee -a "$LOG_FILE"

# 11. ALSA Controls Check
log_msg "1️⃣1️⃣  ALSA Control Interface..."
if amixer -c 0 contents 2>&1 | grep -qi ac108; then
    log_msg "✅ AC108 controls found"
    log_msg "   Total controls: $(amixer -c 0 controls | wc -l)"
    log_msg "   First controls:" 
    amixer -c 0 scontrols 2>&1 | head -5 | while IFS= read -r line; do log_msg "   $line"; done
else
    log_msg "⚠️  No AC108 controls found"
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
