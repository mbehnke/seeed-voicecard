# **Seeed 4-Mic Array (RPi 5 / Kernel 6.x) – AI Coding Instructions**

## **Project Overview**
Linux kernel driver for **Seeed ReSpeaker 4-Mic Array** on **Raspberry Pi 5 (Kernel 6.x)**.
**Key Components**:
- **Kernel Modules**: `snd-soc-ac108.ko` (AC108 codec), `snd-soc-seeed-voicecard.ko` (machine driver)
- **ALSA Plugin**: `ac108_plugin/` for multi-channel capture
- **Device Tree Overlays**: Configures I2S/I2C for AC108
- **Audio Configs**: `asound_4mic.conf` for ALSA routing

---

## **Architecture**
### **Core Components**
| Component               | File                     | Purpose                                                                 |
|-------------------------|--------------------------|-------------------------------------------------------------------------|
| **Machine Driver**      | `seeed-voicecard.c`      | Binds CPU DAI (I2S) to AC108 codec, manages clock/startup sequences      |
| **AC108 Codec Driver**  | `ac108.c`               | Multi-channel ADC with PLL, register maps, and capture configuration  |
| **Device Tree Overlay** | `seeed-4mic-voicecard-rpi5-overlay.dts` | Configures I2S, I2C, MCLK, and audio routing for RPi 5               |
| **ALSA Plugin**         | `ac108_plugin/`         | Userspace PCM plugin for AC108 capture support                         |

### **Data Flow**
1. **User App** → ALSA (`/dev/snd/pcm*`)
2. **ALSA Core** → `seeed-voicecard` machine driver
3. **Machine Driver** → AC108 codec (I2C control, I2S data)
4. **AC108** → Multi-channel audio → ALSA plugin → Userspace

---

## **RPi 5 / Kernel 6.x Specifics**
### **Critical Checks**
| Area                     | Issue                                                                 | Fix                                                                                     |
|--------------------------|-----------------------------------------------------------------------|----------------------------------------------------------------------------------------|
| **Kernel Compatibility** | ASoC API changes (e.g., `snd_soc_dai_set_fmt`, `devm_*` functions)     | Update driver to use `devm_snd_soc_register_card` and modern ASoC APIs.               |
| **I2S Format Support**   | RPi 5’s `designware-i2s` **does not support `DSP_A` (TDM)**            | Force `simple-audio-card,format = "i2s"` in DTS. Use software channel multiplexing.      |
| **Clock Configuration**  | AC108 requires **24 MHz MCLK**, but RPi 5 uses different clock sources | Define `fixed-clock` in DTS: `ac108_mclk: clock-frequency = <24000000>;`.               |
| **Device Tree Bindings** | RPi 5 uses **new bindings** (`brcm,bcm2712-i2s`, `rp1-i2c`)             | Update DTS `compatible` strings and node paths.                                       |
| **I2C/I2S Node Status**  | Nodes may be **disabled** (`status = "disabled"`)                     | Ensure `status = "okay"` in DTS for `&i2s` and `&i2c1`.                               |
| **ALSA Routing**         | Gerätename may change (e.g., `seeed4micvoicec` → `card0`)            | Adapt `/etc/asound.conf` to match actual device name.                                  |

---

## **Build & Install Workflow**
### **1. DKMS Build (Recommended)**
```bash
sudo ./install.sh  # Auto-detects RPi 5, applies patches, compiles .ko + .dtbo
sudo reboot
```
- **Why DKMS?**: Survives kernel updates; applies version-specific patches from `patches/`.

### **2. Manual Build (Debugging)**
```bash
make clean
make DEBUG=1  # Enables AC108 debug logs (check `dmesg`)
sudo make install
sudo depmod -a && modprobe snd_soc_seeed_voicecard
```

### **3. Device Tree Overlay**
```bash
# Compile DTS → DTBO
dtc -I dts -O dtb -o seeed-4mic-voicecard-rpi5.dtbo seeed-4mic-voicecard-rpi5-overlay.dts

# Merge into RPi 5 DTB (avoids runtime overlay issues)
sudo fdtoverlay -i /boot/firmware/bcm2712-rpi-5-b.dtb -o /boot/firmware/bcm2712-rpi-5-b.dtb.merged seeed-4mic-voicecard-rpi5.dtbo
sudo cp /boot/firmware/bcm2712-rpi-5-b.dtb{.merged,}
sudo reboot
```

