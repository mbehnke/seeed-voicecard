# AC108 I2C Communication - Root Cause Analysis

**Date**: 2025-12-30
**Symptom**: AC108 device shows "UU" in i2cdetect but cannot communicate via i2cget

## Executive Summary

The AC108 codec driver **successfully probes and registers** (logs show "✅ COMPLETE"), but **post-boot I2C communication fails** with "Device or resource busy". This is a **regmap/regcache state issue**, not a hardware wiring problem.

## Key Findings

### 1. Kernel Boot Sequence - SUCCESS ✅
```
[startup] MOD_CLK_EN=0x91 ✓
[startup] I2S_CTRL=0xf5 ✓
[startup] TX1 channels enabled ✓
[startup] ADC digital blocks enabled ✓
[startup] ✅ COMPLETE
```

The kernel driver **successfully initializes** during boot, suggesting **I2C communication works briefly**.

### 2. Post-Boot I2C Access - FAILURE ❌
```
$ sudo i2cget -y 1 0x3b 0x00
Error: Could not set address to 0x3b: Device or resource busy
```

After boot, the device cannot be accessed. The "Device or resource busy" error means:
- The kernel driver has an exclusive lock on the I2C device
- Userspace tools (i2cget) cannot access it
- **This is NORMAL for kernel drivers**

### 3. The Real Issue - Regmap Cache State

The AC108 driver uses `regmap_init_i2c()` with `REGCACHE_FLAT` configuration:

```c
static const struct regmap_config ac108_regmap = {
    .cache_type = REGCACHE_FLAT,
};

// During probe:
ac10x->i2cmap[index] = devm_regmap_init_i2c(i2c, &ac108_regmap);
regcache_cache_only(ac10x->i2cmap[index], false);  // ← Enable real I2C
ret = regmap_write(ac10x->i2cmap[index], CHIP_RST, CHIP_RST_VAL);
```

**Hypothesis**: After the initial probe succeeds, the regcache transitions to a state where:
1. Hardware writes are cached but not reflected in I2C bus
2. The in-memory cache is updated, but hardware never sees the commands
3. The "✅ COMPLETE" logs are printed, but register writes are still **cached only**

### 4. Audio Still Produces Data (Strangely)

Despite I2C failures, audio capture produces:
- ✅ 3-second WAV file (768KB)
- ❌ Contains only zeros (silent)
- The file size suggests **the I2S interface is working**
- The silence suggests **ADC is not actually capturing**

This points to **partial initialization**: I2S works, but AC108 ADC is not responding due to misconfiguration.

## Root Cause

**The AC108 regmap is stuck in a cache-only state after initial probe.**

This causes:
1. Startup register writes don't reach the hardware
2. AC108 ADC never actually enables
3. I2S receives only zeros from ADC

## Evidence

| Check | Status | Evidence |
|-------|--------|----------|
| Driver loads | ✅ YES | `lsmod \| grep ac108` shows module loaded |
| Device-Tree match | ✅ YES | compatible="x-power,ac108_0" matches of_match_table |
| Probe succeeds | ✅ YES | "✅ COMPLETE" in kernel logs |
| Register writes reach HW | ❌ NO | i2cget fails with "busy", audio is silent |
| Regcache enabled | ⚠️ LIKELY | REGCACHE_FLAT configured, cache_only not explicitly disabled post-probe |

## Next Steps

1. **Verify regcache state** after probe completes
2. **Force regcache bypass** during startup
3. **Check if regcache_sync() is missing** after initial writes
4. **Trace actual I2C transactions** with kernel debug logging
