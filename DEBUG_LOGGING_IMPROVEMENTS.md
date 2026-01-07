# Debug-Logging Verbesserungen

Dieses Dokument beschreibt die vorgenommenen Verbesserungen an der Debug-Logging-Infrastruktur für den Seeed 4-Mic Array Treiber auf Raspberry Pi 5 (Kernel 6.x).

## Übersicht der Änderungen

Alle Änderungen wurden implementiert, um die Fehlerdiagnose zu vereinfachen und maschinenlesbare Logs für automatisierte Analysen bereitzustellen.

---

## 1. Kernel-Modul: seeed-voicecard.c

### 1.1 Startup-Funktion Logging
**Änderung**: Hinzufügen von Debug-Logs beim Start des PCM-Streams.

```c
pr_info("seeed-voicecard: %s: stream=%s\n", __func__, snd_pcm_stream_str(substream));
```

**Nutzen**: Zeigt an, wann ein Audio-Stream (Capture/Playback) gestartet wird.

### 1.2 Channel Override Logging
**Änderung**: Loggen der Kanal-Überschreibung.

```c
pr_info("seeed-voicecard: %s: Channel override - playback: %d->%d, capture: %d->%d\n",
    __func__, priv->channels_playback_default, priv->channels_playback_override,
    priv->channels_capture_default, priv->channels_capture_override);
```

**Nutzen**: Überwacht die Kanal-Konfiguration (wichtig für 4-Kanal-Setup).

### 1.3 TDM Slot Configuration Logging
**Änderung**: Erweiterte Logs für CPU und Codec DAI TDM-Konfiguration.

```c
pr_info("seeed-voicecard: %s: Configuring CPU DAI TDM slots\n", __func__);
dev_info(rtd->dev, "Setting CPU DAI TDM: slots=%d, width=%d, tx_mask=0x%x, rx_mask=0x%x\n",
    dai_props->cpu_dai.slots, dai_props->cpu_dai.slot_width,
    dai_props->cpu_dai.tx_slot_mask, dai_props->cpu_dai.rx_slot_mask);
```

**Nutzen**: 
- Zeigt TDM-Slot-Konfiguration (kritisch für Multi-Channel-Audio)
- Unterscheidet zwischen erfolgreicher Konfiguration und Fehlern
- Wichtig für RPi 5 I2S-Kompatibilitätsprüfung

### 1.4 MCLK/SYSCLK Configuration Logging
**Änderung**: Detaillierte Logs für Clock-Konfiguration.

```c
pr_info("seeed-voicecard: %s: Configuring MCLK: rate=%d Hz, mclk_fs=%d, mclk=%d Hz\n",
    __func__, params_rate(params), mclk_fs, mclk);
dev_info(rtd->dev, "Codec DAI sysclk configured: %d Hz (CLOCK_IN)\n", mclk);
dev_info(rtd->dev, "CPU DAI sysclk configured: %d Hz (CLOCK_OUT)\n", mclk);
```

**Nutzen**:
- Bestätigt, dass 24 MHz MCLK korrekt konfiguriert ist
- Zeigt Clock-Richtung (IN für Codec, OUT für CPU)
- Erleichtert Debugging von Clock-Problemen

### 1.5 Module Init/Exit Logging
**Änderung**: Logs beim Laden/Entladen des Moduls.

```c
static int __init seeed_voice_card_init(void) {
    pr_info("seeed-voicecard: Initializing SEEED Voice Card driver\n");
    return platform_driver_register(&seeed_voice_card);
}

static void __exit seeed_voice_card_exit(void) {
    pr_info("seeed-voicecard: Unloading SEEED Voice Card driver\n");
    platform_driver_unregister(&seeed_voice_card);
}
```

**Nutzen**: Bestätigt Modul-Lebenszyklus in `dmesg`.

---

## 2. Kernel-Modul: ac108.c

### 2.1 SYSCLK Configuration Logging
**Änderung**: Erweiterte Logs für System-Clock-Konfiguration.

```c
pr_info("ac108: %s: Setting sysclk - freq=%u Hz, clk_id=%d, dir=%d\n",
    __func__, freq, clk_id, dir);
pr_info("ac108: %s: Using PLL as sysclk source\n", __func__);
pr_info("ac108: %s: Sysclk configured successfully - freq=%u Hz, source=%d\n",
    __func__, ac10x->sysclk, ac10x->clk_id);
```

