# ReSpeaker 4-Mic Array auf Raspberry Pi 5 - Lösungswege

## Problem-Zusammenfassung
**Fehler**: `designware-i2s 1f000a0000.i2s: ASoC: error at snd_soc_dai_hw_params: -22 (EINVAL)`

**Ursache**: RP1 designware-i2s Controller lehnt 4-Kanal-Konfiguration ab.

---

## Lösungsweg A: 2-Kanal-Workaround (FUNKTIONIERT TEILWEISE)
**Status**: ✅ Constraint funktioniert, ❌ hw_params wird noch abgelehnt  
**Dateien**: `seeed-voicecard.c` (mit `RP5_2CH_WORKAROUND`)

### Was funktioniert:
- Channel-Constraint auf 2 limitiert ALSA-Ebene
- `arecord --dump-hw-params` zeigt korrekt 2 Kanäle

### Was nicht funktioniert:
- designware-i2s lehnt trotzdem hw_params ab (-22)
- Vermutlich BCLK-Ratio oder Timing-Problem

### Nächste Schritte:
1. BCLK-Ratio explizit für 2ch setzen
2. Format auf S16_LE statt S32_LE testen
3. Eventuell Slots auf 0 für reines I2S ohne TDM

### Aktivierung:
```bash
make CFLAGS="-DRP5_2CH_WORKAROUND" -j4
```

---

## Lösungsweg B: TDM-Slot-Programmierung (GETESTET, FEHLGESCHLAGEN)
**Status**: ❌ Funktioniert nicht  
**Commit**: 2026-01-02 (vor Rollback)

### Getestet:
- Explizite `snd_soc_dai_set_tdm_slot()` Aufrufe für CPU+Codec
- `snd_soc_dai_set_bclk_ratio()` für 128 (4×32)
- Slots=4, slot_width=32, mask=0xf

### Ergebnis:
- Seeed-voicecard hw_params: SUCCESS
- designware-i2s hw_params: -22 (EINVAL)

### Warum gescheitert:
RP1 designware-i2s akzeptiert keine TDM-Konfiguration, auch nicht als "Fake-TDM" für I2S.

---

## Lösungsweg C: DAI-Format-Overrides (GETESTET, TEILWEISE)
**Status**: ⚠️ Teilweise funktionierend  
**Dateien**: `seeed-voicecard.c` (Lines 554-569)

### Getestet:
```c
dai_link->dai_fmt = SND_SOC_DAIFMT_I2S | SND_SOC_DAIFMT_NB_NF | SND_SOC_DAIFMT_CBS_CFS;
```

### Ergebnis:
- Format wird korrekt gesetzt (0x4001 = I2S + NB_NF + CBS_CFS)
- AC108 akzeptiert Slave-Modus
- designware-i2s lehnt trotzdem ab (Channel-Problem)

---

## Lösungsweg D: AC108 Register-Tweaks (FUNKTIONIERT FÜR AC108)
**Status**: ✅ AC108 korrekt konfiguriert  
**Dateien**: `ac108.c` (MCLK-Modus, Startup, hw_params)

### Erfolgreich implementiert:
1. **MCLK-Direkt-Modus** statt PLL:
   - `SYSCLK_CTRL = 0x01` (nur SYSCLK_EN, kein PLL)
   - Verwendet 24MHz MCLK direkt
   
2. **I2S_CTRL korrekt**:
   - `0xF5` = TXEN + SDO1_EN + BCLK_IOEN + LRCK_IOEN
   
3. **Channel-Mapping**:
   - TX1 Kanäle 1-4 aktiviert (0x0F)
   - Mapping 0xE4 korrekt

### Problem:
AC108 läuft perfekt, aber **CPU-DAI (designware-i2s) lehnt ab**.

---

## Lösungsweg E: Device-Tree-Optimierungen (GETESTET)
**Status**: ✅ DT korrekt, Problem liegt woanders  
**Dateien**: `seeed-4mic-voicecard-rpi5-overlay.dts`

### Erfolgreich:
- `simple-audio-card,format = "i2s"`
- Clock-Provider: CPU (CBS_CFS)
- MCLK 24MHz fixed-clock definiert
- I2C + I2S Status = "okay"

### Verifiziert:
- `i2cdetect`: AC108 @ 0x3b (UU = driver owns)
- `/sys/kernel/debug/clk`: clk_i2s läuft (50MHz)
- Pinmux: i2s0 korrekt

---

## Lösungsweg F: RP1 Kernel-Patch (NICHT GETESTET)
**Status**: ⚠️ Erfordert Kernel-Neubau  
**Dateien**: Noch nicht implementiert

