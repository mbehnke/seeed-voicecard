#!/bin/bash

# Comprehensive Audio Test for Seeed ReSpeaker 4-Mic Array
# Tests hardware detection, configuration, and actual audio capture
# Logs all results to project directory (not /tmp)

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$PROJECT_DIR/logs/audio_test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TEST_DIR"

TEST_FILE="$TEST_DIR/audio_capture.wav"
STATUS_FILE="$TEST_DIR/test_status.json"
CONSOLE_LOG="$TEST_DIR/console.log"

echo "🎤 Audio Capture Test - Seeed ReSpeaker 4-Mic Array" | tee -a "$CONSOLE_LOG"
echo "=================================================" | tee -a "$CONSOLE_LOG"
echo "Test directory: $TEST_DIR" | tee -a "$CONSOLE_LOG"
echo "" | tee -a "$CONSOLE_LOG"

# Helper functions
log() {
    echo "$(date '+%H:%M:%S') | $1" | tee -a "$CONSOLE_LOG"
}

check_status() {
    if [ $1 -eq 0 ]; then
        echo "✅"
    else
        echo "❌"
    fi
}

# ====== PRE-TEST CHECKS ======
log "📋 PRE-TEST CHECKS"
log "=================="

# 1. Check kernel modules
log "1️⃣  Checking kernel modules..."
if ! lsmod | grep -q snd_soc_ac108; then
    log "   ⚠️  snd_soc_ac108 not loaded! Loading..."
    sudo modprobe snd_soc_ac108 || {
        log "   ❌ FATAL: Cannot load snd_soc_ac108"
        exit 1
    }
fi
log "   ✅ snd_soc_ac108 loaded"

if ! lsmod | grep -q snd_soc_seeed_voicecard; then
    log "   ⚠️  snd_soc_seeed_voicecard not loaded! Loading..."
    sudo modprobe snd_soc_seeed_voicecard || {
        log "   ❌ FATAL: Cannot load snd_soc_seeed_voicecard"
        exit 1
    }
fi
log "   ✅ snd_soc_seeed_voicecard loaded"

# 2. Check ALSA device
log "2️⃣  Checking ALSA device..."
if arecord -l 2>&1 | grep -qi "seeed"; then
    CARD_NUM=$(arecord -l | grep -i seeed | head -1 | grep -o 'card [0-9]*' | awk '{print $2}')
    log "   ✅ Seeed device found (card $CARD_NUM)"
    CARD_NAME=$(arecord -l | grep -i seeed | head -1 | sed 's/.*: //')
    log "   Device name: $CARD_NAME"
else
    log "   ❌ FATAL: No Seeed device found!"
    arecord -l | tee -a "$CONSOLE_LOG"
    exit 1
fi

# 3. Check I2C AC108
log "3️⃣  Checking I2C device (AC108 @ 0x3b)..."
if i2cdetect -y 1 2>&1 | grep -q "UU"; then
    log "   ✅ AC108 codec responding on I2C (device busy/in-use)"
else
    log "   ⚠️  AC108 not detected - may be offline"
fi

# 4. Check mixer controls
log "4️⃣  Checking ALSA mixer controls..."
CONTROL_COUNT=$(amixer -c 0 scontrols 2>/dev/null | wc -l)
if [ "$CONTROL_COUNT" -gt 0 ]; then
    log "   ✅ Found $CONTROL_COUNT mixer controls"
    log "   ADC Gain controls:"
    for i in 1 2 3 4; do
        GAIN=$(amixer -c 0 sget "ADC${i} PGA gain" 2>/dev/null | grep -o "Mono: [0-9]*" | awk '{print $2}')
        if [ -n "$GAIN" ]; then
            log "     ADC${i}: $GAIN/31"
        fi
    done
else
    log "   ⚠️  No mixer controls found (AC108 may not be initialized)"
fi

echo "" | tee -a "$CONSOLE_LOG"

# ====== CONFIGURE GAINS ======
log "🔊 CONFIGURING MIXER GAINS"
log "=========================="
log "Setting ADC gains to 80% (25/31) for optimal capture..."
for i in 1 2 3 4; do
    if amixer -c 0 sset "ADC${i} PGA gain" 25 > /dev/null 2>&1; then
        log "   ✅ ADC${i} gain set to 25/31"
    else
        log "   ⚠️  Could not set ADC${i} gain (may not exist)"
    fi
