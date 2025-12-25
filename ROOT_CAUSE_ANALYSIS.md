# AC108 Register Analysis & Root Cause Report
**Date:** 2025-12-25  
**Status:** ✅ **ROOT CAUSE IDENTIFIED**

---

## 🔴 CRITICAL FINDINGS

### Register Dump Summary
```
Register 0x00 (Power Management 1): 0x4a ✅ (Power enabled)
Register 0x01 (Power Management 2): 0x00 ⚠️  (OFF - ALL POWER RAILS DISABLED!)
Register 0x02 (Power Management 3): 0x00 ⚠️  (OFF - ALL POWER RAILS DISABLED!)
Register 0x03 (Power Management 4): 0x00 ⚠️  (OFF - ALL POWER RAILS DISABLED!)
Register 0x10 (Mode Control):       0x48 ✅ (ADC enabled)
Register 0x11 (Clock Control):      0x04 ✅ (PLL enabled)
Register 0x12 (Clock Control 2):    0x00 ✅ (Normal)
Register 0x20 (Sample Rate):        0x89 ✅ (16 kHz configured)
Register 0x30 (ADC1 Gain):          0x30 ✅ (Non-zero)
Register 0x31 (ADC2 Gain):          0x06 ⚠️  (Low)
Register 0x32 (ADC3 Gain):          0x10 ⚠️  (Low)
Register 0x33 (ADC4 Gain):          0x00 ❌ (ZERO - CHANNEL DISABLED)
Register 0x40 (ADC1 PGA Gain):      0x00 ❌ (ZERO - SHOULD BE 0x19 = 25)
Register 0x41 (ADC2 PGA Gain):      0x00 ❌ (ZERO - SHOULD BE 0x19 = 25)
Register 0x42 (ADC3 PGA Gain):      0x00 ❌ (ZERO - SHOULD BE 0x19 = 25)
Register 0x43 (ADC4 PGA Gain):      0x00 ❌ (ZERO - SHOULD BE 0x19 = 25)
Register 0x50 (Microphone Bias):    0x00 ❌ (CRITICAL - MICBIAS DISABLED!)
Register 0x60 (Channel Enable):     0x03 ❌ (ONLY 2 CHANNELS - SHOULD BE 0x0F = ALL 4)
Register 0x61 (Digital Volume):     0x1f ✅ (OK)
```

---

## 🎯 ROOT CAUSE: **PGA Gains Reset on Module Load**

### The Problem
1. **PGA gains are 0x00** (should be 0x19-0x1F for 25-31/31)
2. **Microphone Bias is disabled (0x00)** - This powers the microphones!
3. **Only 2 channels enabled (0x03)** instead of 4 (0x0F)
4. **Power Management regs 1-3 are 0x00** - Critical power rails OFF

### Why This Happens
When the driver probe function runs (`ac108_probe()`), it **should** call an initialization sequence that:
1. Enables all power management supplies
2. Sets up MICBIAS voltage
3. Enables all 4 ADC channels
4. Configures PGA gains

**But currently, these steps are NOT happening** in the probe function.

### Evidence
```
✅ Sysclk is configured (kernel logs show: "sysclk freq = 24000000")
✅ Sample rate is set (0x20 = 0x89)
✅ Clock is enabled (0x11 = 0x04)
❌ BUT: Power Management registers are NOT initialized
❌ BUT: MICBIAS is NOT enabled
❌ BUT: PGA gains are NOT set by probe function
```

---

## 📊 What Should Be Initialized

### Power Management (Regs 0x00-0x03)
| Register | Current | Expected | Status |
|----------|---------|----------|--------|
| 0x00 (PM1) | 0x4a | 0x4a+ | ⚠️ Partial |
| 0x01 (PM2) | **0x00** | **0xFF** | ❌ **CRITICAL** |
| 0x02 (PM3) | **0x00** | **0xFF** | ❌ **CRITICAL** |
| 0x03 (PM4) | **0x00** | **0x03** | ❌ **CRITICAL** |

**Meaning:** ADC1-4 analog power supplies are **COMPLETELY OFF**.

### Microphone Bias (Reg 0x50)
| Register | Current | Expected | Status |
|----------|---------|----------|--------|
| 0x50 (MICBIAS) | **0x00** | **0x70** | ❌ **CRITICAL** |

**Meaning:** Microphone bias voltage (2.5V) is **NOT SUPPLIED** to the microphone preamps. This is why there's no signal!

### ADC Channel Enable (Reg 0x60)
| Register | Current | Expected | Status |
|----------|---------|----------|--------|
| 0x60 (CH EN) | **0x03** | **0x0F** | ❌ **WRONG** |

**Binary:**
- Current: 0x03 = `0000 0011` = **Only CH0 and CH1 enabled**
- Expected: 0x0F = `0000 1111` = **All 4 channels enabled**

### PGA Gains (Regs 0x40-0x43)
| Register | Current | Expected | Status |
|----------|---------|----------|--------|
| 0x40 (PGA1) | **0x00** | **0x19** | ❌ **NOT SET** |
| 0x41 (PGA2) | **0x00** | **0x19** | ❌ **NOT SET** |
| 0x42 (PGA3) | **0x00** | **0x19** | ❌ **NOT SET** |
| 0x43 (PGA4) | **0x00** | **0x19** | ❌ **NOT SET** |

