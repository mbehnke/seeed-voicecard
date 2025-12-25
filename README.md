# seeed-voicecard

The drivers for [ReSpeaker Mic Hat](https://www.seeedstudio.com/ReSpeaker-2-Mics-Pi-HAT-p-2874.html), [ReSpeaker 4 Mic Array](https://www.seeedstudio.com/ReSpeaker-4-Mic-Array-for-Raspberry-Pi-p-2941.html), [6-Mics Circular Array Kit](), and [4-Mics Linear Array Kit]() for Raspberry Pi.

### Install seeed-voicecard
Get the seeed voice card source code and install all linux kernel drivers
```bash
git clone https://github.com/HinTak/seeed-voicecard
cd seeed-voicecard
sudo ./install.sh
sudo reboot
```
## ReSpeaker Documentation

Up to date documentation for reSpeaker products can be found in [Seeed Studio Wiki](https://wiki.seeedstudio.com/ReSpeaker/)!
![](https://files.seeedstudio.com/wiki/ReSpeakerProductGuide/img/Raspberry_Pi_Mic_Array_Solutions.png)


### Coherence

Estimate the magnitude squared coherence using Welch’s method.
![4-mics-linear-array-kit coherence](https://user-images.githubusercontent.com/3901856/37277486-beb1dd96-261f-11e8-898b-84405bfc7cea.png)  
Note: 'CO 1-2' means the coherence between channel 1 and channel 2.

```bash
# How to get the coherence of the captured audio(a.wav for example).
sudo apt install python-numpy python-scipy python-matplotlib
python tools/coherence.py a.wav

# Requirement of the input audio file:
- format: WAV(Microsoft) signed 16-bit PCM
- channels: >=2
```

### uninstall seeed-voicecard
If you want to upgrade the driver , you need uninstall the driver first.

```
pi@raspberrypi:~/seeed-voicecard $ sudo ./uninstall.sh 
...
------------------------------------------------------
Please reboot your raspberry pi to apply all settings
Thank you!
------------------------------------------------------
```

Enjoy !

### Technical support

For hardware testing purposes we made a Rasperry Pi OS 5.10.17-v7l+ 32-bit image with reSpeaker drivers pre-installed, which you can download by clicking on [this link](https://files.seeedstudio.com/linux/Raspberry%20Pi%204%20reSpeaker/2021-05-07-raspios-buster-armhf-lite-respeaker.img.xz).

We provide official support for using reSpeaker with the following OS:
- 32-bit Raspberry Pi OS
- 64-bit Raspberry Pi OS

And following hardware platforms:
- Raspberry Pi 3 (all models), Raspberry Pi 4 (all models)

Anything beyond the scope of official support is considered to be community supported. Support for other OS/hardware platforms can be added, provided MOQ requirements can be met. 

If you have a technical problem when using reSpeaker with one of the officially supported platforms/OS, feel free to create an issue on Github. For general questions or suggestions, please use [Seeed forum](https://forum.seeedstudio.com/c/products/respeaker/15). 

Super — ich habe das Web systematisch durchforstet und die technischen Fakten zum **Seeed / ReSpeaker 4-Mic Array** (inkl. Linear-Kit Varianten) zusammengetragen. Unten findest du eine technisch konzentrierte Übersicht (Hardware, Codecs, Schnittstellen, Software/Driver, typische Probleme, Hinweise für Portierung/Integration) mit den wichtigsten Quellen. Wenn du möchtest, erstelle ich direkt ein Beispiel-Device-Tree-Overlay, ein kurzes Kernel-Build-Howto oder ein Troubleshooting-Checklist für Raspberry Pi 5.

# Kurz-Zusammenfassung (Kernaussagen)

* Das 4-Mic-Array nutzt den **AC108** (X-Powers) als Quad-ADC (I2S/TDM) und (bei Linear-Kit) zusätzlich einen **AC101** als DAC für Headset/Lautsprecher-Ausgang. ([cdn.sparkfun.com][1])
* Vier analoge MEMS-Mikrofone (häufig: **Knowles SPU0414HR5HSB**) sind verbaut; Sensitivity ≈ **−22 dBFS**, SNR ≈ **59 dB** (Angaben aus Produkt-Specs). ([static5.arrow.com][2])
* Schnittstellen: **I2S / TDM** (Audio-Daten), **I²C** (Control), 40-Pin Raspberry-Header, zusätzliche **Grove I2C** / GPIO-Anschlüsse und APA102 LED-Ring (SPI-adressierbar). ([wiki.seeedstudio.com][3])
* Offizielle/Community-Treiber: `seeed-voicecard` / `respeaker/seeed-voicecard` und Forks; Installation via Git + Install-Script, aber Kernel/DT-Kompatibilität kann bei neueren Raspberry-OS-/Kernel-Versionen Probleme machen (Threaded Issues vorhanden). ([GitHub][4])

---

# Detaillierte Technik-Übersicht

## Hardware / Bauteile

* **ADCs/DACs**

  * **AC108**: Quad-Channel ADC, TDM/I2S-Ausgang, interne PLL für Standard-Audio-Sampleraten (unterstützt u. a. 8 / 16 / 22.05 / 24 / 32 / 44.1 / 48 kHz). Wird typischerweise als Multi-MIC ADC eingesetzt. ([cdn.sparkfun.com][1])
  * **AC101** (bei Linear Kit): Stereo DAC für Kopfhörer/Line-Out (Register-gesteuert, Sample-rate gekoppelt an ADC). ([files.seeedstudio.com][5])
* **Mikrofone**: Knowles SPU0414HR5HSB (omnidirectional MEMS), typische Werte Sensitivity −22 dBFS, SNR ≈ 59 dB. ([docs.rs-online.com][6])
* **LEDs**: 12× APA102 (programmierbare RGB), über SPI ansteuerbar (für DOA / VU / Status).
* **Anschlüsse**: 40-Pin HAT Header zum Pi, Grove I2C, JST-Stecker bei manchen Kits; Linear Kit besteht aus Voice HAT + separatem Mic-Flex-Strip. ([wiki.seeedstudio.com][7])

## Elektrische / Audio-Schnittstellen

* **Audio data out**: I2S standard oder TDM (AC108 unterstützt TDM-Mode zur Übertragung mehrerer Kanäle über einen I2S-Bus). Auf Raspberry Pi wird das üblicherweise als externes Soundcard-Device konfiguriert. ([Scribd][8])
* **Control bus**: AC108 konfigurierbar über I²C (z. B. Gain, Sample-Rate Einstellungen). Grove-I2C ist auf dem HAT herausgeführt. ([wiki.seeedstudio.com][3])

## Software / Treiber / Integration

* **Repo / Treiber**: `seeed-voicecard` (respeaker/seeed-voicecard & Community-Forks) liefert das Install-Script, Device-Tree-Overlay(s) und ALSA-Konfigurationen für die ReSpeaker HATs/Arrays. Installation: `git clone` + `sudo ./install.sh`. Achtung: Script ändert System-Audio/ALSA-Konfig.
* **Device Tree / Overlay**: Hardware wird per DTS/DTSI konfiguriert (sound-card, ac108 codec node). Für andere Plattformen (Jetson, Rockchip etc.) muss das DTS portiert werden. Viele Community-Beiträge zeigen genau das (DTS-Beispiele vorhanden). ([NVIDIA Developer Forums][9])
* **ALSA/Pulse/Multiple Channels**: ReSpeaker-Setups melden oft mehrere Aufnahmekanäle (z. B. 8in/8out für Linear kit), wobei nur die ersten 4 Capture-Kanäle echte Mic-Daten liefern (Rest Echo/Dummy). ([wiki.seeedstudio.com][7])

## Unterstützte Sample-Rates / Clocking

* AC108 unterstützt Standard-Raten (8, 16, 22.05, 24, 32, 44.1, 48 kHz). Interne PLL erlaubt verschiedene Referenzclock-Frequenzen (z. B. 6/12/13/19.2 MHz etc.). Das ist wichtig beim Setzen von I2S/DAI/Formats im DTS. ([Scribd][8])

---

# Typische Probleme & Hinweise aus Praxis / Community

* **Kernel / Raspberry-OS-Versionen**: Nutzerberichte zeigen, dass die `seeed-voicecard` Installation mit bestimmten neueren Kernel-Versionen (RPI4/RPI5) Probleme macht — u. a. nicht erkannte Soundcard oder fehlende Overlay-Kompatibilität. Es existieren Issues/Workarounds in den GitHub- und Seeed-Foren. (Meinung: das ist erwartbar bei älteren HATs, da DT/ABI sich mit Kernel-Upgrades ändert.) ([GitHub][4])
* **Portierung auf andere SOCs** (Jetson, RK, etc.): funktioniert, erfordert aber DTS-/Clock-Mapping-Arbeit und ggf. Kernel-Modul-Kompilierung. ([NVIDIA Developer Forums][9])
* **Echo/Loopback-Kanäle**: Einige Kits liefern zusätzliche virtuelle Kanäle (Echo/Playback dummy channels) — ALSA-Routing anpassen, wenn du nur die 4 Mic-Inputs brauchst. ([wiki.seeedstudio.com][7])

---

# Nützliche Dateien / Orte (für direkten Zugriff)

* Seeed Wiki Produktseite (Beschreibung, Quickstart, Beispiele). ([wiki.seeedstudio.com][3])
* `seeed-voicecard` GitHub (Treiber, Install-Script, Overlays).
* AC108 Datasheet (X-Powers) — Pinout, PLL, unterstützte Samplerates. ([cdn.sparkfun.com][1])
* ReSpeaker 4-Mic Produkt-Manual / PDF (Technische Specs, Mikrofon-Typen). ([static5.arrow.com][2])
* Community-Threads / Issues zu Pi4/Pi5 Kompatibilität und Troubleshooting. ([Seeed Studio Forum][10])

---

# Konkrete technische To-Dos (wenn du tiefer einsteigen willst) — ich kann das direkt ausarbeiten

1. **DT-Overlay Beispiel für Raspberry Pi 5** (DTS-Snippet + Hinweise auf clocks/asychrones TDM) — inklusive `snd-soc` Eintrag und ac108 codec-node. *(empfohlen, wenn du das Array an RPI5 betreibst)*.
2. **Kernel-Modul-Build-Kurzguide** (wie man `seeed-voicecard` kompiliert / anpasst für neueren Kernel + typische Patch-Hacks).
3. **ALSA-Routing/Config**: Minimales `.asoundrc`/`alsa-setup` für nur 4-Mic Capture + Skripte fürs Testen (arecord mit channel map).
4. **DOA / Beamforming Stack**: Überblick über freie KWS/DOA-Libs (z. B. Mycroft/Porcupine/Weave-stacks) + wie man die APA102 LED-Ring-Signalisierung koppelt. *(Opinion: für einfache DOA reicht oft VAD+TDOA, komplexeres Beamforming braucht DSP work)*.

[1]: https://cdn.sparkfun.com/assets/6/0/d/c/a/AC108_Datasheet_V1.1.pdf?utm_source=chatgpt.com "AC108 Datasheet"
[2]: https://static5.arrow.com/pdfs2/2019/3/24/12/39/13/515728/seeed_/manual/respeaker4-micarrayforraspberrypi.pdf?utm_source=chatgpt.com "ReSpeaker 4-Mic Array for Raspberry Pi"
[3]: https://wiki.seeedstudio.com/ReSpeaker_4_Mic_Array_for_Raspberry_Pi/?utm_source=chatgpt.com "ReSpeaker 4-Mic Array for Raspberry Pi | Seeed Studio Wiki"
[4]: https://github.com/respeaker/seeed-voicecard/issues/246?utm_source=chatgpt.com "ReSpeaker 4-Mic with Raspberry Pi OS (previously called ..."
[5]: https://files.seeedstudio.com/wiki/ReSpeaker_6-Mics_Circular_Array_kit_for_Raspberry_Pi/reg/AC101_User_Manual_v1.1.pdf?utm_source=chatgpt.com "AC101 User Manual"
[6]: https://docs.rs-online.com/489a/0900766b8168eba6.pdf?utm_source=chatgpt.com "ReSpeaker 4-Mic Linear Array Kit 2018/10/29 - RS Online"
[7]: https://wiki.seeedstudio.com/ReSpeaker_4-Mic_Linear_Array_Kit_for_Raspberry_Pi/?utm_source=chatgpt.com "ReSpeaker 4-Mic Linear Array Kit | Seeed Studio Wiki"
[8]: https://www.scribd.com/document/903045685/AC108-BRIEFv2?utm_source=chatgpt.com "AC108 BRIEFv2. | PDF | Analog To Digital Converter"
[9]: https://forums.developer.nvidia.com/t/how-to-port-raspberry-pi-hardware-respeaker-4-mic-array/77117?utm_source=chatgpt.com "How to port Raspberry Pi hardware: ReSpeaker 4 Mic Array"
[10]: https://forum.seeedstudio.com/t/respeaker-v1-4-microphone-array-why-no-support-for-rp4/268459?utm_source=chatgpt.com "Respeaker V1 4 Microphone array -- Why no support for ..."