done

echo "" | tee -a "$CONSOLE_LOG"

# ====== PERFORM AUDIO CAPTURE ======
log "🎙️  AUDIO CAPTURE TEST"
log "===================="
log "Recording 5 seconds from all 4 channels..."
log "Please make noise or speak into the microphone NOW!"
echo "" | tee -a "$CONSOLE_LOG"

# Capture with detailed error reporting
CAPTURE_START=$(date +%s)
CAPTURE_LOG="$TEST_DIR/capture.log"

if timeout 6 arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 -d 5 "$TEST_FILE" > "$CAPTURE_LOG" 2>&1; then
    CAPTURE_STATUS="success"
    log "✅ Recording completed successfully"
else
    CAPTURE_STATUS="timeout_or_error"
    log "⚠️  Recording interrupted (timeout or error)"
    cat "$CAPTURE_LOG" | tee -a "$CONSOLE_LOG"
fi

CAPTURE_END=$(date +%s)
CAPTURE_DURATION=$((CAPTURE_END - CAPTURE_START))
log "   Duration: $CAPTURE_DURATION seconds"

echo "" | tee -a "$CONSOLE_LOG"

# ====== ANALYZE RECORDING ======
log "📊 ANALYZING RECORDING"
log "===================="

if [ ! -f "$TEST_FILE" ]; then
    log "❌ FATAL: Test file not created"
    echo "{\"status\": \"error\", \"error\": \"capture_failed\", \"file_created\": false}" > "$STATUS_FILE"
    exit 1
fi

FILE_SIZE=$(stat -c%s "$TEST_FILE" 2>/dev/null || stat -f%z "$TEST_FILE")
log "File size: $(numfmt --to=iec-i --suffix=B "$FILE_SIZE" 2>/dev/null || echo "$FILE_SIZE bytes")"

# Expected size for 5 seconds: 16000 Hz * 5 sec * 4 channels * 4 bytes = 1,280,000 bytes
EXPECTED_SIZE=$((16000 * 5 * 4 * 4))
if [ "$FILE_SIZE" -ge "$((EXPECTED_SIZE - 10000))" ]; then
    log "✅ File size reasonable (expected ~$((EXPECTED_SIZE / 1000))KB)"
    SIZE_OK="true"
else
    log "⚠️  File size smaller than expected"
    log "   Expected: ~$((EXPECTED_SIZE / 1000))KB, Got: $((FILE_SIZE / 1000))KB"
    SIZE_OK="false"
fi

# Analyze audio content with Python
log "Analyzing audio content..."
python3 << 'PYEOF' > "$TEST_DIR/audio_analysis.txt" 2>&1
import wave
import struct
import sys
import json
import os

test_file = os.environ['TEST_FILE']
output = {
    'channels': 0,
    'sample_rate': 0,
    'sample_width': 0,
    'duration': 0,
    'frames': 0,
    'channel_stats': [],
    'overall_max': 0,
    'overall_min': 0,
    'audio_detected': False
}