**Nutzen**:
- Zeigt, ob MCLK oder PLL verwendet wird
- Bestätigt 24 MHz Sysclk
- Hilfreich bei PLL-Konfigurationsproblemen

### 2.2 Hardware Parameters Logging
**Änderung**: Detaillierte Logs für Sample-Rate, Format und Kanäle.

```c
pr_info("ac108: %s: Configuring hardware parameters\n", __func__);
pr_info("ac108: %s: rate=%d, channels=%d, format=%d\n",
    __func__, params_rate(params), params_channels(params), params_format(params));
pr_info("ac108: %s: Sample resolution configured: samp_res=%d (%d-bit)\n",
    __func__, samp_res, ac108_samp_res[samp_res].real_val);
pr_info("ac108: %s: Sample rate configured: rate_idx=%d (%d Hz)\n",
    __func__, rate, ac108_sample_rate[rate].real_val);
```

**Nutzen**:
- Bestätigt S32_LE Format (32-bit)
- Zeigt 16000 Hz Sample-Rate
- Bestätigt 4-Kanal-Konfiguration

---

## 3. Diagnose-Skript: diagnose_audio_2.sh

### 3.1 Kernel Module & Device Tree Check
**Neue Sektion**: Schritt 0 - Kernel-Module und Device Tree prüfen.

```bash
module_duration=$(step_timer "Kernel-Module und Device Tree prüfen" "
  {
    echo '[Kernel Modules]'
    lsmod | grep -E '(snd_soc_ac108|snd_soc_seeed_voicecard|snd_soc)'
    echo '[Module Info]'
    modinfo snd_soc_ac108
    echo '[Device Tree]'
    sudo dtoverlay -l
    echo '[dmesg - seeed/ac108/i2s]'
    dmesg | grep -Ei 'seeed|ac108|i2s' | tail -100
  } > '$LOG_DIR/0_kernel_modules.log'
")
```

**Nutzen**:
- Bestätigt, dass Module geladen sind
- Zeigt Device Tree Overlays
- Filtert relevante Kernel-Logs

### 3.2 I2S & Clock Configuration Check
**Neue Sektion**: Schritt 6a - I2S und Clock-Konfiguration.

```bash
i2s_clock_duration=$(step_timer "I2S und Clock-Konfiguration prüfen" "
  {
    echo '[Clock Tree]'
    cat /sys/kernel/debug/clk/clk_summary | grep -i i2s
    echo '[I2S Status]'
    sudo find /sys/kernel/debug/asoc/ -name 'state' | while read -r f; do
      echo '---' $f '---'
      sudo cat $f
    done
  } > '$LOG_DIR/6a_i2s_clock.log'
")
```

**Nutzen**:
- Zeigt I2S-Clock-Status
- Bestätigt Clock-Quellen
- Hilfreich bei Clock-Timing-Problemen

### 3.3 Enhanced I2C Dump
**Erweiterung**: I2C-Detection vor Register-Dump.

```bash
echo '--- I2C Detection ---'
i2cdetect -y 1 2>/dev/null
echo '--- I2C Register Dump (AC108 @ 0x3b) ---'
sudo i2cdump -y 1 0x3b
```

**Nutzen**: Zeigt I2C-Bus-Status vor Register-Dump.

---

## 4. Early Boot Skript: early_boot_capture.sh

### 4.1 Kernel Version & Module Status
**Neue Sektion**: Kernel-Version und geladene Module.

```bash
echo "=== kernel version ==="
uname -r

echo "=== loaded kernel modules (ac108/seeed) ==="
lsmod | grep -E "(ac108|seeed)" || echo "no ac108/seeed modules loaded"

echo "=== device tree overlays ==="
sudo dtoverlay -l 2>/dev/null || echo "dtoverlay command not available"
```

**Nutzen**: Bestätigt Kernel-Version und Modul-Status beim Boot.

### 4.2 I2C Device Detection
**Erweiterung**: Explizite AC108-Erkennung.

```bash
echo "=== I2C device check (AC108 @ 0x3b) ==="
if i2cdetect -y 1 2>/dev/null | grep -qE "3b|UU"; then
  echo "AC108 detected on I2C bus (0x3b)"
else
  echo "WARNING: AC108 NOT detected on I2C bus"
fi
```

