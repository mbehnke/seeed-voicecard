# Implementation Checklist

## ✅ Completed Items

### Kernel Module Debug Logging
- [x] seeed-voicecard.c: Module init/exit logging
- [x] seeed-voicecard.c: Startup function logging  
- [x] seeed-voicecard.c: Channel override tracking
- [x] seeed-voicecard.c: CPU DAI TDM slot config logging
- [x] seeed-voicecard.c: Codec DAI TDM slot config logging
- [x] seeed-voicecard.c: MCLK/SYSCLK config logging
- [x] ac108.c: System clock configuration logging
- [x] ac108.c: Hardware parameters logging
- [x] ac108.c: Sample resolution validation logging
- [x] ac108.c: Sample rate index logging

### Diagnostic Scripts
- [x] diagnose_audio_2.sh: Fixed step_timer function order
- [x] diagnose_audio_2.sh: Added kernel modules check (Step 0)
- [x] diagnose_audio_2.sh: Added I2S/Clock check (Step 6a)
- [x] diagnose_audio_2.sh: Enhanced I2C detection
- [x] diagnose_audio_2.sh: Updated console output
- [x] early_boot_capture.sh: Added kernel version check
- [x] early_boot_capture.sh: Added module status
- [x] early_boot_capture.sh: Added DT overlay check
- [x] early_boot_capture.sh: Added I2C AC108 detection
- [x] early_boot_capture.sh: Added clock config check
- [x] early_boot_capture.sh: Added DAI format check
- [x] early_boot_capture.sh: Added hwparams dump

### Device Tree Fixes
- [x] seeed-4mic-voicecard-rpi5-overlay.dts: Fixed DTS structure
- [x] seeed-4mic-voicecard-rpi5-overlay.dts: Shortened device name
- [x] seeed-4mic-voicecard-rpi5-overlay.dts: Fixed TDM slot config
- [x] seeed-4mic-voicecard-rpi5-overlay.dts: Updated channel counts

### Documentation
- [x] DEBUG_LOGGING_IMPROVEMENTS.md: Comprehensive logging reference
- [x] DIAGNOSTIC_FINDINGS.md: Root cause analysis
- [x] QUICK_FIX_GUIDE.md: Implementation steps
- [x] IMPLEMENTATION_SUMMARY.md: Overview of all changes
- [x] IMPLEMENTATION_CHECKLIST.md: This file

## 🔧 Pending Items

### Before Testing
- [ ] Compile DTS to DTBO
  ```bash
  dtc -I dts -O dtb -o seeed-4mic-voicecard-rpi5.dtbo seeed-4mic-voicecard-rpi5-overlay.dts
  ```

- [ ] Backup DTB
  ```bash
  sudo cp /boot/firmware/bcm2712-rpi-5-b.dtb /boot/firmware/bcm2712-rpi-5-b.dtb.backup
  ```

- [ ] Merge overlay into DTB
  ```bash
  sudo fdtoverlay -i /boot/firmware/bcm2712-rpi-5-b.dtb \
    -o /boot/firmware/bcm2712-rpi-5-b.dtb.merged \
    seeed-4mic-voicecard-rpi5.dtbo
  sudo mv /boot/firmware/bcm2712-rpi-5-b.dtb.merged /boot/firmware/bcm2712-rpi-5-b.dtb
  ```

- [ ] Rebuild modules with debug
  ```bash
  cd /home/adm_behnke/seeed-voicecard
  make clean && make DEBUG=1
  sudo make install
  sudo depmod -a
  ```

- [ ] Reboot system
  ```bash
  sudo reboot
  ```

### Verification (After Reboot)
- [ ] Verify modules loaded
  ```bash
  lsmod | grep -E "snd_soc_ac108|seeed"
  ```

- [ ] Check device name (should be "seeed-4mic")
  ```bash
  arecord -l | grep seeed
  ```

