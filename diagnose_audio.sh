#!/bin/bash
# AC108 Hardware Diagnostics for Seeed ReSpeaker
# Checks driver status, I2C communication, and performs test recording

echo "=========================================="
echo "  AC108 ReSpeaker Hardware Diagnostics"
echo "=========================================="
echo ""

# 1. Kernel Module Check
echo "1️⃣  Checking Kernel Modules..."
if lsmod | grep -q snd_soc_ac108; then
    echo "✅ snd_soc_ac108 loaded"
else
    echo "❌ snd_soc_ac108 NOT loaded"
    echo "   Run: sudo modprobe snd_soc_ac108"
fi

if lsmod | grep -q snd_soc_seeed_voicecard; then
    echo "✅ snd_soc_seeed_voicecard loaded"
else
    echo "❌ snd_soc_seeed_voicecard NOT loaded"
fi
echo ""

# 2. Hardware Detection
echo "2️⃣  Checking Hardware Detection..."
arecord -l | grep -i seeed
if [ $? -eq 0 ]; then
    echo "✅ Seeed device detected by ALSA"
else
    echo "❌ No Seeed device found"
fi
echo ""

# 3. I2C Communication
echo "3️⃣  Checking I2C Communication..."
I2C_ADDR=$(i2cdetect -y 1 | grep -o "UU" | head -1)
if [ -n "$I2C_ADDR" ]; then
    echo "✅ Codec responding on I2C bus 1 (address shows UU - driver in use)"
else
    echo "⚠️  No codec detected on I2C bus 1"
fi
echo ""

# 4. Kernel Logs Check
echo "4️⃣  Recent Kernel Logs (errors/warnings)..."
dmesg | grep -iE "(ac108|seeed)" | grep -iE "(error|fail|warn)" | tail -5
if [ $? -ne 0 ]; then
    echo "✅ No errors in kernel logs"
fi
echo ""

# 5. Mixer Settings
echo "5️⃣  Current Mixer Settings..."
for i in 1 2 3 4; do
    GAIN=$(amixer -c 0 sget "ADC${i} PGA gain" 2>/dev/null | grep -o "Mono: [0-9]*" | awk '{print $2}')
    if [ -n "$GAIN" ]; then
        PERCENT=$((GAIN * 100 / 31))
        echo "   ADC${i} PGA gain: ${GAIN}/31 (${PERCENT}%)"
    fi
done
echo ""

# 6. Set Optimal Gains
echo "6️⃣  Setting Optimal Mixer Gains (90%)..."
for i in 1 2 3 4; do
    amixer -c 0 sset "ADC${i} PGA gain" 28 > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✅ ADC${i} set to 28/31 (90%)"
    else
        echo "❌ Failed to set ADC${i}"
    fi
done
echo ""

# 7. Test Recording
echo "7️⃣  Performing Test Recording (3 seconds)..."
echo "   🎤 Please speak or make noise now..."
arecord -D plughw:0,0 -f S32_LE -r 16000 -c 4 -d 3 /tmp/test_ac108.wav 2>&1 | grep -v "^$"
echo ""

# 8. Analyze Recording
echo "8️⃣  Analyzing Recording..."
if [ -f /tmp/test_ac108.wav ]; then
    FILE_SIZE=$(stat -f%z /tmp/test_ac108.wav 2>/dev/null || stat -c%s /tmp/test_ac108.wav)
    echo "   File size: ${FILE_SIZE} bytes"
    
    # Python analysis
    python3 << 'EOF'
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
    echo "   ❌ Test file not created"
fi
echo ""

# 9. Device Tree Check
echo "9️⃣  Checking Device Tree Overlay..."
dtoverlay -l | grep -i seeed
if [ $? -eq 0 ]; then
    echo "✅ Seeed overlay loaded"
else
    echo "⚠️  No seeed overlay in dtoverlay list"
    echo "   Check /boot/firmware/config.txt for dtoverlay=seeed-*mic-voicecard"
fi
echo ""

echo "=========================================="
echo "  Diagnostic Complete"
echo "=========================================="
echo ""
echo "💡 Quick Fixes:"
echo "   • Reload modules: sudo modprobe -r snd_soc_ac108 && sudo modprobe snd_soc_ac108"
echo "   • Reboot: sudo reboot"
echo "   • Check config: cat /boot/firmware/config.txt | grep seeed"
echo ""