**Nutzen**: Frühe Erkennung von I2C-Verbindungsproblemen.

### 4.3 Clock Configuration Check
**Neue Sektion**: Clock-Konfiguration prüfen.

```bash
echo "=== clock configuration ==="
if [ -f /sys/kernel/debug/clk/clk_summary ]; then
  sudo cat /sys/kernel/debug/clk/clk_summary | grep -i i2s
else
  echo "clk_summary not available"
fi
```

**Nutzen**: Zeigt Clock-Setup beim Boot.

### 4.4 DAI Formats & TDM Check
**Neue Sektion**: DAI-Format-Überprüfung.

```bash
echo "=== DAI formats (TDM check) ==="
sudo find /sys/kernel/debug/asoc/ -name formats 2>/dev/null | while read -r f; do
  echo "--- $f ---"
  sudo cat "$f"
done
```

**Nutzen**: Bestätigt I2S-Format (nicht DSP_A) auf RPi 5.

### 4.5 Hardware Parameters Dump
**Erweiterung**: Hardware-Parameter vor Aufnahme.

```bash
echo "--- Hardware parameters check ---"
timeout 2 arecord -D hw:0,0 --dump-hw-params -f S32_LE -r 16000 -c 4 /dev/null 2>&1
echo "--- Recording test ---"
timeout 2 arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 "$LOG_DIR/early_boot_${TS}.wav" 2>&1
```

**Nutzen**: Zeigt unterstützte Hardware-Parameter (Format, Rate, Channels).

---

## 5. Maschinenlesbare JSON-Ausgabe

Beide Skripte (`diagnose_audio_2.sh` und `early_boot_capture.sh`) generieren JSON-Status-Dateien:

### 5.1 JSON-Struktur
```json
{
  "status": "error",
  "error_code": -3,
  "key_metrics": {
    "device_detected": true,
    "i2c_status": "in_use",
    "alsa_controls": 4,
    "recording_max_level": "0.000000"
  },
  "root_cause": "capture silent (max level 0)",
  "required_actions": [
    "amixer -c 0 sset \"ADC1 PGA gain\" 31",
    "timeout 3 arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 /tmp/test.wav",
    "dmesg | grep -i ac108"
  ]
}
```

### 5.2 Status-Codes
- **0**: Erfolg
- **-1**: ALSA-Karte nicht erkannt
- **-2**: AC108-Mixer-Controls fehlen
- **-3**: Aufnahme stumm (Max-Level = 0)

### 5.3 Verwendung
```bash
# Skript ausführen
sudo ./diagnose_audio_2.sh

# JSON-Status lesen
jq . logs/ac108_debug_*/status.json

# Automatisierte Auswertung
status=$(jq -r '.status' logs/ac108_debug_*/status.json)
if [ "$status" = "error" ]; then
  jq -r '.required_actions[]' logs/ac108_debug_*/status.json
fi
```

---

## 6. Log-Dateien Übersicht

### diagnose_audio_2.sh Logs
```
logs/ac108_debug_YYYYMMDD_HHMMSS/
├── 0_kernel_modules.log       # Kernel-Module und Device Tree
├── 1_dai_formats.log          # DAI-Formate (I2S, DSP_A, etc.)
├── 2_dapm.log                 # DAPM-Widgets und Routen
├── 3_tdm_logs.log             # TDM/Slot Kernel-Logs
├── 4_hwparams.log             # ALSA Hardware-Parameter
├── 5_mixer.log                # Mixer-Controls
├── 6_i2c_dump.log             # I2C-Register-Dump
├── 6a_i2s_clock.log           # I2S und Clock-Konfiguration
├── 7_alsa_status.log          # ALSA-Status und Testaufnahme
├── test_recording.wav         # Testaufnahme (3 Sekunden)
└── status.json                # Maschinenlesbarer Status
```

### early_boot_capture.sh Logs
```
logs/
├── early_boot_YYYYMMDD_HHMMSS.log       # Vollständige Boot-Diagnose
├── early_boot_YYYYMMDD_HHMMSS.wav       # Boot-Testaufnahme (1 Sekunde)
└── early_boot_YYYYMMDD_HHMMSS.json      # Maschinenlesbarer Status
```

---

## 7. Verwendung der Debug-Logs

### 7.1 Nach Installation/Update
```bash
# Vollständige Diagnose ausführen
sudo ./diagnose_audio_2.sh

# Status prüfen
cat logs/ac108_debug_*/status.json | jq .
```

