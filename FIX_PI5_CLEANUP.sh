#!/bin/bash
# Pi 5 Seeed Voicecard: CLEAN UP and FIX machine driver conflict

set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 1>&2
   exit 1
fi

echo "========================================================="
echo "SEEED VOICECARD Pi 5 - CLEANUP & FIX"
echo "========================================================="
echo ""

# 1. Determine if Pi 5
IS_PI5=0
if grep -q "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null; then
  IS_PI5=1
elif grep -q "bcm2712" /proc/cpuinfo 2>/dev/null; then
  IS_PI5=1
fi

if [ $IS_PI5 -ne 1 ]; then
  echo "❌ This script is for Pi 5 only. Exiting."
  echo "   Model: $(cat /proc/device-tree/model 2>/dev/null || echo 'unknown')"
  exit 1
fi

echo "✅ Detected Raspberry Pi 5"
echo ""

# 2. Remove seeed-voicecard from /etc/modules
echo "[1/4] Removing snd-soc-seeed-voicecard from /etc/modules..."
if grep -q "^snd-soc-seeed-voicecard$" /etc/modules; then
  sed -i '/^snd-soc-seeed-voicecard$/d' /etc/modules
  echo "  ✅ Removed from /etc/modules"
else
  echo "  ℹ️  Already absent from /etc/modules"
fi

# 3. Unload seeed-voicecard module if loaded
echo "[2/4] Unloading snd-soc-seeed-voicecard module..."
if lsmod | grep -q "^snd_soc_seeed_voicecard"; then
  modprobe -r snd_soc_seeed_voicecard 2>/dev/null || true
  sleep 1
  echo "  ✅ Module unloaded"
else
  echo "  ℹ️  Module not currently loaded"
fi

# 4. Verify only codec + simple-card load
echo "[3/4] Reloading audio modules..."
modprobe -r snd_soc_ac108 2>/dev/null || true
modprobe -r snd_soc_simple_card 2>/dev/null || true
sleep 1

# Load only what we need: codecs + simple-card from DT
modprobe snd_soc_ac108
modprobe snd_soc_simple_card
sleep 2

echo "  ✅ Modules reloaded"

# 5. Check result
echo "[4/4] Verifying ALSA device..."
echo ""
arecord -l
echo ""

if arecord -l 2>/dev/null | grep -q "seeed\|ac10x\|4-mic"; then
  echo "✅ SUCCESS: seeed-4mic capture device detected!"
else
  echo "⚠️  No seeed device yet. Checking kernel logs..."
  dmesg | grep -i "asoc-simple-card\|sysfs.*duplicate" | tail -n 5 || true
fi

echo ""
echo "========================================================="
echo "Cleanup complete. Status:"
lsmod | grep snd_soc | grep -E 'ac108|simple'
echo "========================================================="
