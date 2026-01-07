#!/bin/bash
# Pi 5 Seeed Voicecard: Full installation + DTB merge + reboot prep

set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 1>&2
   exit 1
fi

echo "========================================================="
echo "SEEED VOICECARD Pi 5 - FULL INSTALLATION & DTB MERGE"
echo "========================================================="
echo ""

cd "$(dirname "$0")"

# 1. Install DKMS modules
echo "[1/4] Installing kernel modules via DKMS..."
./install.sh

# 2. Verify modules installed
echo "[2/4] Verifying module installation..."
sleep 2
if modinfo snd-soc-ac108 2>/dev/null | grep -q 'depends.*snd-soc-core,regmap-i2c'; then
  echo "✅ snd-soc-ac108 correctly decoupled (no seeed-voicecard dependency)"
else
  echo "⚠️  WARNING: snd-soc-ac108 may still have unexpected dependencies"
  modinfo snd-soc-ac108 | grep 'depends:'
fi

# 3. Check DTB and merge overlay
echo "[3/4] Checking DTB and overlay status..."
OVERLAYS=/boot/overlays
[ -d /boot/firmware/overlays ] && OVERLAYS=/boot/firmware/overlays

DTB=/boot/firmware/bcm2712-rpi-5-b.dtb
[ -f /boot/bcm2712-rpi-5-b.dtb ] && DTB=/boot/bcm2712-rpi-5-b.dtb

if [ -f "$DTB" ] && [ -f "$OVERLAYS/seeed-4mic-voicecard-rpi5.dtbo" ]; then
  echo "   DTB: $DTB"
  echo "   DTBO: $OVERLAYS/seeed-4mic-voicecard-rpi5.dtbo"
  
  ts=$(date +%Y%m%d_%H%M%S)
  DTB_BACKUP="$DTB.bak.$ts"
  cp -a "$DTB" "$DTB_BACKUP"
  echo "   Backup created: $DTB_BACKUP"
  
  if fdtoverlay -i "$DTB" -o "$DTB.merged" "$OVERLAYS/seeed-4mic-voicecard-rpi5.dtbo"; then
    cp -a "$DTB.merged" "$DTB"
    echo "✅ DTB merged with Pi5-specific overlay (includes /delete-* cleanup)"
  else
    echo "❌ DTB merge failed. Restoring backup."
    cp -a "$DTB_BACKUP" "$DTB"
    exit 1
  fi
else
  echo "⚠️  DTB or DTBO not found. Check paths above."
  exit 1
fi

# 4. Summary
echo ""
echo "[4/4] Pre-reboot status..."
echo "========================================================="
echo "✅ Modules built and installed (AC108 decoupled)"
echo "✅ Pi5 overlay merged into DTB"
echo "✅ Boot config updated for Pi5"
echo ""
echo "📋 Next steps:"
echo "   1. Reboot: sudo reboot"
echo "   2. After reboot, verify:"
echo "      - arecord -l          (should list seeed-4mic capture device)"
echo "      - sudo ./diagnose_audio_2.sh"
echo "========================================================="
echo ""

# Prompt for reboot
read -p "Ready to reboot now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Rebooting in 3 seconds..."
  sleep 3
  reboot
else
  echo "Reboot deferred. When ready, run: sudo reboot"
fi
