# ReSpeaker 4-Mic Array auf Raspberry Pi 5 – Installations- & Betriebsanleitung

## ✅ Status: Funktional auf Raspberry Pi 5 (Dezember 2025)

Die ReSpeaker 4-Mic Voicecard funktioniert jetzt **vollständig auf Raspberry Pi 5** mit Kernel 6.12.x dank eines überarbeiteten Device Tree Overlays.

---

## Hardware-Anforderungen

- **Raspberry Pi 5** (BCM2712)
- **ReSpeaker 4-Mic Array** (AC108 codec)
- **Kernel 6.12.x** oder später
- **64-bit Raspberry Pi OS** empfohlen

---

## Schnelle Installation

```bash
# 1. Repository klonen (v6.12 Branch für Pi 5)
cd ~
git clone -b v6.12 https://github.com/HinTak/seeed-voicecard.git
cd seeed-voicecard

# 2. Installation
sudo ./install.sh

# 3. Reboot erforderlich!
sudo reboot

# 4. Nach Reboot testen
arecord -l                                                    # Geräte auflisten
arecord -D plughw:0,0 -f S16_LE -r 16000 -c 4 -d 5 test.wav # 5 Sekunden aufnehmen
```

---

## Spezifische Pi 5 Änderungen

### 1. Device Tree Overlay (`seeed-4mic-voicecard-rpi5.dtbo`)

Der Overlay wurde speziell für Pi 5 angepasst:
- Nutzt `&i2s`, `&i2c1`, `&sound` Labels (statt absoluter Pfade)
- Korrekte `__fixups__` und `__local_fixups__` Sektion
- Kompatibel mit `simple-audio-card` (nicht `seeed-voicecard` compatible)

**Boot-Konfiguration** (`/boot/firmware/config.txt`):
```ini
dtoverlay=seeed-4mic-voicecard-rpi5
```

### 2. Kernel-Module

Auto-geladen nach Installation:
```bash
# Prüfen:
lsmod | grep seeed
# Ausgabe:
# snd_soc_seeed_voicecard    49152  1
# snd_soc_ac108              ...
# snd_soc_simple_card_utils  ...
```

### 3. Audio-Geräte nach Installation

```bash
$ arecord -l
**** List of CAPTURE Hardware Devices ****
card 0: seeed4micvoicec [seeed-4mic-voicecard], device 0: 1f000a0000.i2s-ac10x-codec0 ac10x-codec0-0
```

---

## Unterstützte Sample-Raten & Formate

| Sample-Rate | Kanäle | Format | Getestet |
|-------------|--------|--------|----------|
| 8 kHz       | 4      | S16_LE | ✓ OK     |
| 16 kHz      | 4      | S16_LE | ✓ OK     |
| 48 kHz      | 4      | S16_LE | ✓ OK     |

---

## Praktische Audio-Kommandos

### Aufnahme (alle 4 Kanäle)
```bash
# Standard 16kHz
arecord -D plughw:0,0 -f S16_LE -r 16000 -c 4 -d 10 output.wav

# Verschiedene Sample-Raten:
arecord -D plughw:0,0 -f S16_LE -r 8000 -c 4 -d 5 test_8k.wav
arecord -D plughw:0,0 -f S16_LE -r 48000 -c 4 -d 5 test_48k.wav
```

### Mixer-Kontrolle (pro Mikrofon)
```bash
# Alle Mixer-Controls anzeigen:
amixer -c 0 contents

# ADC Gain pro Kanal anpassen (0-31 dB):
amixer -c 0 sset 'ADC1 PGA gain' 20
amixer -c 0 sset 'ADC2 PGA gain' 20
amixer -c 0 sset 'ADC3 PGA gain' 20
amixer -c 0 sset 'ADC4 PGA gain' 20

# Digitale Lautstärke pro Kanal (0-255):
amixer -c 0 sset 'CH1 digital volume' 222
```

### Overlay-Status prüfen
```bash
# Geladene Overlays
dtoverlay -l | grep seeed

# Manuell laden (für Debugging)
sudo dtoverlay seeed-4mic-voicecard-rpi5

# Entfernen
sudo dtoverlay -r seeed-4mic-voicecard-rpi5
```