### 7.2 Nach Reboot
```bash
# Early Boot Capture ausführen (automatisch via systemd oder manuell)
sudo ./early_boot_capture.sh

# Boot-Status prüfen
cat logs/early_boot_*.json | jq .
```

### 7.3 Bei Problemen
```bash
# 1. Kernel-Logs prüfen
dmesg | grep -Ei "seeed|ac108|i2s|asoc"

# 2. TDM-Konfiguration prüfen
cat logs/ac108_debug_*/3_tdm_logs.log

# 3. I2C-Verbindung prüfen
cat logs/ac108_debug_*/6_i2c_dump.log

# 4. ALSA Hardware-Parameter prüfen
cat logs/ac108_debug_*/4_hwparams.log
```

---

## 8. Debug-Logging aktivieren

### 8.1 Kernel-Modul Debug-Level
```bash
# Debug-Logs aktivieren (beim Kompilieren)
make DEBUG=1

# Oder runtime (wenn unterstützt)
echo 8 > /proc/sys/kernel/printk
```

### 8.2 ALSA Debug-Logs
```bash
# ALSA Debug-Level erhöhen
echo 1 > /sys/module/snd/parameters/debug
```

### 8.3 Kernel Dynamic Debug
```bash
# AC108-spezifische Debug-Logs aktivieren
echo 'file ac108.c +p' > /sys/kernel/debug/dynamic_debug/control
echo 'file seeed-voicecard.c +p' > /sys/kernel/debug/dynamic_debug/control
```

---

## 9. Zusammenfassung der Verbesserungen

| Komponente              | Verbesserung                                     | Nutzen                                          |
|-------------------------|--------------------------------------------------|-------------------------------------------------|
| **seeed-voicecard.c**   | TDM/MCLK/Channel-Override-Logs                   | Echtzeit-Debugging von Audio-Konfiguration     |
| **ac108.c**             | SYSCLK/HW-Params/Sample-Rate-Logs                | Codec-Konfiguration nachvollziehbar             |
| **diagnose_audio_2.sh** | Kernel-Module/I2S-Clock/I2C-Checks               | Umfassende Post-Installation-Diagnose           |
| **early_boot_capture.sh**| Boot-Logs/DAI-Formats/Clock-Checks              | Frühe Erkennung von Boot-Zeit-Problemen         |
| **JSON-Status**         | Maschinenlesbare Fehleranalyse                   | Automatisierte Diagnose und Fehlerbehebung      |

---

## 10. Nächste Schritte

### Nach den Änderungen:
1. **Kernel-Module neu kompilieren**:
   ```bash
   make clean
   make DEBUG=1
   sudo make install
   sudo modprobe -r snd_soc_seeed_voicecard snd_soc_ac108
   sudo modprobe snd_soc_ac108
   sudo modprobe snd_soc_seeed_voicecard
   ```

2. **Diagnose ausführen**:
   ```bash
   sudo ./diagnose_audio_2.sh
   ```

3. **Logs analysieren**:
   ```bash
   dmesg | grep -Ei "seeed|ac108" | tail -100
   cat logs/ac108_debug_*/status.json | jq .
   ```

4. **Bei Fehlern**:
   ```bash
   # JSON-Actions ausführen
   jq -r '.required_actions[]' logs/ac108_debug_*/status.json | bash
   ```

---

## 11. Fehlerbehandlung

### Problem: Kernel-Logs fehlen
**Lösung**:
```bash
# printk-Level erhöhen
echo 7 > /proc/sys/kernel/printk
```

### Problem: I2C-Register nicht lesbar
**Lösung**:
```bash
# I2C-Bus-Status prüfen
i2cdetect -y 1
# Falls "UU" bei 0x3b: I2C-Bus wird bereits verwendet (OK)
# Falls "--" bei 0x3b: Hardware-Problem oder falscher I2C-Bus
```

### Problem: TDM-Slots werden nicht gesetzt
**Lösung**:
```bash
# DTS prüfen
sudo dtc -I fs /proc/device-tree > /tmp/device-tree.dts
grep -A20 "ac108" /tmp/device-tree.dts
```

---

**Erstellt**: 23. Dezember 2025  
**Version**: 1.0  
**Autor**: GitHub Copilot (Claude Sonnet 4.5)
