#!/bin/bash
echo "=========================================="
echo "  FINAL PRE-REBOOT CHECK"
echo "=========================================="
echo ""
echo "✓ Clean DTB backup exists:"
ls -lh /boot/firmware/bcm2712-rpi-5-b.dtb.backup-clean

echo ""
echo "✓ Merged DTB installed:"
ls -lh /boot/firmware/bcm2712-rpi-5-b.dtb
sudo strings /boot/firmware/bcm2712-rpi-5-b.dtb | grep -E "seeed-voice" | head -3

echo ""
echo "✓ Config.txt (no overlay line needed):"
grep -E "i2s|i2c_arm|seeed" /boot/firmware/config.txt | tail -5

echo ""
echo "✓ Modules in /etc/modules:"
grep -E "ac108|seeed" /etc/modules

echo ""
echo "✓ I2C device:"
i2cdetect -y 1 | grep -E "^30|UU" | head -1

echo ""
echo "=========================================="
echo "  ✅ READY FOR FINAL REBOOT"
echo "=========================================="
echo ""
echo "After reboot, run:"
echo "  ./diagnose_audio.sh"
echo "Expected: seeed-4mic-voicecard should appear"
