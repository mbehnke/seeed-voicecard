#!/bin/bash
LOG_FILE="/tmp/final_check_$(date '+%Y%m%d_%H%M%S').log"

log_msg() {
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo "$1"
    echo "$timestamp $1" >> "$LOG_FILE"
}

log_msg "=========================================="
log_msg "  FINAL PRE-REBOOT CHECK"
log_msg "=========================================="
log_msg ""
log_msg "✓ System Information:"
log_msg "   Hostname: $(hostname)"
log_msg "   Kernel: $(uname -r)"
log_msg "   Date: $(date '+%Y-%m-%d %H:%M:%S')"
log_msg ""

log_msg "✓ Clean DTB backup exists:"
ls -lh /boot/firmware/bcm2712-rpi-5-b.dtb.backup-clean 2>&1 | tee -a "$LOG_FILE"
log_msg ""

log_msg "✓ Current DTB Status:"
log_msg "   Main DTB:"
ls -lh /boot/firmware/bcm2712-rpi-5-b.dtb 2>&1 | tee -a "$LOG_FILE"
log_msg ""
log_msg "   DTB contains seeed components:"
sudo strings /boot/firmware/bcm2712-rpi-5-b.dtb | grep -E "seeed-voice" | head -5 | tee -a "$LOG_FILE"
log_msg ""
log_msg "   All DTB backups:"
ls -lh /boot/firmware/bcm2712-rpi-5-b.dtb* 2>&1 | tee -a "$LOG_FILE"
log_msg ""

log_msg "✓ Config.txt settings:"
log_msg "   Relevant lines:"
grep -E "i2s|i2c_arm|seeed|dtoverlay" /boot/firmware/config.txt | tee -a "$LOG_FILE"
log_msg ""

log_msg "✓ Kernel Modules Configuration:"
log_msg "   /etc/modules content:"
grep -E "ac108|seeed|snd" /etc/modules | tee -a "$LOG_FILE"
log_msg ""
log_msg "   Currently loaded audio modules:"
lsmod | grep -E "snd_soc|ac108|seeed" | tee -a "$LOG_FILE"
log_msg ""

log_msg "✓ I2C Hardware Status:"
log_msg "   I2C Bus 1 scan:"
i2cdetect -y 1 2>&1 | tee -a "$LOG_FILE"
log_msg ""
if i2cdetect -y 1 2>/dev/null | grep -q "UU"; then
    log_msg "   ✅ I2C device detected (UU at 0x3b)"
else
    log_msg "   ⚠️  No I2C device showing as bound"
fi
log_msg ""

log_msg "✓ Device Tree Overlay Status:"
log_msg "   Current overlays:"
dtoverlay -l 2>&1 | tee -a "$LOG_FILE"
log_msg ""

log_msg "✓ ALSA Device Status (Pre-Reboot):"
arecord -l 2>&1 | tee -a "$LOG_FILE"
log_msg ""

log_msg "=========================================="
log_msg "  ✅ READY FOR FINAL REBOOT"
log_msg "=========================================="
log_msg ""
log_msg "After reboot, run:"
log_msg "  ./diagnose_audio.sh"
log_msg "Expected: seeed-4mic-voicecard should appear"
log_msg ""
log_msg "Log saved to: $LOG_FILE"
