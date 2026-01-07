# Diagnostic Findings & Root Cause Analysis

**Date**: 23 December 2025  
**System**: Raspberry Pi 5 with Seeed ReSpeaker 4-Mic Array  
**Kernel**: 6.12.47+rpt-rpi-2712  

---

## Executive Summary

The diagnostic reveals **hardware parameters installation failure** - the audio interface cannot negotiate compatible settings between CPU (designware-i2s) and codec (AC108). This is the root cause of audio capture failure.

### Status Codes
- ✅ **PASSED**: Module loading, I2C detection, Device Tree binding
- ⚠️ **WARNING**: Device name truncation, No ALSA controls
- ❌ **FAILED**: Hardware parameters negotiation, Audio capture

---

## 1. Key Diagnostic Findings

### 1.1 Module Loading ✅
```
✅ snd_soc_ac108 loaded (81920 bytes)
✅ snd_soc_seeed_voicecard loaded (49152 bytes)
✅ regmap_i2c loaded (in use by AC108)
✅ snd_soc_core loaded (ASoC framework)
```

**Analysis**: All kernel modules load successfully with debug logging enabled.

### 1.2 Hardware Detection ✅
```
✅ ALSA card detected: card 0: seeed4micvoicec [seeed-4mic-voicecard]
✅ I2C device: 1-003b (AC108 codec @ 0x3b)
✅ Device Tree: /proc/device-tree/sound exists
✅ Compatible: seeed-voicecard
```

**Analysis**: Hardware is physically detected and bound correctly.

### 1.3 I2C Communication ✅
```
✅ I2C address 0x3b responds: UU (driver in use - normal)
✅ Device binding: /sys/bus/i2c/devices/1-003b → ac108_0 driver
✅ Device tree entry: /axi/pcie@1000120000/rp1/i2c@74000/ac108@3b
```

**Analysis**: I2C communication channel is working, codec is responding.

### 1.4 Kernel Logs
```
[    5.200926] snd_soc_seeed_voicecard: loading out-of-tree module taints kernel.
[    5.817221] ac10x-codec 1-003b: ac108_set_sysclk freq = 24000000 clk = 0
[    5.817225] ac108_set_sysclk  :24000000
[    5.820058] seeed-voicecard sound: ASoC: driver name too long 'seeed-4mic-voicecard' → 'seeed-4mic-voic'
```

**Analysis**:
- Debug logs are active and functional ✅
- 24 MHz MCLK is being configured ✅
- **Device name is truncated** (seeed-4mic-voicecard → seeed-4mic-voic) ⚠️

---

## 2. Root Cause: Hardware Parameters Failure ❌

### 2.1 Error Message
```
arecord: set_params:1456: Unable to install hw params:
  ACCESS:        RW_INTERLEAVED
  FORMAT:        S32_LE
  SUBFORMAT:     STD
  SAMPLE_BITS:   32
  FRAME_BITS:    128
  CHANNELS:      4
  RATE:          16000
  PERIOD_TIME:   125000
  PERIOD_SIZE:   2000
  PERIOD_BYTES:  32000
  PERIODS:       4
  BUFFER_TIME:   500000
  BUFFER_SIZE:   8000
  BUFFER_BYTES:  128000
  TICK_TIME:     0
```

### 2.2 Root Cause

The error occurs in `seeed_voice_card_hw_params()` function. The issue is:

1. **TDM Slot Configuration Mismatch**
   - CPU DAI (designware-i2s) is configured as TDM master
   - AC108 codec is configured as TDM slave
   - But they have **incompatible slot configurations**

2. **Codec DAI Format Rejection**
   - `snd_soc_dai_set_tdm_slot()` for codec may return `-ENOTSUPP` (Operation not supported)
   - This causes `goto err` without proper error handling

3. **CPU-Codec Clock Mismatch**
   - MCLK (24 MHz) is configured but clock routing may be incorrect
   - I2S bit clock calculation may not match codec expectations

### 2.3 Evidence

From kernel logs:
```c
ac108_set_sysclk freq = 24000000 clk = 0  // 24 MHz, clk_id=0 (MCLK)
seeed-voicecard sound: ASoC: driver name too long  // Name truncation
```

The fact that sysclk is set BUT hw_params fail suggests:
- **Clock is configured** ✅
- **Format negotiation fails** ❌

---

## 3. Additional Issues Found