### Idee:
Patch für `sound/soc/dwc/designware-i2s.c`:
```c
// Erlaube 4 Kanäle im I2S-Modus für RP1
if (channels > 2 && config->chan_wl_override) {
    // Nutze 32-bit slots für 4 Kanäle
    dw_i2s_config_multi_channel(dev, channels);
}
```

### Risiko:
- Kernel-Build erforderlich
- Ungetestet, ob Hardware es unterstützt

---

## Lösungsweg G: ALSA-Plugin für Channel-Downmix (NOCH NICHT GETESTET)
**Status**: 🔵 Nächster praktikabler Schritt  
**Dateien**: `ac108_plugin/` (bereits vorhanden, aber nicht für RP5)

### Konzept:
1. Hardware: Capture 2 Kanäle (Mic 1+2)
2. ALSA Plugin: Dupliziert auf 4 virtuelle Kanäle
3. Anwendung: Sieht 4 Kanäle

### Vorteile:
- Keine Kernel-Änderungen
- Funktioniert garantiert (wenn 2ch läuft)

### Nachteil:
- Nur 2 echte Mikrofone nutzbar

---

## Lösungsweg H: Device Tree TDM-Slot-Konfiguration (HOHE PRIORITÄT)
**Status**: 🔵 NÄCHSTER TEST  
**Dateien**: `seeed-4mic-voicecard-rpi5-overlay.dts`

### Konzept:
RP1 I2S könnte TDM unterstützen, wenn explizit im Device Tree konfiguriert:

```dts
simple-audio-card,cpu {
    sound-dai = <&i2s>;
    dai-tdm-slot-num = <4>;        // 4 Slots statt 2
    dai-tdm-slot-width = <32>;     // 32-bit pro Slot
    dai-tdm-slot-tx-mask = <1 1 1 1>;
    dai-tdm-slot-rx-mask = <1 1 1 1>;
};
```

### Warum vielversprechend:
- Bisherige Overlays setzen keine expliziten TDM-Slots
- RP1 könnte TDM unterstützen, aber nicht auto-detektieren
- Designware I2S hat TDM-Capabilities

### Test-Schritte:
1. DTS erweitern mit TDM-Slot-Properties
2. `.dtbo` neu kompilieren
3. Overlay laden und testen
4. `arecord -D hw:0,0 -c4` versuchen

### Risiko: Niedrig
Hardware wird nicht beschädigt, nur Device Tree.

---

## Lösungsweg I: AC108 Encoding Mode (ELEGANT)
**Status**: 🔵 Erfolgversprechend  
**Dateien**: `ac108.c` (Register 0x30: I2S_CTRL)

### Konzept:
AC108 hat **ENCD_SEL** Modus (Bit im I2S_CTRL):
- 4 Kanäle werden als 2 Kanäle mit **Channel-Tags** encodiert
- Hardware sendet 2×32-bit statt 4×16-bit
- Software dekodiert Tags zurück zu 4 separaten Kanälen

### Register-Änderung:
```c
// In ac108_set_fmt():
snd_soc_component_update_bits(component, I2S_CTRL, 
                                ENCD_SEL_MASK, ENCD_SEL_ENABLE);
```

### Vorteile:
- RP1 sieht nur 2 Kanäle (akzeptiert hw_params)
- Alle 4 Mics aktiv
- Userspace-Dekodierung via ALSA-Plugin

### Nachteil:
- Userspace-Dekodierung nötig
- Performance-Overhead

---

## Lösungsweg J: BCLK/LRCK Ratio Trick (EXPERIMENTELL)
**Status**: ⚠️ Fortgeschritten  
**Dateien**: `seeed-voicecard.c`, `ac108.c`

### Konzept:
4 Kanäle in 2-Kanal-Frame packen:
- BCLK = 64 × Sample Rate (statt 32)
- LRCK = Sample Rate (normal)
- Jeder "Stereo"-Frame enthält 2×32-bit = 64-bit = 4×16-bit Daten

### Implementierung:
```c
// In seeed_voice_card_hw_params():
if (params_channels(params) == 4) {
    // Fake 2 channels für RP1
    snd_soc_dai_set_bclk_ratio(cpu_dai, 64);
    
    // AC108 sendet 4ch in 2ch-Frame
    ac108_configure_packed_mode(codec_dai);
}
```

### Risiko: Mittel
Timing muss exakt stimmen, sonst Datenverlust.

---

## Lösungsweg K: Multi-SDO Routing (HARDWARE-NAH)
**Status**: 🔵 Hardware-Check nötig  
**Dateien**: DTS + AC108 Init

