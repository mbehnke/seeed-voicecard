# Quick Fix Guide - Next Steps

## ✅ Completed Fixes

1. **diagnose_audio_2.sh** - Fixed step_timer function declaration order
2. **seeed-4mic-voicecard-rpi5-overlay.dts** - Fixed malformed DTS structure
3. **seeed-4mic-voicecard-rpi5-overlay.dts** - Shortened device name to avoid truncation

## 🔧 Required Actions

### Step 1: Rebuild and Merge Device Tree Overlay (5 min)

```bash
cd /home/adm_behnke/seeed-voicecard

# Compile the DTS to DTBO
dtc -I dts -O dtb -o seeed-4mic-voicecard-rpi5.dtbo seeed-4mic-voicecard-rpi5-overlay.dts

# Verify compilation
ls -lh seeed-4mic-voicecard-rpi5.dtbo

# Backup original DTB
sudo cp /boot/firmware/bcm2712-rpi-5-b.dtb /boot/firmware/bcm2712-rpi-5-b.dtb.backup

# Merge overlay into DTB (using fdtoverlay)
sudo fdtoverlay -i /boot/firmware/bcm2712-rpi-5-b.dtb \
  -o /boot/firmware/bcm2712-rpi-5-b.dtb.merged \
  seeed-4mic-voicecard-rpi5.dtbo

# Replace original with merged version
sudo mv /boot/firmware/bcm2712-rpi-5-b.dtb.merged /boot/firmware/bcm2712-rpi-5-b.dtb

# Verify merge
dtc -I dtb -O dts /boot/firmware/bcm2712-rpi-5-b.dtb | grep -A10 "seeed-voice-card"
```

### Step 2: Recompile Kernel Modules

```bash
cd /home/adm_behnke/seeed-voicecard

# Clean and rebuild with debug enabled
make clean && make DEBUG=1

# Install modules
sudo make install
sudo depmod -a

# Verify installation
ls -lh /lib/modules/$(uname -r)/kernel/sound/soc/{codecs/snd-soc-ac108.ko,bcm/snd-soc-seeed-voicecard.ko}
```

### Step 3: Reboot System

```bash
sudo reboot
```

### Step 4: Verify and Debug (After Reboot)

```bash
# Check modules loaded
lsmod | grep -E "snd_soc_ac108|seeed"

# Enable real-time kernel debugging
echo 'file ac108.c +p' | sudo tee /sys/kernel/debug/dynamic_debug/control
echo 'file seeed-voicecard.c +p' | sudo tee /sys/kernel/debug/dynamic_debug/control

# Watch kernel logs while testing
sudo dmesg -w | grep -Ei "seeed|ac108|TDM|slot|sysclk" &
DMESG_PID=$!

# Test audio in another terminal
timeout 5 arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 /tmp/test.wav

# Kill dmesg monitor
kill $DMESG_PID 2>/dev/null

# Review logs
dmesg | grep -Ei "seeed|ac108|TDM" | tail -50
```

### Step 5: Run Full Diagnostics

```bash
cd /home/adm_behnke/seeed-voicecard

# Run improved diagnostics (step_timer now works!)
sudo ./diagnose_audio_2.sh

# Check results
cat logs/ac108_debug_*/status.json | jq .

# If still failing, check specific logs
cat logs/ac108_debug_*/3_tdm_logs.log
cat logs/ac108_debug_*/4_hwparams.log
```

## 📋 Troubleshooting

### Issue: DTB Merge Fails
```bash
# If fdtoverlay fails, manually patch DTB using device tree manipulation
# Or restore backup and try alternative overlay method
sudo cp /boot/firmware/bcm2712-rpi-5-b.dtb.backup /boot/firmware/bcm2712-rpi-5-b.dtb
```

### Issue: Modules Still Don't Load
```bash
# Check if device tree is correct
dtc -I dtb /boot/firmware/bcm2712-rpi-5-b.dtb -O dts | grep -B5 -A15 "ac108"

# Check I2C device is present
i2cdetect -y 1

# Check kernel logs for errors
dmesg | grep -i "error\|failed" | grep -i "seeed\|ac108"
```

### Issue: Audio Still Silent
```bash
# Check if gains are set (should be non-zero after diagnose_audio.sh)
amixer -c 0 get 'ADC1 PGA gain'

# Manually set gains
amixer -c 0 sset 'ADC1 PGA gain' 31
amixer -c 0 sset 'ADC2 PGA gain' 31
amixer -c 0 sset 'ADC3 PGA gain' 31
amixer -c 0 sset 'ADC4 PGA gain' 31

# Test recording again
arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 -d 3 /tmp/test.wav
sox /tmp/test.wav -n stat
```

## 📊 Expected Kernel Logs (After Fixes)

```
[    5.200926] snd_soc_seeed_voicecard: Initializing SEEED Voice Card driver
[    5.817221] ac108: ac108_set_sysclk: Setting sysclk - freq=24000000 Hz, clk_id=1, dir=0
[    5.817225] ac108: ac108_set_sysclk: Using PLL as sysclk source
[    5.820058] seeed-voicecard: Setting device: card name='seeed-4mic' (should NOT be truncated)
```

When recording:
```
seeed-voicecard: seeed_voice_card_startup: stream=Capture
seeed-voicecard: seeed_voice_card_startup: Channel override - playback: 0->2, capture: 0->4
seeed-voicecard: Setting CPU DAI TDM: slots=4, width=32, tx_mask=0xf, rx_mask=0xf
seeed-voicecard: Setting Codec DAI TDM: slots=4, width=32, tx_mask=0xf, rx_mask=0xf
ac108: ac108_hw_params: Configuring hardware parameters
ac108: ac108_hw_params: rate=16000, channels=4, format=6
```

## 🎯 Success Criteria

✅ **All should be true after fixes**:
1. Device name appears as "seeed-4mic" (NOT truncated)
2. No "Unable to install hw params" errors
3. Audio test file created with non-zero audio levels
4. `amixer` shows AC108 mixer controls
5. `dmesg` shows TDM slot configuration logs

## 📝 Documentation References

- Full diagnostic details: [DIAGNOSTIC_FINDINGS.md](DIAGNOSTIC_FINDINGS.md)
- Debug logging improvements: [DEBUG_LOGGING_IMPROVEMENTS.md](DEBUG_LOGGING_IMPROVEMENTS.md)
- Device tree reference: [PI5-INSTALLATION.md](PI5-INSTALLATION.md)

---

**Estimated Total Time**: 30 minutes  
**Difficulty**: Medium  
**Risk**: Low (backup created automatically)