---

## Troubleshooting

### Problem: "arecord: main:850: audio open error: No such file or directory"

**Ursache**: Overlay ist nicht geladen.

**Lösung**:
```bash
# 1. Prüfen ob overlay geladen ist
dtoverlay -l | grep seeed

# 2. Falls nicht: manuell laden
sudo dtoverlay seeed-4mic-voicecard-rpi5

# 3. Falls weiterhin Fehler: Reboot
sudo reboot

# 4. Nach Reboot erneut prüfen
dtoverlay -l | grep seeed
```

### Problem: AC108 wird auf I2C nicht erkannt

**Ursache**: I2C-Bus ist nicht konfiguriert.

**Lösung**:
```bash
# I2C-Geräte scannen
i2cdetect -y 1

# Sollte AC108 bei 0x3b zeigen. Falls nicht:
# 1. /boot/firmware/config.txt prüfen: dtparam=i2c_arm=on
# 2. Reboot
```

### Problem: Kernel-Modul lädt nicht

**Ursache**: DKMS Build-Fehler für Ihre Kernel-Version.

**Lösung**:
```bash
# Verfügbare DKMS Module prüfen
dkms status

# Logs prüfen
dmesg | grep -i "seeed\|ac108"

# Falls nötig: Neu-Installation
sudo ./uninstall.sh
sudo ./install.sh
```

---

## Kernel-kompatibilität

| Kernel-Version | Pi 5 Branch | Status   |
|----------------|-------------|----------|
| 6.12.x         | v6.12       | ✓ Getestet |
| 6.6.x          | v6.6        | ✓ Funktional |
| 6.5.x          | v6.5        | ⚠ Ältere Patches |
| <6.5           | v4.19/v5.4  | ✗ Nicht unterstützt |

**Kernel-Version prüfen:**
```bash
uname -r
```

**Kernel aktualisieren:**
```bash
sudo apt update && sudo apt upgrade
sudo rpi-update  # Für Beta-Kernel
```

---

## Wichtige Dateien

| Datei | Zweck |
|-------|-------|
| `seeed-4mic-voicecard-rpi5-overlay.dts` | Device Tree Source (Pi 5) |
| `seeed-4mic-voicecard-rpi5.dtbo` | Compiled Device Tree Overlay |
| `seeed-voicecard.c` | Machine Driver (ALSA) |
| `ac108.c` | AC108 Codec Driver |
| `/boot/firmware/config.txt` | Boot-Konfiguration |

---

## Nächste Schritte (optional)

1. **Integration in Python-Audio-Projekt**:
   ```python
   import pyaudio
   import wave
   
   # Hardware-ID: 0 (seeed-4mic-voicecard)
   # Format: pyaudio.paInt16 (S16_LE)
   # Channels: 4
   # Rate: 16000
   ```

2. **PulseAudio-Konfiguration** (falls needed):
   - Siehe `/etc/pulseaudio/` für Microphone Array Routing

3. **Beamforming / Multi-Mic Processing**:
   - Siehe `tools/coherence.py` für Phasenkohärenz-Analyse

---

## Community & Support

- **GitHub**: [HinTak/seeed-voicecard](https://github.com/HinTak/seeed-voicecard)
- **Issue Tracking**: [Pi 5 Support #19](https://github.com/HinTak/seeed-voicecard/issues/19)
- **Raspberry Pi Forum**: [Pi 5 ReSpeaker Discussion](https://forums.raspberrypi.com/viewtopic.php?t=381355)

---

## Changelog für Pi 5 Support

**v0.3 (Dezember 2025)**
- ✅ Device Tree Overlay für Pi 5 angepasst
- ✅ Simple-audio-card Konfiguration (statt seeed-voicecard compatible)
- ✅ __fixups__ Sektion korrigiert für Pi 5 Labels
- ✅ Auto-Erkennung in install.sh (Pi 4 vs Pi 5)
- ✅ Getestet: 8kHz, 16kHz, 48kHz Aufnahme
- ✅ Mixer-Kontrolle für alle 4 Kanäle funktional