### Konzept:
AC108 hat **SDO1** und **SDO2** Ausgänge:
- SDO1: Kanal 1+2 (Stereo)
- SDO2: Kanal 3+4 (Stereo)
- RP1 nutzt 2 separate I2S-Interfaces

### Voraussetzung:
RP1 muss 2 I2S-Interfaces unterstützen (prüfen in `/sys/kernel/debug`).

### Vorteil:
Jedes Interface sieht nur 2 Kanäle → RP1 akzeptiert.

### Nachteil:
- 2 PCM-Geräte in ALSA
- Software muss beide öffnen und synchronisieren

---

## Lösungsweg L: GPIO/PIO Direct I2S (HARDCORE)
**Status**: ⚠️ Sehr experimentell  
**Dateien**: Kernel-Modul oder Userspace mit `/dev/gpiomem`

### Konzept:
- RP1 GPIO direkt für I2S nutzen
- PIO (Programmable I/O) State Machine implementiert
- Umgeht designware-i2s komplett

### Vorteile:
- Totale Kontrolle über Timing
- Keine Kernel-Treiber-Limitierungen

### Nachteile:
- **Sehr** komplex
- Real-Time-Anforderungen
- Kein ALSA-Integration

### Nur wenn alle anderen Wege scheitern.

---

## Lösungsweg M: Designware-i2s Kernel-Patch (NACHHALTIG)
**Status**: 🔵 Beste langfristige Lösung  
**Dateien**: `/usr/src/linux/.../sound/soc/dwc/designware_i2s.c`

### Konzept:
Patch für den RP1 designware-i2s Treiber:

```c
// In dw_i2s_hw_params():
if (channels > 2 && dev->capability & DW_I2S_MULTICHAN) {
    // Aktiviere TDM-Mode
    regmap_update_bits(dev->regmap, CCR, 
                       WSS_MASK | SCLKG_MASK,
                       WSS_32 | SCLKG_CLK_GATE_NONE);
    
    // Setze Channel-Config für 4ch
    for (i = 0; i < channels; i++) {
        regmap_write(dev->regmap, RCR(i), WLEN_32);
    }
}
```

### Warum erfolgversprechend:
- Designware IP unterstützt TDM generisch
- RP1-spezifische Limitierung könnte Software-seitig sein

### Vorgehen:
1. Kernel-Source für RPi 5 herunterladen
2. `sound/soc/dwc/designware_i2s.c` patchen
3. Kernel-Modul neu kompilieren
4. Insmod testen

---

## Lösungsweg N: AC108 Daisy-Chain Mode (SPEZIAL)
**Status**: 🔵 Hardware-Datenblatt prüfen  
**Dateien**: `ac108.c`

### Konzept:
Manche Multi-Channel-Codecs haben "Daisy-Chain" oder "Cascade" Mode:
- Master-AC108 aggregiert Daten vom Slave
- RP1 sieht nur Master als einzelnen 2-Kanal-Codec

### Prüfen:
AC108-Datenblatt auf "Cascade Mode" oder "Multi-Codec Sync" überprüfen.

---

## Lösungsweg O: Alternativer Codec/HAT (HARDWARE-TAUSCH)
**Status**: ⚠️ Fallback  
**Hardware**: Andere Lösungen

### Optionen:
1. **2× WM8960** (2 Stereo-Codecs)
2. **USB-Mikrofonarray** (UMA-8)
3. **Pi 4 verwenden** (funktioniert dort)

### Nur wenn RP5 + AC108 nicht lösbar.

---

## Lösungsweg P: Spezialisierte Kernel-Fork (COMMUNITY)
**Status**: 🔵 Recherche nötig  
**Quellen**: GitHub, RPi-Forums

### Konzept:
Community-Kernel mit erweiterten Audio-Features:
- RT-Patches
- Erweiterte I2S-Treiber
- Speziell für Audio optimiert

### Beispiele:
- `linux-rpi-audio` Fork
- RT-Preempt Kernel

---

## Prioritäten-Matrix

| Priorität | Lösungsweg | Aufwand | Erfolgswahrscheinlichkeit | Nächster Schritt |
|-----------|------------|---------|---------------------------|------------------|
| **1** | **H: DT TDM-Slots** | Niedrig | Mittel-Hoch | DTS erweitern, testen |
| **2** | **I: Encoding Mode** | Mittel | Hoch | AC108 Register checken |
| **3** | **J: BCLK Ratio** | Mittel | Mittel | Timing-Experimente |
| **4** | **M: Kernel-Patch** | Hoch | Sehr hoch | Source analysieren |
| 5 | A: 2ch Workaround | Niedrig | Mittel | BCLK-Fix fertigstellen |
| 6 | K: Multi-SDO | Mittel | Mittel | I2S-Interfaces zählen |
| 7 | G: ALSA-Plugin | Mittel | Hoch | Wenn 2ch läuft |
| 8 | N: Daisy-Chain | Niedrig | Unbekannt | Datenblatt prüfen |