- [ ] Enable kernel debug
  ```bash
  echo 'file seeded-voicecard.c +p' | sudo tee /sys/kernel/debug/dynamic_debug/control
  echo 'file ac108.c +p' | sudo tee /sys/kernel/debug/dynamic_debug/control
  ```

- [ ] Test diagnostics
  ```bash
  sudo ./diagnose_audio_2.sh
  ```

- [ ] Check JSON status
  ```bash
  cat logs/ac108_debug_*/status.json | jq .
  ```

### Investigation Tasks
- [ ] Debug TDM slot configuration
  - Watch kernel logs for error messages
  - Check AC108 codec driver TDM support
  - Verify designware-i2s parameters

- [ ] Investigate missing ALSA controls
  - Search for mixer control definitions in ac108.c
  - Check if controls are registered
  - May need to add control definitions

- [ ] Test audio capture
  - Record test file: `arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 -d 3 /tmp/test.wav`
  - Verify audio levels: `sox /tmp/test.wav -n stat`

## 📊 Status Summary

| Category | Status | Items | Notes |
|----------|--------|-------|-------|
| Kernel Logging | ✅ Complete | 10 | All pr_info/dev_info added |
| Scripts | ✅ Complete | 12 | Both scripts enhanced + fixed |
| Device Tree | ✅ Complete | 4 | Structure + name + TDM fixed |
| Documentation | ✅ Complete | 5 | Comprehensive guides created |
| **Before Testing** | ⏳ Pending | 4 | DTS compile, DTB merge, rebuild, reboot |
| **Verification** | ⏳ Pending | 5 | Module check, device name, debug, diagnostics |
| **Investigation** | ⏳ Pending | 3 | TDM debugging, ALSA controls, audio test |

**Overall Completion**: 60% (implementation done, testing pending)

## 🎯 Next Steps (Ordered)

### Phase 1: Device Tree & Module Rebuild (15 min)
1. Compile DTS overlay to DTBO
2. Backup existing DTB
3. Merge overlay into DTB
4. Recompile kernel modules with DEBUG=1
5. Install modules and update depmod

### Phase 2: System Restart & Verification (10 min)
6. Reboot system
7. Verify modules loaded
8. Check device name in ALSA
9. Enable kernel dynamic debugging
10. Run diagnostic script

### Phase 3: Debugging (30+ min)
11. Analyze kernel logs for TDM configuration
12. Check AC108 mixer control registration
13. Test audio capture with detailed logging
14. Document findings for troubleshooting

## 📝 Notes

### Important Reminders
- Always backup DTB before merging overlays
- Run diagnostics with `sudo` for full access
- Keep kernel logs for reference: `dmesg > kernel_log_$(date +%s).txt`
- Test after each major change

### Known Issues
1. **Hardware Parameters Failure**: TDM slot negotiation between CPU and codec
2. **Missing ALSA Controls**: AC108 mixer controls not registering
3. **Device Name Truncation**: ✅ FIXED (shortened to "seeed-4mic")

### Test Commands Reference
```bash
# Basic diagnostics
sudo ./diagnose_audio.sh

# Advanced diagnostics  
sudo ./diagnose_audio_2.sh

# Boot diagnostics
sudo ./early_boot_capture.sh

# Manual audio test
arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 -d 3 /tmp/test.wav
sox /tmp/test.wav -n stat

# Check mixer
amixer -c 0 scontrols
amixer -c 0 contents
```

## 📞 Reference Documents

- **Quick Start**: QUICK_FIX_GUIDE.md
- **Detailed Analysis**: DIAGNOSTIC_FINDINGS.md  
- **Logging Reference**: DEBUG_LOGGING_IMPROVEMENTS.md
- **Implementation Overview**: IMPLEMENTATION_SUMMARY.md
- **This File**: IMPLEMENTATION_CHECKLIST.md

---

**Created**: 23 December 2025  
**Last Updated**: 23 December 2025  
**Estimated Completion**: 24 December 2025 (after Phase 3)  
**Difficulty Level**: Medium  
**Risk Level**: Low (backups in place)