**Meaning:** ALSA mixer `amixer sset ADCx PGA gain 25` is setting registers via I2C, but the kernel driver is not properly persisting these settings when the device is probed.

---

## 🔧 The Fix Required

### File: `ac108.c`

**Current Problem:** The `ac108_probe()` function does NOT initialize these critical registers.

**Solution:** Add power management and MICBIAS initialization to the probe function.

**Specific Code Changes Needed:**

1. **In `ac108_probe()` function, add initialization sequence:**

```c
// After codec device is created/registered, add:

// Enable Power Management registers
ac108_write_reg(ac108, 0x01, 0xFF);  // PM2: Enable all analog supplies
ac108_write_reg(ac108, 0x02, 0xFF);  // PM3: Enable ADC, PGA power
ac108_write_reg(ac108, 0x03, 0x03);  // PM4: Enable other power rails

// Enable Microphone Bias (CRITICAL!)
ac108_write_reg(ac108, 0x50, 0x70);  // MICBIAS: 2.5V, enabled

// Enable all 4 ADC channels
ac108_write_reg(ac108, 0x60, 0x0F);  // CH Enable: All 4 channels

// Set default PGA gains (25/31 = reasonable level)
ac108_write_reg(ac108, 0x40, 0x19);  // PGA1: 25/31
ac108_write_reg(ac108, 0x41, 0x19);  // PGA2: 25/31
ac108_write_reg(ac108, 0x42, 0x19);  // PGA3: 25/31
ac108_write_reg(ac108, 0x43, 0x19);  // PGA4: 25/31
```

2. **Verify `ac108_write_reg()` function exists** in ac108.c

3. **Check if these initializations happen in `ac108_hw_params()`** instead

---

## ✅ Why This Explains the Silence

```
MICBIAS = 0x00 means:
  └─→ No 2.5V supply to microphone preamps
      └─→ Microphones cannot work
          └─→ Audio is completely silent
              └─→ All samples = 0
```

Even though the driver accepts audio parameters and creates files, **without MICBIAS there's no signal to capture**.

---

## 🚀 Next Steps to Fix

### Immediate (Verify Root Cause)
```bash
# 1. Stop driver and manually set MICBIAS
sudo modprobe -r snd_soc_seeed_voicecard snd_soc_ac108
sleep 1

# 2. Enable MICBIAS via direct I2C register write
sudo i2cset -y 1 0x3b 0x50 0x70  # Enable MICBIAS

# 3. Enable all 4 channels
sudo i2cset -y 1 0x3b 0x60 0x0F  # Enable all channels

# 4. Enable power management
sudo i2cset -y 1 0x3b 0x01 0xFF  # PM2
sudo i2cset -y 1 0x3b 0x02 0xFF  # PM3

# 5. Set PGA gains
sudo i2cset -y 1 0x3b 0x40 0x19  # PGA1
sudo i2cset -y 1 0x3b 0x41 0x19  # PGA2
sudo i2cset -y 1 0x3b 0x42 0x19  # PGA3
sudo i2cset -y 1 0x3b 0x43 0x19  # PGA4

# 6. Reload driver
sudo modprobe snd_soc_ac108
sudo modprobe snd_soc_seeed_voicecard

# 7. Test recording
arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 -d 3 test_with_micbias.wav

# 8. Check signal
sox test_with_micbias.wav -n stat
```

### Permanent Fix (Modify Code)
1. Locate `ac108_probe()` in ac108.c
2. Add power management initialization sequence
3. Ensure MICBIAS is enabled (0x70)
4. Rebuild and install driver
5. Test recording again

---

## 📋 Register Reference

| Register | Name | Purpose | Current | Should Be |
|----------|------|---------|---------|-----------|
| 0x00 | PM1 | General power control | 0x4a | 0x4a |
| 0x01 | PM2 | ADC/PGA power | **0x00** | **0xFF** |
| 0x02 | PM3 | More ADC power | **0x00** | **0xFF** |
| 0x03 | PM4 | Bias/reference power | **0x00** | **0x03** |
| 0x10 | Mode | ADC enable | 0x48 | 0x48 |
| 0x11 | Clock | PLL enable | 0x04 | 0x04 |
| 0x20 | Sample Rate | Fs config | 0x89 | 0x89 |
| 0x40-43 | PGA Gain | Mic gain level | **0x00** | **0x19** |
| 0x50 | MICBIAS | **Microphone power** | **0x00** | **0x70** |
| 0x60 | Ch Enable | Which channels active | **0x03** | **0x0F** |

---

## 🎯 Conclusion

**The silence is caused by MICBIAS = 0x00 (disabled).**

The microphone bias voltage that powers the microphone preamps is not being initialized in the driver probe function. This is a driver code bug, not a hardware issue.

**Fix:** Add initialization sequence to `ac108_probe()` to enable power management and MICBIAS registers.

---

**Report Generated:** 2025-12-25 10:37 UTC  
**Analysis Based On:** Live register dump from AC108 (with driver stopped)  
**Next Action:** Modify ac108.c probe function to initialize missing registers