---

## Sofort-Test-Plan (heute)

### Test 1: Device Tree TDM (Lösungsweg H)
```bash
# 1. DTS editieren
nano seeed-4mic-voicecard-rpi5-overlay.dts

# 2. Kompilieren
./builddtbo.sh

# 3. Overlay neu laden
sudo dtoverlay -r seeed-4mic-voicecard-rpi5
sudo dtoverlay seeed-4mic-voicecard-rpi5

# 4. Testen
arecord -D hw:0,0 -c4 -f S16_LE -r 16000 -d 2 /tmp/test.wav
```

### Test 2: AC108 Encoding Mode (Lösungsweg I)
```bash
# 1. ac108.c editieren - ENCD_SEL aktivieren
# 2. Neu kompilieren
make -j4 && sudo make install

# 3. Reload
sudo rmmod snd_soc_ac108 && sudo modprobe snd_soc_ac108

# 4. Register prüfen
sudo i2cget -y 1 0x3b 0x30  # I2S_CTRL sollte Bit gesetzt haben
```

### Test 3: Kernel Source Check (Lösungsweg M)
```bash
# RP1 designware-i2s Capabilities prüfen
cat /sys/devices/platform/axi/1f00000000.pcie/1f00080000.pcie/1f000a0000.i2s/*/capabilities

# Kernel-Config prüfen
zcat /proc/config.gz | grep DW_I2S
```

---

## Debugging-Tools (IMPLEMENTIERT)
**Status**: ✅ Diagnostik funktioniert  
**Dateien**: 
- `ac108_diagnostic_logger.sh` (umfangreiches Logging)
- Minimal JSON Output für Automatisierung

### Features:
- Erkennt "UU" (kernel owns device)
- Überspringt i2cget wenn sinnlos
- Kernel-Log-Analyse
- ALSA hw_params dump
- Clock/Pinmux/GPIO Check

---

## Nächste empfohlene Schritte

### SOFORT (vor Reboot):
1. **✅ Alle Lösungswege dokumentiert** (A-P)
2. **✅ Build-Script erstellt** (`build_solution.sh`)
3. **✅ Prioritäten-Matrix angelegt**

### NACH Reboot - Priorität 1:
**Lösungsweg H: Device Tree TDM-Slots testen**
```bash
cd /home/adm_behnke/seeed-voicecard
./build_solution.sh H
```

### NACH Reboot - Priorität 2:
**Lösungsweg I: AC108 Encoding Mode**
```bash
./build_solution.sh I
```

### Wenn H+I scheitern - Priorität 3:
**Lösungsweg M: Kernel-Patch vorbereiten**
```bash
apt-get source linux-image-$(uname -r)
# Dann designware_i2s.c patchen
```

---

## Schnell-Wechsel zwischen Lösungswegen

### Branch-System:
```bash
# Aktuellen Stand sichern
git branch solution-A-2ch-workaround

# Lösungsweg B testen
git checkout solution-B-tdm-slots
make clean && make -j4
sudo make install && sudo reboot

# Zurück zu A
git checkout solution-A-2ch-workaround
```

### Compile-Zeit-Schalter:
```c
#ifdef RP5_2CH_WORKAROUND
    // 2-Kanal-Constraint
#elif defined(RP5_TDM_HACK)
    // TDM-Slot-Programmierung
#elif defined(RP5_KERNEL_PATCH)
    // Kernel-Patch-Modus
#endif
```

---

## Erfolgs-Kriterien

### Minimal (akzeptabel):
- ✅ 2 Kanäle funktionieren
- ✅ Stabile Aufnahme ohne Fehler
- ⚠️ Nur 2 von 4 Mics nutzbar

### Optimal (Ziel):
- ✅ 4 Kanäle funktionieren
- ✅ Alle Mics nutzbar
- ✅ Keine Kernel-Patches nötig

---

**Letztes Update**: 2026-01-03 19:30  
**Status**: 16 Lösungswege dokumentiert, Priorität 1+2 bereit für Test nach Reboot  
**Nächster Schritt**: Lösungsweg H (DT TDM) → I (Encoding) → M (Kernel-Patch)
