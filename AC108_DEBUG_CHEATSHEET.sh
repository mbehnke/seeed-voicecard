#!/bin/bash
# AC108 Debug Quick Reference - Cheat Sheet
# Version: 1.0
# For quickly diagnosing AC108 issues on RPi 5 Kernel 6.x

cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════════════╗
║      AC108 AC108 CODEC DEBUGGING - QUICK REFERENCE GUIDE                  ║
║           Raspberry Pi 5 / Kernel 6.12.47+rpt-rpi-2712                    ║
╚═══════════════════════════════════════════════════════════════════════════╝

═══════════════════════════════════════════════════════════════════════════════

█ SECTION 1: IMMEDIATE STATUS CHECKS (Run in this order)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1️⃣  CHECK I2C BUS STATUS
    Command: sudo i2cdetect -y 1
    
    ✅ GOOD: Shows "3b" at address 0x3b
    ❌ BAD:  Shows "UU" at address 0x3b (device locked)
    ⚠️  BAD:  No device shown at 0x3b (device not detected)

2️⃣  CHECK KERNEL LOGS FOR ERRORS
    Command: sudo dmesg | grep -i "ac108\|error\|fail" | tail -30
    
    Look for:
    ✅ "ac108: [probe] ... registered successfully"
    ✅ "ac108: [startup] ✅ COMPLETE"
    ❌ "Device or resource busy"
    ❌ "deferred probe"
    ❌ "Regcache sync failed"

3️⃣  CHECK ALSA CARD REGISTRATION
    Command: cat /proc/asound/cards
    
    ✅ GOOD: Shows "seeed-4mic-voicecard" card
    ❌ BAD:  Only shows "vc4hdmi" devices

4️⃣  CHECK MODULE STATUS
    Command: lsmod | grep ac108
    
    ✅ GOOD: Shows snd_soc_ac108 and seeed_voicecard loaded
    ❌ BAD:  No modules shown

═══════════════════════════════════════════════════════════════════════════════

█ SECTION 2: REGCACHE ISSUES (Main suspect for I2C problems)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

REGCACHE STUCK IN CACHE-ONLY MODE?

Symptoms:
  ❌ Device shows "UU" in i2cdetect (locked but not responding)
  ❌ All register reads fail with "Device or resource busy"
  ❌ Audio capture produces silence (all zeros)
  ❌ Kernel logs don't show error, but hardware isn't responding

Root Cause:
  Regmap in cache-only mode = register writes cached, not reaching hardware