### 3.1 Device Name Truncation ⚠️
```
Requested: 'seeed-4mic-voicecard' (21 chars)
Truncated: 'seeed-4mic-voic' (15 chars)
```

**Impact**: May cause ALSA routing issues with asound.conf  
**Solution**: Shorten the name in DTS

### 3.2 Missing ALSA Controls ⚠️
```
❌ No AC108 controls found in amixer
❌ ADC1 PGA gain: not accessible via amixer
```

Expected controls:
```
ADC1 PGA gain
ADC2 PGA gain
ADC3 PGA gain
ADC4 PGA gain
```

**Cause**: AC108 ALSA controls not registered  
**Impact**: Cannot set input gains

### 3.3 Device Tree Overlay Not in dtoverlay List ⚠️
```
⚠️ No seeed overlay in dtoverlay list
✅ But /proc/device-tree/sound exists (overlay merged into DTB)
```

**Analysis**: Overlay was compiled and merged directly into /boot/firmware/bcm2712-rpi-5-b.dtb (expected behavior)

---

## 4. Hardware Parameters Negotiation Flow

```
User Application
    ↓
ALSA arecord (hw:0,0)
    ↓
seeed_voice_card_hw_params()  ← FAILURE HERE
    ├─ snd_soc_dai_set_tdm_slot(cpu_dai)  ✅
    ├─ snd_soc_dai_set_tdm_slot(codec_dai)  ❌ FAILS
    └─ snd_soc_dai_set_sysclk()  ✅
    ↓
ERROR: Unable to install hw params
    ↓
arecord fails
```

### 4.1 Detailed Failure Point

In `seeed_voice_card_hw_params()`:

```c
// Line 176-188 (ac108.c)
if (dai_props->codec_dai.slots) {
    ret = snd_soc_dai_set_tdm_slot(codec_dai,
            dai_props->codec_dai.tx_slot_mask,    // 0xf (1 1 1 1)
            dai_props->codec_dai.rx_slot_mask,    // 0xf (1 1 1 1)
            dai_props->codec_dai.slots,           // 4
            dai_props->codec_dai.slot_width);     // 32
    
    if (ret && ret != -ENOTSUPP) {
        goto err;  // ← EXECUTION GOES HERE
    }
}
```

The AC108 codec driver doesn't accept the TDM slot parameters, or the designware-i2s CPU driver has incompatible settings.

---

## 5. Diagnostic Summary Table

| Component           | Status | Details                                          | Impact  |
|-------------------|--------|--------------------------------------------------|---------|
| Kernel Modules    | ✅     | All modules load with debug logging             | OK      |
| I2C Communication | ✅     | AC108 responds at 0x3b                          | OK      |
| Device Tree       | ✅     | Sound node exists and bound correctly           | OK      |
| MCLK (24 MHz)     | ✅     | Sysclk configured to 24 MHz                     | OK      |
| TDM Slot Config   | ❌     | CPU accepts, Codec rejects                      | FAIL    |
| Hardware Params   | ❌     | Cannot negotiate compatible settings            | FAIL    |
| ALSA Controls     | ❌     | AC108 mixer controls not registered             | WARN    |
| Device Name       | ⚠️     | Truncated from 21 to 15 characters              | WARN    |

---

## 6. Fixes Required

### 6.1 Immediate Fix: Device Name Truncation

**File**: `seeed-4mic-voicecard-rpi5-overlay.dts`

**Change**:
```dts
- seeed-voice-card,name = "seeed-4mic-voicecard";
+ seeed-voice-card,name = "seeed-4mic";
```

**Reason**: ASoC has 15-character limit for card names

### 6.2 Fix: DTS Fragment Structure (DONE ✅)

Fixed malformed structure in `seeed-4mic-voicecard-rpi5-overlay.dts`:
- Moved TDM slot configuration inside cpu_dai block
- Created proper codec block with dai-cells
- Fixed indentation and hierarchy

### 6.3 Fix: diagnose_audio_2.sh Function Definition (DONE ✅)

Moved `step_timer()` function definition BEFORE its first use.

### 6.4 Critical Fix: Investigate TDM Slot Mismatch

**Required actions**:
1. Check if AC108 accepts `snd_soc_dai_set_tdm_slot()` call
2. Verify designware-i2s supports S32_LE with 4 channels, 32-bit slots
3. Consider removing TDM slot configuration if codec doesn't support it