try:
    with wave.open(test_file, 'rb') as w:
        output['channels'] = w.getnchannels()
        output['sample_rate'] = w.getframerate()
        output['sample_width'] = w.getsampwidth()
        output['frames'] = w.getnframes()
        output['duration'] = output['frames'] / output['sample_rate']
        
        # Read all frames
        all_frames = w.readframes(output['frames'])
        
        if output['sample_width'] == 4:
            # Unpack 32-bit samples
            samples = struct.unpack('<' + 'i' * (len(all_frames) // 4), all_frames)
            
            # Analyze by channel
            frame_count = len(samples) // output['channels']
            for ch in range(output['channels']):
                ch_samples = [samples[i * output['channels'] + ch] for i in range(frame_count)]
                ch_max = max(ch_samples)
                ch_min = min(ch_samples)
                ch_range = ch_max - ch_min
                
                output['channel_stats'].append({
                    'channel': ch + 1,
                    'max': ch_max,
                    'min': ch_min,
                    'range': ch_range,
                    'rms': int((sum(s**2 for s in ch_samples) / len(ch_samples))**0.5)
                })
            
            # Overall statistics
            overall_max = max(samples)
            overall_min = min(samples)
            output['overall_max'] = overall_max
            output['overall_min'] = overall_min
            
            # Determine if audio detected
            max_range = max(stat['range'] for stat in output['channel_stats'])
            if max_range > 500:
                output['audio_detected'] = True
                
        # Print human-readable output
        print(f"Wave File Analysis:")
        print(f"  Channels: {output['channels']}")
        print(f"  Sample Rate: {output['sample_rate']} Hz")
        print(f"  Sample Width: {output['sample_width']} bytes")
        print(f"  Total Frames: {output['frames']}")
        print(f"  Duration: {output['duration']:.2f} seconds")
        print("")
        print("Per-Channel Statistics:")
        for stat in output['channel_stats']:
            print(f"  Ch{stat['channel']}: Range={stat['range']:10d} RMS={stat['rms']:8d} (Max={stat['max']:11d} Min={stat['min']:11d})")
        print("")
        print(f"Overall: Max={output['overall_max']:11d} Min={output['overall_min']:11d}")
        print("")
        
        if output['audio_detected']:
            max_ch = max(output['channel_stats'], key=lambda x: x['range'])
            print(f"✅ AUDIO DETECTED on Ch{max_ch['channel']} (range: {max_ch['range']})")
        else:
            print("❌ NO AUDIO DETECTED (all channels silent)")

except Exception as e:
    print(f"Error: {e}")
    output['error'] = str(e)

# Save JSON for scripting
with open(os.environ['STATUS_FILE'], 'w') as f:
    json.dump(output, f, indent=2)
PYEOF

export TEST_FILE="$TEST_FILE"
export STATUS_FILE="$STATUS_FILE"

# Display analysis results
cat "$TEST_DIR/audio_analysis.txt" | tee -a "$CONSOLE_LOG"

echo "" | tee -a "$CONSOLE_LOG"

# ====== DETAILED DIAGNOSTICS ======
log "🔍 DETAILED DIAGNOSTICS"
log "======================"

log "Kernel logs (seeded/ac108):"
if dmesg | grep -iE "seeded|ac108" | tail -5 | tee -a "$CONSOLE_LOG"; then
    :
else
    log "   (no recent kernel messages)"
fi

echo "" | tee -a "$CONSOLE_LOG"

log "Mixer contents:"
amixer -c 0 contents 2>/dev/null | head -20 | tee -a "$CONSOLE_LOG"

echo "" | tee -a "$CONSOLE_LOG"

log "ALSA device details:"
arecord -D hw:0,0 --dump-hw-params -f S32_LE -r 16000 -c 4 /dev/null 2>&1 | grep -v "^$" | tee -a "$CONSOLE_LOG"

echo "" | tee -a "$CONSOLE_LOG"

# ====== FINAL SUMMARY ======
log "📝 TEST SUMMARY"
log "==============="

# Read analysis results
if [ -f "$STATUS_FILE" ]; then
    python3 << 'SUMMARYEOF'
import json
import os

status_file = os.environ['STATUS_FILE']
with open(status_file, 'r') as f:
    data = json.load(f)

audio_detected = data.get('audio_detected', False)
channels = data.get('channels', 0)
duration = data.get('duration', 0)
sample_rate = data.get('sample_rate', 0)

print(f"Results:")
print(f"  Channels captured: {channels}")
print(f"  Duration: {duration:.2f} seconds")
print(f"  Sample Rate: {sample_rate} Hz")
print(f"  Audio detected: {'✅ YES' if audio_detected else '❌ NO'}")

if not audio_detected:
    print("")
    print("Troubleshooting steps:")
    print("  1. Verify microphone is plugged in")
    print("  2. Check mixer gains: amixer -c 0 scontrols")
    print("  3. Reload drivers: sudo modprobe -r snd_soc_seeed_voicecard snd_soc_ac108")
    print("  4. Check dmesg: dmesg | grep -i ac108")
SUMMARYEOF
fi

echo "" | tee -a "$CONSOLE_LOG"
log "================================================="
log "✅ Test complete! Results saved to:"
log "   $TEST_DIR/"
log ""
log "Key files:"
log "   • audio_capture.wav  - Raw audio data"
log "   • console.log        - Full test output"
log "   • audio_analysis.txt - Detailed analysis"
log "   • test_status.json   - Machine-readable results"
log ""
log "To play recording: aplay -D plughw:0,0 '$TEST_FILE'"
log "To analyze again: sox '$TEST_FILE' -n stat"