Check:
    Command: sudo cat /sys/kernel/debug/regmap/*/cache_only
    
    ✅ GOOD: Shows "0" or "N" (cache-only DISABLED)
    ❌ BAD:  Shows "1" or "Y" (cache-only ENABLED)

Fix (if needed - requires recompilation):
    In ac108.c around line 1370, must have:
    ┌─ CODE ─────────────────────────────────────────────────────────┐
    │ for (i = 0; i < ac10x->codec_cnt; i++) {                      │
    │     if (ac10x->i2cmap[i] == NULL)                             │
    │         continue;                                              │
    │     regcache_cache_only(ac10x->i2cmap[i], false);            │
    │ }                                                              │
    └────────────────────────────────────────────────────────────────┘

═══════════════════════════════════════════════════════════════════════════════

█ SECTION 3: REGISTER READ/WRITE TESTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

READ CHIP ID (Register 0x00):
    Command: sudo i2cget -y 1 0x3b 0x00 w
    
    ✅ GOOD: Returns "0xff00" or similar (actual value)
    ❌ BAD:  Returns "Error" or "0xff"

READ MOD_CLK_EN (Register 0x21):
    Command: sudo i2cget -y 1 0x3b 0x21 w
    
    ✅ GOOD: After startup, should be "0x91"
    ❌ BAD:  Returns "0x00" (clock not enabled)
    ❌ BAD:  Returns "Error" (hardware not responding)

READ I2S_TX1_CTRL2 (Register 0x38):
    Command: sudo i2cget -y 1 0x3b 0x38 w
    
    ✅ GOOD: After startup, should be "0x0f"
    ❌ BAD:  Returns "0x00" (TX1 channels not enabled)

═══════════════════════════════════════════════════════════════════════════════

█ SECTION 4: DEVICE TREE CHECKS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CHECK DTB STRUCTURE:
    Command: sudo fdtdump /boot/firmware/bcm2712-rpi-5-b.dtb | grep -A20 "ac108"
    
    ✅ MUST HAVE:
       - compatible = "x-power,ac108_0" (or _1, _2, _3)
       - reg = <0x3b>
       - status = "okay"

    ❌ PROBLEMS:
       - status = "disabled" (overlay not merged)
       - Missing "compatible" field
       - Wrong I2C address

CHECK I2C NODE STATUS:
    Command: sudo fdtdump /boot/firmware/bcm2712-rpi-5-b.dtb | grep -B5 -A5 "i2c@"
    
    ✅ MUST HAVE: status = "okay" for i2c node

═══════════════════════════════════════════════════════════════════════════════

█ SECTION 5: ALSA DEVICE NOT REGISTERING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SYMPTOM: seeded-voicecard card missing from /proc/asound/cards

CHECK 1: Is machine driver loading?
    Command: sudo dmesg | grep "seeed_voicecard"
    
    ✅ GOOD: Shows machine driver probe/bind messages
    ❌ BAD:  No messages (driver not probing)

CHECK 2: Is codec binding to I2S?
    Command: sudo cat /proc/asound/cardX/id
    
    ✅ GOOD: Shows device binding info
    ❌ BAD:  File doesn't exist (card not registered)

CHECK 3: Check for deferred probe:
    Command: sudo dmesg | grep "deferred"
    
    ✅ GOOD: No "deferred probe" messages
    ❌ BAD:  Shows "seeed_voicecard: deferred probe"
    
    If deferred, check what's missing:
    - I2C device not detected? (fix: merge DTB overlay)
    - I2S device not ready? (fix: ensure &i2s node has status="okay")
    - Codec not initialized? (fix: ensure AC108 probe succeeds)

═══════════════════════════════════════════════════════════════════════════════

█ SECTION 6: AUDIO CAPTURE TESTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

TEST 1: Check recording devices
    Command: arecord -l
    
    ✅ GOOD: Lists seeed-4mic-voicecard with 4 channels
    ❌ BAD:  Only lists HDMI devices

TEST 2: Test audio capture
    Command: arecord -D hw:0,0 -f S16_LE -r 16000 -c 4 -d 5 test.wav
    
    ✅ GOOD: Creates 5-second WAV file with data
    ❌ BAD:  "Cannot get card index" error (no ALSA device)
    ❌ BAD:  Creates WAV but all zeros (ADC not enabled)

TEST 3: Check audio levels
    Command: sox test.wav -n stat
    
    ✅ GOOD: Shows RMS values > 0.001
    ❌ BAD:  Shows "RMS = 0.0" (silent/all zeros)
    ❌ BAD:  "Unable to open file" (capture failed)

═══════════════════════════════════════════════════════════════════════════════

█ SECTION 7: KERNEL LOG ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

FULL STARTUP SEQUENCE LOG:
    Command: sudo dmesg | grep "ac108:" | tail -40

WHAT TO LOOK FOR:

Phase 1 - Device Probe (boot):
    ✅ "ac108: [probe] Starting for device at I2C address 0x3b"
    ✅ "ac108: [probe] Device index matched"
    ✅ "ac108: [probe] Regmap initialization successful"
    ✅ "ac108: [probe] Regcache cache-only DISABLED"
    ✅ "ac108: [probe] Chip reset completed"
    ✅ "ac108: [probe] ... registered successfully"

Phase 2 - Audio Startup (stream start):
    ✅ "ac108: ac108_audio_startup() called"
    ✅ "ac108: Disabling cache-only mode"
    ✅ "ac108: MOD_CLK_EN=0x91 ✓ VERIFIED"
    ✅ "ac108: [startup] ✅ COMPLETE"

Common Problems:
    ❌ "Device or resource busy" → Regcache issue
    ❌ "Regcache sync failed" → Hardware not responding
    ❌ "deferred probe" → Missing dependency
    ❌ No startup messages → Startup not called

═══════════════════════════════════════════════════════════════════════════════

█ SECTION 8: COMPILATION & INSTALLATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

REBUILD MODULES (after code changes):
    Commands:
    $ cd /home/adm_behnke/seeed-voicecard
    $ make clean
    $ make DEBUG=1              # Enable debug logs
    $ sudo make install
    $ sudo depmod -a
    $ sudo reboot

CHECK BUILD RESULTS:
    Command: make 2>&1 | tail -20
    
    ✅ GOOD: "snd-soc-ac108.ko built successfully"
    ✅ GOOD: Only warnings about "missing prototypes" (non-critical)
    ❌ BAD:  Compilation errors (fix code, retry)

═══════════════════════════════════════════════════════════════════════════════

█ SECTION 9: COMMON FIXES (ONE-LINERS)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

FIX 1: Merge DTB overlay (if device shows "UU")
    $ cd /boot/firmware && \
      sudo fdtoverlay -i bcm2712-rpi-5-b.dtb \
        -o bcm2712-rpi-5-b.dtb.merged \
        /path/to/seeed-4mic-voicecard-rpi5.dtbo && \
      sudo cp bcm2712-rpi-5-b.dtb{.merged,} && \
      sudo reboot

FIX 2: Reload modules (quick fix without reboot)
    $ sudo rmmod snd_soc_ac108 snd_soc_seeed_voicecard 2>/dev/null
    $ sleep 1
    $ sudo modprobe snd_soc_seeed_voicecard
    $ sleep 2
    $ sudo i2cdetect -y 1

FIX 3: Check & fix asound.conf permissions
    $ ls -la /etc/asound.conf
    $ sudo chown root:root /etc/asound.conf
    $ sudo chmod 644 /etc/asound.conf

═══════════════════════════════════════════════════════════════════════════════

█ SECTION 10: USEFUL ONE-LINER TESTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Quick I2C Status:
    $ sudo i2cdetect -y 1 | grep -E "3b|UU"

Quick Kernel Status:
    $ sudo dmesg | grep -E "ac108:.*✓|ac108:.*ERROR" | tail -5

Quick Module Status:
    $ lsmod | grep ac108 && echo "✅ Modules loaded" || echo "❌ Modules not loaded"

Quick ALSA Status:
    $ cat /proc/asound/cards | grep -q seeed && echo "✅ ALSA card found" || echo "❌ ALSA card missing"

Run Full Diagnostics:
    $ cd /home/adm_behnke/seeed-voicecard && sudo ./post_fix_verification.sh

═══════════════════════════════════════════════════════════════════════════════

█ SECTION 11: REGISTER REFERENCE TABLE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Critical Registers (expected values after startup):

Reg   | Name                | Addr | Expected | What it does
------|---------------------|------|----------|-----------------------------------
0x00  | CHIP_ID            | 0x00 | 0xff00   | Read chip ID (verify hardware)
0x21  | MOD_CLK_EN         | 0x21 | 0x91     | Enable I2S/ADC clocks
0x22  | MOD_RST_CTRL       | 0x22 | 0x91     | Deassert module resets
0x30  | I2S_CTRL           | 0x30 | 0xf5     | I2S master/slave + format
0x38  | I2S_TX1_CTRL2      | 0x38 | 0x0f     | Enable all 4 TX channels
0x3c  | I2S_TX1_CHMP_CTRL1 | 0x3c | 0xe4     | TX1 channel mapping
0x70  | ADC_DIG_EN         | 0x70 | 0x??     | ADC digital blocks enable

Read register: sudo i2cget -y 1 0x3b <ADDR> w
Example:       sudo i2cget -y 1 0x3b 0x21 w     # Read MOD_CLK_EN

═══════════════════════════════════════════════════════════════════════════════

█ SECTION 12: EMERGENCY DEBUG STEPS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

IF DEVICE SHOWS "UU" (not responding):

Step 1: Check if it's a regcache issue
    $ sudo dmesg | grep "cache-only"
    
    If nothing shows → regcache code might not be executing
    Add debug log at line 1365 in ac108.c:
    pr_info("DEBUG: Regcache management code executing\n");

Step 2: Force disable cache-only via sysfs (temporary fix)
    $ echo 0 | sudo tee /sys/kernel/debug/regmap/*/cache_only

Step 3: If nothing works, enable debug logs
    $ cd /home/adm_behnke/seeed-voicecard
    $ make DEBUG=1
    $ sudo make install
    $ sudo reboot

Step 4: Capture full debug output
    $ sudo dmesg > /tmp/dmesg.log
    $ arecord -D hw:0,0 -c 4 -r 16000 -d 2 /tmp/test.wav 2>&1 | tee /tmp/arecord.log
    $ sudo dmesg > /tmp/dmesg_after.log

═══════════════════════════════════════════════════════════════════════════════

█ LAST KNOWN GOOD STATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ I2C Communication: WORKING (device shows "3b" in i2cdetect)
⚠️  ALSA Integration: INCOMPLETE (sound card not registering)

Files that made I2C work:
  - ac108.c with regcache bypass (lines ~1370)
  - ac108.c with error handling (lines ~1535-1542)
  - Device Tree overlay merged into DTB

Next problem to solve:
  - Why seeded-voicecard machine driver not registering sound card
  - Check: codec binding to I2S, ALSA configuration, DAI linkage

═══════════════════════════════════════════════════════════════════════════════

EOF