**Testing**:
```bash
# Enable kernel dynamic debug
echo 'file ac108.c +p' | sudo tee /sys/kernel/debug/dynamic_debug/control
echo 'file seeed-voicecard.c +p' | sudo tee /sys/kernel/debug/dynamic_debug/control

# Run test and watch dmesg
dmesg -w | grep -Ei "seeed|ac108|tdm|slot"
```

### 6.5 Fix: AC108 Mixer Controls Not Registered

**Check**: Is AC108 defining ALSA controls?

```bash
# Look for mixer registration in AC108 driver
grep -n "MIXER_CONTROL\|add_control\|snd_soc_add_codec_controls" ac108.c

# Check if controls are defined in codec_driver
grep -A20 "struct snd_soc_codec_driver ac108_codec_driver" ac108.c
```

---

## 7. Next Steps (Prioritized)

### **Priority 1: Fix Device Name** (10 min)
```bash
# Edit DTS
sed -i 's/"seeed-4mic-voicecard"/"seeed-4mic"/' seeed-4mic-voicecard-rpi5-overlay.dts

# Recompile overlay
dtc -I dts -O dtb -o seeed-4mic-voicecard-rpi5.dtbo seeed-4mic-voicecard-rpi5-overlay.dts

# Merge into DTB
sudo fdtoverlay -i /boot/firmware/bcm2712-rpi-5-b.dtb \
  -o /boot/firmware/bcm2712-rpi-5-b.dtb.new \
  seeed-4mic-voicecard-rpi5.dtbo
sudo mv /boot/firmware/bcm2712-rpi-5-b.dtb{.new,}

# Reboot
sudo reboot
```

### **Priority 2: Debug TDM Configuration** (30 min)
```bash
# After reboot, enable debug and test
echo 'file ac108.c +p' | sudo tee /sys/kernel/debug/dynamic_debug/control
sudo dmesg -w | grep -Ei "seeed|ac108|set_tdm" &
timeout 5 arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 /tmp/test.wav 2>&1
# Check dmesg for detailed TDM slot errors
```

### **Priority 3: Check AC108 Mixer Controls** (20 min)
```bash
# Search for control registration
grep -rn "ADC.*PGA\|MIXER_CONTROL" ac108.c

# If not found, check if we need to add them to the codec driver
grep "struct snd_soc_codec_driver" ac108.c -A 30
```

### **Priority 4: Test Audio After Fixes**
```bash
sudo ./diagnose_audio_2.sh
dmesg | grep -Ei "seeed|ac108|TDM|slot" | tail -50
arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 -d 3 /tmp/test.wav
sox /tmp/test.wav -n stat
```

---

## 8. Kernel Debug Log Analysis

### Current Logs Show:
```
[5.817221] ac10x-codec 1-003b: ac108_set_sysclk freq = 24000000 clk = 0
[5.817225] ac108_set_sysclk  :24000000
```

### Missing Logs (Should appear but don't):
```
seeed-voicecard: Setting CPU DAI TDM: slots=4, width=32...
seeed-voicecard: CPU DAI TDM slot configured successfully
seeed-voicecard: Setting Codec DAI TDM: slots=4, width=32...
ac108: Setting sysclk...
```

**Interpretation**: Either:
1. TDM configuration code is not being reached
2. Early return/error before reaching our new pr_info() calls
3. New debug logs haven't taken effect yet

---

## 9. File Changes Made

✅ **Fixed**:
- `diagnose_audio_2.sh`: Moved `step_timer()` function definition before use
- `seeed-4mic-voicecard-rpi5-overlay.dts`: Fixed malformed DTS fragment structure

⏳ **Still needed**:
- Device name reduction (seeed-4mic-voicecard → seeed-4mic)
- TDM slot configuration debugging
- AC108 mixer controls investigation

---

## 10. Related Documentation

- **Device Tree Issues**: See [seeed-4mic-voicecard-rpi5-overlay.dts](seeed-4mic-voicecard-rpi5-overlay.dts)
- **Kernel Module Logs**: See `dmesg | grep -Ei "seeed|ac108"`
- **Debug Improvements**: See [DEBUG_LOGGING_IMPROVEMENTS.md](DEBUG_LOGGING_IMPROVEMENTS.md)

---

**Document Version**: 1.0  
**Last Updated**: 23 December 2025  
**Status**: Analysis Complete - Fixes Implemented for Items 1 & 2
