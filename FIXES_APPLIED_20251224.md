# Fixes Applied - 2025-12-24 16:35

## Problem Diagnosis
**Root Cause**: RPi 5's RP1-I2S controller does NOT support DSP_A/TDM format.
**Error**: `ASoC: error at snd_soc_dai_set_fmt on 1f000a0000.i2s: -22`

## Changes Made

### 1. Device Tree Overlay (seeed-4mic-voicecard-rpi5-overlay.dts)
✅ **Removed ALL TDM properties**:
- Removed `dai-tdm-slot-num`
- Removed `dai-tdm-slot-width`
- Removed `dai-tdm-slot-tx-mask`
- Removed `dai-tdm-slot-rx-mask`

✅ **Enforced I2S format**:
- Set `seeed-voice-card,format = "i2s"` (not `dsp_a`)
- Added comments explaining RPi 5 limitation

### 2. Driver (seeed-voicecard.c)
✅ **Added DSP_A → I2S fallback logic** (line ~625):
```c
/*
 * RPi 5 RP1-I2S Compatibility Fix:
 * The RP1-I2S controller does NOT support DSP_A/TDM mode.
 * If TDM slots are parsed from DT, simple_util_parse_daifmt() may
 * have set DSP_A format. Override to I2S if DSP_A is detected.
 */
if ((dai_link->dai_fmt & SND_SOC_DAIFMT_FORMAT_MASK) == SND_SOC_DAIFMT_DSP_A) {
    dev_warn(dev, "RPi 5 RP1-I2S does NOT support DSP_A/TDM - forcing I2S format\n");
    dai_link->dai_fmt &= ~SND_SOC_DAIFMT_FORMAT_MASK;
    dai_link->dai_fmt |= SND_SOC_DAIFMT_I2S;
    dev_info(dev, "Corrected DAI format: DSP_A -> I2S (0x%04x)\n", dai_link->dai_fmt);
}
```

### 3. Build & Install
✅ Recompiled kernel modules (ac108, seeed-voicecard)
✅ Compiled new DTBO without TDM properties
✅ Merged DTBO into clean DTB (backup-clean)
✅ Applied merged DTB to `/boot/firmware/bcm2712-rpi-5-b.dtb`

## Expected Result After Reboot
✅ **NO more `-22 (EINVAL)` errors**
✅ **seeed-voicecard probe should succeed**
✅ **ALSA card should be registered**: `seeed-4mic-voicecard`
✅ **4-channel recording should work** (via ALSA routing/plugin)

## Testing
Run after reboot:
```bash
./post_reboot_test.sh
```

## Important Notes
⚠️ **Multi-channel limitation**: Since RPi 5 I2S doesn't support TDM natively, 
4-channel capture will require:
- ALSA plugin configuration (`ac108_plugin`)
- OR software-based channel multiplexing
- See `asound_4mic.conf` for ALSA routing

⚠️ **Format locked to I2S**: Cannot use DSP_A or other TDM formats on RPi 5.

## Backups
- DTB backup: `/boot/firmware/bcm2712-rpi-5-b.dtb.backup_20251224_163312`
- Clean DTB: `/boot/firmware/bcm2712-rpi-5-b.dtb.backup-clean` (used as base)

---
**Next**: Reboot and test with `./post_reboot_test.sh`