---
## **Device Tree Overlay (RPi 5)**
### **Current DTS (`seeed-4mic-voicecard-rpi5-overlay.dts`)**
```dts
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2712";

    fragment@0 {
        target = <&i2s>;  // RPi 5 I2S node
        __overlay__ {
            status = "okay";
        };
    };

    fragment@1 {
        target-path = "/";
        __overlay__ {
            ac108_mclk: codec-mclk {
                compatible = "fixed-clock";
                #clock-cells = <0>;
                clock-frequency = <24000000>;  // AC108 requires 24 MHz
            };
        };
    };

    fragment@2 {
        target = <&i2c1>;  // RPi 5 I2C node
        __overlay__ {
            #address-cells = <1>;
            #size-cells = <0>;
            status = "okay";

            ac108: ac108@3b {
                compatible = "x-power,ac108";
                reg = <0x3b>;
                #sound-dai-cells = <0>;
            };
        };
    };

    fragment@3 {
        target-path = "/";
        __overlay__ {
            sound {
                compatible = "simple-audio-card";
                simple-audio-card,name = "seeed-4mic-voicecard";
                simple-audio-card,format = "i2s";  // RPi 5 does NOT support DSP_A
                status = "okay";

                simple-audio-card,cpu {
                    sound-dai = <&i2s>;
                };

                simple-audio-card,codec {
                    sound-dai = <&ac108>;
                    clocks = <&ac108_mclk>;
                    clock-names = "mclk";
                };
            };
        };
    };
};
```

### **Key Notes**
- **`simple-audio-card,format = "i2s"`**: RPi 5’s `designware-i2s` **does not support `DSP_A`**.
- **`ac108_mclk`**: **24 MHz fixed clock** required for AC108.
- **Labels (`&i2s`, `&i2c1`)**: Use **symbolic references** (not full paths) to avoid DTC errors.

---
## **Testing & Debugging**
### **1. Verify Hardware**
```bash
# Check I2C (AC108 should appear at 0x3b)
i2cdetect -y 1

# Check ALSA devices
arecord -l  # Should list "seeed-4mic-voicecard"
```

### **2. Test Recording**
```bash
# Record 4 channels @ 16kHz
arecord -D hw:0,0 -f S16_LE -r 16000 -c 4 -d 5 test.wav

# Verify channels (non-zero samples)
sox test.wav -n stat
```

### **3. Debug Kernel Issues**
```bash
# Check for errors
dmesg | grep -E "ac108|i2s|sound|asoc"

# Check clock tree
cat /sys/kernel/debug/clk/clk_summary | grep -i i2s
```

---
## **Common Issues & Fixes**
| Issue                                  | Cause                                                                 | Fix                                                                                     |
|----------------------------------------|-----------------------------------------------------------------------|----------------------------------------------------------------------------------------|
| **`deferred probe pending`**           | Missing dependencies (e.g., I2C not ready)                          | Ensure `status = "okay"` for `&i2c1` and `&i2s` in DTS.                                |
| **`ASoC: error at snd_soc_dai_set_fmt`** | RPi 5 I2S rejects `DSP_A` format                                    | Use `simple-audio-card,format = "i2s"` in DTS.                                         |
| **No sound (zero samples)**            | Wrong ALSA device name or muted channels                            | Check `arecord -l`, set gains: `amixer -c 0 sset 'ADC1 PGA gain' 31`.                  |
| **I2C probe fails**                    | AC108 not detected at 0x3b                                           | Verify wiring, run `i2cdetect -y 1`.                                                   |
| **Clock issues (distorted audio)**    | MCLK not configured or wrong frequency                              | Define `ac108_mclk` in DTS with `clock-frequency = <24000000>`.                       |

---
## **Editing Checklist**
1. **Add new codec**: Create `newcodec.c`, register in `seeed-voicecard.c`, update `dkms.conf`.
2. **Fix clock issues**: Adjust PLL tables in `ac108.c` for sample rate compatibility.
3. **Port to new kernel**: Add patch in `patches/` for Kernel 6.x ASoC API changes.
4. **Update routing**: Edit DTS `simple-audio-card,routing`, recompile `.dtbo`.
5. **Debug silence**: Check `amixer` gains, test with `arecord`, analyze `sox test.wav -n stat`.

---
### **Final Notes**
- **RPi 5 Limitations**: No `DSP_A` support → Use `i2s` + software channel routing.
- **Always merge overlays into DTB** (avoids runtime overlay issues).
- **Check `dmesg` first** for errors like `deferred probe` or `DAI format`.

# Improvements Continue
- where possible improve diagnose_audio.sh and pre-reboot-checks.sh scripts to cover RPi 5 specifics and Kernel 6.x changes.