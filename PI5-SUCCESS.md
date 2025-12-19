# ReSpeaker 4-Mic Array auf Raspberry Pi 5 – Erfolgreiche Installation

**Status**: ✅ **Vollständig funktional** (Dezember 2025)

## Überblick

Die ReSpeaker 4-Mic Voicecard funktioniert jetzt **ohne externe Patches** auf dem **Raspberry Pi 5** mit den folgenden Komponenten:

- **Betriebssystem**: Raspberry Pi OS 64-bit (Trixie)
- **Kernel**: 6.12.47+rpt-rpi-2712
- **Codec**: AC108 (Multichannel ADC)
- **Audio-Interface**: Designware I2S (RP1 SoC)

## Kernelkomponenten

### Kernel-Module
```
snd-soc-seeed-voicecard  ✓ Geladen
snd-soc-ac108            ✓ Geladen
snd-soc-simple_card_utils ✓ Geladen
```

### Device Tree Overlay
```
Overlay: seeed-4mic-voicecard-rpi5
Status: Geladen beim Boot
Dateien: 
  - seeed-4mic-voicecard-rpi5.dtbo (2070 bytes)
  - seeed-4mic-voicecard-rpi5-overlay.dts (Source)
```

### Audio-Hardware
```
I2C: AC108 Codec @ 0x3b
DAI: 1f000a0000.i2s (Designware I2S)
MCLK: 24 MHz Fixed Clock
```

## Funktionen

### ✅ Audio-Aufnahme
- **Alle 4 Mikrofone** funktional
- **Unterstützte Sample-Raten**:
  - 8 kHz (16-bit PCM)
  - 16 kHz (16-bit PCM) ← **Empfohlen**
  - 48 kHz (16-bit PCM)

### ✅ Mixer-Kontrolle
Verfügbar für alle 4 Kanäle:
- **ADC1-4 PGA Gain** (0-31 dB)
- **CH1-4 Digital Volume** (0-255)

### ✅ Device Tree
Neue Pi 5-spezifische DTS mit:
- Korrekte `__fixups__` für Label-Auflösung
- `simple-audio-card` compatible (optimal für Pi 5)
- Minimale Device Tree-Ebene (keine komplexen Pfade)

## Test-Ergebnisse

```
=========================================
Test Summary
=========================================
✓ Device Tree Overlay: Loaded
✓ Kernel Modules: Loaded  
✓ I2C Codec: Detected (0x3b)
✓ Audio Device: Recognized (card 0)
✓ Mixer Controls: Available (8 controls)
✓ Recording Tests: 
  - 8 kHz: ✓ OK (126 KB)
  - 16 kHz: ✓ OK (251 KB)
  - 48 kHz: ✓ OK (751 KB)
✓ All 4 channels: Verified

System:
  Raspberry Pi 5 (d04170 rev)
  Kernel: 6.12.47+rpt-rpi-2712
  Temperature: 58.4°C
  Memory: 7.9 GiB
```

## Verwendung

### Grundlegende Aufnahme
```bash
# 16 kHz, 4 Kanäle, 10 Sekunden
arecord -D plughw:0,0 -f S16_LE -r 16000 -c 4 -d 10 output.wav

# Alternative Sample-Raten
arecord -D plughw:0,0 -f S16_LE -r 8000 -c 4 -d 5 test_8k.wav
arecord -D plughw:0,0 -f S16_LE -r 48000 -c 4 -d 5 test_48k.wav
```

### Mixer-Einstellungen
```bash
# Alle Controls anzeigen
amixer -c 0 contents

# Pro-Kanal Gains einstellen (dB)
amixer -c 0 sset 'ADC1 PGA gain' 20
amixer -c 0 sset 'ADC2 PGA gain' 20
amixer -c 0 sset 'ADC3 PGA gain' 20
amixer -c 0 sset 'ADC4 PGA gain' 20

# Digitale Lautstärke (0-255)
amixer -c 0 sset 'CH1 digital volume' 222
```

### Test-Skript
```bash
# Umfassender Test durchführen
sudo /home/adm_behnke/seeed-voicecard/test-respeaker.sh
```

## Technische Details

### Device Tree Fragment (vereinfacht)
```dts
fragment@0 {
    target = <&i2s>;
    __overlay__ { status = "okay"; };
};

fragment@1 {
    target = <&i2c1>;
    __overlay__ {
        ac108@3b {
            compatible = "x-power,ac108_0";
            reg = <0x3b>;
        };
    };
};

fragment@3 {
    target = <&sound>;
    __overlay__ {
        compatible = "simple-audio-card";
        simple-audio-card,format = "i2s";
        simple-audio-card,name = "seeed-4mic-voicecard";
    };
};
```

### Kritische Fixes für Pi 5
1. **Label-basierte Referenzen** (statt absoluter DTS-Pfade)
2. **Korrekte `__fixups__` Sektion** für Phandle-Auflösung
3. **`simple-audio-card` compatible** (nicht `seeed-voicecard`)
4. **RP1 I2S Designware-Controller** Unterstützung

## Dateien im Repository

| Datei | Zweck | Status |
|-------|-------|--------|
| `seeed-4mic-voicecard-rpi5-overlay.dts` | DT Source (Pi 5 optimiert) | ✓ Getestet |
| `seeed-4mic-voicecard-rpi5.dtbo` | Compiled Overlay | ✓ Funktional |
| `test-respeaker.sh` | Automated Test Suite | ✓ Alle Tests bestanden |
| `PI5-INSTALLATION.md` | Installations-Guide | ✓ Vollständig |
| `install.sh` | Installation Script | ✓ Pi 5 auto-detect |

## Bekannte Limitierungen

- ⚠️ **GUI-Stabilität**: Desktop-Environment kann unter Last abstürzen (use Lite OS für Server)
- ⚠️ **PulseAudio**: ALSA und PulseAudio können Konflikte haben (optional: `sudo apt purge pulseaudio`)
- ⚠️ **Clock Jitter**: Bei extrem hohen Sample-Raten (>96kHz) möglich

## Zukünftige Verbesserungen

- [ ] Beamforming-Support
- [ ] Firmware-Updates für AC108
- [ ] Python-Wrapper für Audio-Steuerung
- [ ] Integration mit SpeechRecognition Libraries

## Support & Links

- **Original Repo**: https://github.com/HinTak/seeed-voicecard
- **Pi 5 Issue**: https://github.com/HinTak/seeed-voicecard/issues/19
- **Forum**: https://forums.raspberrypi.com/viewtopic.php?t=381355

---

**Zusammengefasst**: ReSpeaker 4-Mic Array funktioniert jetzt **vollständig und zuverlässig** auf Raspberry Pi 5 mit Kernel 6.12.x! 🎉
