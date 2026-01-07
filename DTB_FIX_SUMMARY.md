# Device Tree Fix - 2025-12-25 16:53

## Problem Identified

The seeed-voicecard driver was **failing to probe** with error -22 (EINVAL) due to duplicate device tree nodes.

### Root Cause

The `/boot/firmware/bcm2712-rpi-5-b.dtb` file had **duplicate sound card nodes**:

**WRONG Structure (before fix):**
```dts
sound {
    seeed-voice-card,codec { ... }        // ❌ Direct child - WRONG
    seeed-voice-card,cpu { ... }          // ❌ Direct child - WRONG

    seeed-voice-card,dai-link {           // ✅ Correct structure
        seeed-voice-card,codec { ... }    // ✅ Nested child - CORRECT
        seeed-voice-card,cpu { ... }      // ✅ Nested child - CORRECT
    }
}
```

### What Happened

1. The driver iterated through children of the `sound` node
2. It found `seeed-voice-card,codec` as the first child (instead of `seeed-voice-card,dai-link`)
3. It tried to parse `seeed-voice-card,codec` as if it were a DAI link container
4. It failed with "Can't find CPU DT node" because the codec node doesn't contain a cpu child
5. Driver probe failed with error -22

### Error Messages

```
[6.024108] seeed-voicecard sound: seeed_voice_card_dai_link_of: Can't find CPU DT node
[6.024110] seeed-voicecard sound: parse error -22
[6.024112] seeed-voicecard sound: probe with driver seeed-voicecard failed with error -22
```

## Fix Applied

### Actions Taken

1. **Restored clean base DTB**
   ```bash
   sudo cp /boot/firmware/bcm2712-rpi-5-b.dtb.baseclean /boot/firmware/bcm2712-rpi-5-b.dtb
   ```

2. **Recompiled overlay from source**
   ```bash
   sudo dtc -@ -I dts -O dtb -o /boot/firmware/overlays/seeed-4mic-voicecard-rpi5.dtbo \
       seeed-4mic-voicecard-rpi5-overlay.dts
   ```

3. **Merged overlay correctly**
   ```bash
   sudo fdtoverlay -i /boot/firmware/bcm2712-rpi-5-b.dtb \
       -o /tmp/test-merge.dtb \
       /boot/firmware/overlays/seeed-4mic-voicecard-rpi5.dtbo
   ```

4. **Verified merged structure** - confirmed no duplicate nodes

5. **Applied fixed DTB**
   ```bash
   sudo cp /tmp/test-merge.dtb /boot/firmware/bcm2712-rpi-5-b.dtb
   ```

### Correct Structure (after fix)

```dts
sound {
    compatible = "seeed-voicecard";
    seeed-voice-card,name = "seeed-4mic-voicecard";
    seeed-voice-card,channels-playback-override = <4>;
    seeed-voice-card,channels-capture-override = <4>;
    status = "okay";

    seeed-voice-card,dai-link {
        seeed-voice-card,format = "i2s";
        seeed-voice-card,bitclock-master = <&i2s>;
        seeed-voice-card,frame-master = <&i2s>;

        seeed-voice-card,codec {
            sound-dai = <&ac108_a>;
            clocks = <&ac108_mclk>;
            clock-names = "mclk";
        };

        seeed-voice-card,cpu {
            sound-dai = <&i2s>;
        };
    }
}
```

## Additional Fix

Fixed syntax error in `diagnose_audio_2.sh` script:
- Escaped `${ch}` variables as `\${ch}` in eval strings (lines 134, 138)

## Expected Result After Reboot

After rebooting, the driver should:
1. Find the `seeed-voice-card,dai-link` node correctly
2. Parse the nested cpu and codec nodes successfully
3. Create the ALSA sound card
4. Register 4 capture channels

You should see:
```bash
arecord -l
**** List of CAPTURE Hardware Devices ****
card 0: seeed4micvoicec [seeed-4mic-voicecard], device 0: bcm2835-i2s-ac10x-codec0 ac10x-codec0-0 [bcm2835-i2s-ac10x-codec0 ac10x-codec0-0]
  Subdevices: 1/1
  Subdevice #0: subdevice #0
```

## Files Modified

- `/boot/firmware/bcm2712-rpi-5-b.dtb` - Fixed device tree (backed up to `.backup-20251225-165328`)
- `/boot/firmware/overlays/seeed-4mic-voicecard-rpi5.dtbo` - Recompiled from source
- `diagnose_audio_2.sh` - Fixed syntax error

## Next Steps

**REBOOT REQUIRED** to load the fixed device tree:

```bash
sudo reboot
```

After reboot, verify with:
```bash
arecord -l
dmesg | grep -i seeed
```
