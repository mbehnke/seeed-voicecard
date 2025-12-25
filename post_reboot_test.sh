#!/bin/bash

echo "========================================"
echo "  Post-Reboot Test: AC108 Seeed Card"
echo "========================================"
echo ""

# 1. Check kernel error
echo "1️⃣  Checking kernel logs for DAI format errors..."
ERRORS=$(dmesg | grep -i "error at snd_soc_dai_set_fmt")
if [ -z "$ERRORS" ]; then
    echo "✅ NO dai_set_fmt errors found!"
else
    echo "❌ ERRORS found:"
    echo "$ERRORS"
fi
echo ""

# 2. Check probe success
echo "2️⃣  Checking seeed-voicecard probe status..."
PROBE_ERR=$(dmesg | grep "seeed-voicecard sound: probe with driver seeed-voicecard failed")
if [ -z "$PROBE_ERR" ]; then
    echo "✅ Probe successful (no failure messages)"
else
    echo "❌ Probe FAILED:"
    echo "$PROBE_ERR"
fi
echo ""

# 3. Check ALSA card
echo "3️⃣  Checking ALSA card registration..."
arecord -l | grep -i "seeed"
if [ $? -eq 0 ]; then
    echo "✅ Seeed card detected!"
else
    echo "❌ Seeed card NOT detected"
fi
echo ""

# 4. Check mixer controls
echo "4️⃣  Checking mixer controls..."
CONTROLS=$(amixer -c 0 scontrols 2>/dev/null | wc -l)
echo "Found $CONTROLS mixer controls"
if [ "$CONTROLS" -gt 0 ]; then
    echo "✅ Mixer controls available"
else
    echo "❌ NO mixer controls"
fi
echo ""

# 5. Quick recording test
echo "5️⃣  Testing recording (3 seconds)..."
CARD=$(arecord -l | grep -i "seeed" | head -1 | sed 's/card \([0-9]\).*/\1/')
if [ -n "$CARD" ]; then
    echo "Recording from card $CARD..."
    timeout 3 arecord -D hw:$CARD,0 -f S16_LE -r 16000 -c 4 /tmp/test_$(date +%s).wav 2>&1 | head -5
    if [ ${PIPESTATUS[0]} -eq 0 ] || [ ${PIPESTATUS[0]} -eq 124 ]; then
        echo "✅ Recording test passed"
    else
        echo "❌ Recording test FAILED"
    fi
else
    echo "⚠️  Skipped (no card detected)"
fi
echo ""

# 6. Check DTB format
echo "6️⃣  Checking DTB format configuration..."
FORMAT=$(tr -d '\0' < /proc/device-tree/sound/seeed-voice-card,format 2>/dev/null)
echo "DTB Format: '$FORMAT'"
if [ "$FORMAT" = "i2s" ]; then
    echo "✅ Format is I2S (correct for RPi 5)"
else
    echo "⚠️  Format is not I2S: '$FORMAT'"
fi
echo ""

# Summary
echo "========================================"
echo "  Test Summary"
echo "========================================"
dmesg | tail -20 | grep -E "ac108|seeed|i2s" | tail -10

