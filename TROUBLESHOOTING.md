# 🔧 ReSpeaker Audio Troubleshooting Guide

## Problem: Keine Audioaufnahme (Stille trotz korrekter Mixer-Einstellungen)

### Häufigste Ursache: Device Tree Overlay nicht geladen

Das Device Tree Overlay konfiguriert die Hardware-Verbindungen zwischen Raspberry Pi und AC108 Codec. Ohne geladenes Overlay kann der Codec keine Daten übertragen.

### ✅ Schnelle Lösung

```bash
# 1. Überprüfen ob Overlay in config.txt eingetragen ist
cat /boot/firmware/config.txt | grep seeed

# Erwartete Ausgabe (für 4-mic ReSpeaker auf Pi 5):
# dtoverlay=seeed-4mic-voicecard-rpi5

# 2. Neustart erforderlich um Overlay zu laden
sudo reboot
```

### 🔍 Diagnostics durchführen

```bash
# Umfassendes Diagnose-Script ausführen
cd /home/adm_behnke/seeed-voicecard
./diagnose_audio.sh

# Manuelle Checks:
# - Ist das Overlay geladen?
dtoverlay -l | grep seeed

# - Sind die Kernel-Module geladen?
lsmod | grep ac108

# - Sind die Mixer-Gains gesetzt?
amixer -c 0 sget "ADC1 PGA gain"
```

### 🎯 Schritt-für-Schritt Fehlerbehebung

#### 1. Overlay nicht geladen (häufigstes Problem)
```bash
# Symptom: dtoverlay -l zeigt kein "seeed"
# Lösung: Neustart
sudo reboot

# Nach Neustart prüfen:
dtoverlay -l | grep seeed
# Sollte zeigen: "3: seeed-4mic-voicecard-rpi5"
```

#### 2. Mixer-Gains zu niedrig
```bash
# Symptom: Sehr schwaches Signal
# Lösung: Gains auf 90% setzen
for i in 1 2 3 4; do 
    sudo amixer -c 0 sset "ADC${i} PGA gain" 28
done

# Prüfen:
for i in 1 2 3 4; do 
    amixer -c 0 sget "ADC${i} PGA gain"
done
```

#### 3. I2C-Kommunikationsfehler
```bash
# Symptom: dmesg zeigt "lost arbitration" oder I2C errors
# Kernel-Logs prüfen:
dmesg | grep -i "ac108\|i2c" | tail -20

# Lösung: Module neu laden
sudo modprobe -r snd_soc_ac108
sudo modprobe -r snd_soc_seeed_voicecard
sudo modprobe snd_soc_seeed_voicecard
```

#### 4. Falsches Overlay für Pi-Modell
```bash
# Pi 5 benötigt spezielles Overlay!
# In /boot/firmware/config.txt:

# Für Pi 5:
dtoverlay=seeed-4mic-voicecard-rpi5

# Für Pi 4 und älter:
dtoverlay=seeed-4mic-voicecard

# Nach Änderung: sudo reboot
```

#### 5. Hardware-Test
```bash
# Einfacher Aufnahmetest
arecord -D plughw:0,0 -f S32_LE -r 16000 -c 4 -d 3 test.wav

# Signal-Analyse
python3 -c "
import wave, struct
w = wave.open('test.wav', 'rb')
frames = w.readframes(5000)
samples = struct.unpack('<i' * (len(frames)//4), frames)
print(f'Signal Range: {max(samples) - min(samples)}')
print('✅ OK' if max(samples) - min(samples) > 1000 else '❌ SILENT')
"
```

### 📋 Checkliste für erfolgreiche Audio-Aufnahme

- [ ] Device Tree Overlay in config.txt eingetragen
- [ ] System nach Overlay-Änderung neu gestartet
- [ ] `dtoverlay -l` zeigt "seeed-*mic-voicecard"
- [ ] `lsmod | grep ac108` zeigt geladene Module
- [ ] `arecord -l` zeigt "seeed-4mic-voicecard"
- [ ] Mixer-Gains auf 28/31 (90%) gesetzt
- [ ] I2C-Bus zeigt Codec (i2cdetect -y 1 → "UU" bei 0x3b)
- [ ] Test-Aufnahme enthält Signal (Range > 100000)

### 🔊 Erwartete Werte bei funktionierender Hardware

```
# Mixer Gains (optimal)
ADC1-4 PGA gain: 28/31 (90%)

# Test-Aufnahme Signal-Range
- Stille/Rauschen: < 1000 (❌ Problem)
- Sehr leise Sprache: 1000-100000 (⚠️ Gain erhöhen)
- Normale Sprache: > 100000 (✅ OK)
- Laute Sprache: > 1000000 (✅ Ausgezeichnet)

# Dateigrößen (16kHz, 32-bit, 4 Kanäle)
- 1 Sekunde: ~256 KB
- 5 Sekunden: ~1.25 MB
- 10 Sekunden: ~2.5 MB
```

### 🚨 Wenn nichts funktioniert

1. **Vollständige Neuinstallation**
```bash
cd /home/adm_behnke/seeed-voicecard
sudo ./uninstall.sh
sudo reboot
sudo ./install.sh
sudo reboot
```

2. **Hardware-Test**
- Mikrofonkabel fest eingesteckt?
- LED auf ReSpeaker-Board leuchtet?
- Andere GPIO-Hats entfernen (Konflikt möglich)

3. **Log-Dateien sammeln**
```bash
# Für Support-Anfrage
dmesg | grep -iE "(ac108|seeed|i2c)" > audio_debug.log
amixer -c 0 contents >> audio_debug.log
dtoverlay -l >> audio_debug.log
lsmod | grep snd >> audio_debug.log
```

### 📚 Weitere Ressourcen

- [seeed-voicecard GitHub](https://github.com/HinTak/seeed-voicecard)
- [PI5-INSTALLATION.md](PI5-INSTALLATION.md) - Spezifische Hinweise für Raspberry Pi 5
- [AC108 Codec Dokumentation](ac108.c) - Treiber-Code mit Details zur Konfiguration
