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

**For Raspberry Pi 5 with kernel 6.12+:**
The installation process is the same as above. The installer will automatically:
- Detect your kernel version (6.12+)
- Install appropriate kernel headers (raspberrypi-kernel-headers or linux-headers-raspi)
- Build and install drivers using DKMS for your specific kernel
- Install updated device tree overlays with BCM2712 support
- Configure the audio system for your ReSpeaker device

After reboot, verify the installation:
```bash
# Check if the driver modules are loaded
lsmod | grep snd_soc

# For 4-Mic Array, check if the device is detected
arecord -l | grep seeed4micvoicec

# Test recording (4-Mic Array example)
arecord -Dhw:seeed4micvoicec -f S32_LE -r 16000 -c 4 test.wav
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

For hardware testing purposes we made a Raspberry Pi OS 5.10.17-v7l+ 32-bit image with reSpeaker drivers pre-installed, which you can download by clicking on [this link](https://files.seeedstudio.com/linux/Raspberry%20Pi%204%20reSpeaker/2021-05-07-raspios-buster-armhf-lite-respeaker.img.xz).

We provide official support for using reSpeaker with the following OS:
- 32-bit Raspberry Pi OS
- 64-bit Raspberry Pi OS
- Kernel versions from 4.19 through 6.12+ (including latest 6.13)

And following hardware platforms:
- Raspberry Pi 3 (all models)
- Raspberry Pi 4 (all models)
- Raspberry Pi 5 (all models with kernel 6.12+)

### Raspberry Pi 5 Support (Kernel 6.12+)

The drivers now support Raspberry Pi 5 with kernel 6.12 and later versions. The device tree overlays have been updated to support the BCM2712 SoC used in Raspberry Pi 5, while maintaining backward compatibility with earlier Raspberry Pi models (BCM2835, BCM2836, BCM2837, BCM2711).

**Key updates for RPi5 with kernel 6.12:**
- Device tree overlays support BCM2712 SoC
- Kernel 6.13 ASoC changes (rtd->id) are implemented
- All ReSpeaker models work: 2-Mic, 4-Mic, 6-Mic, and 8-Mic arrays
- Installation process remains the same using `./install.sh`

**4-Mic Array on Raspberry Pi 5:**
The 4-Mic Array uses the AC108 codec and connects via I2C and I2S interfaces. After installation, the device will appear as `seeed4micvoicec` in ALSA. The configuration file `/etc/voicecard/asound_4mic.conf` provides the proper PCM device mapping.

Anything beyond the scope of official support is considered to be community supported. Support for other OS/hardware platforms can be added, provided MOQ requirements can be met.

If you have a technical problem when using reSpeaker with one of the officially supported platforms/OS, feel free to create an issue on Github. For general questions or suggestions, please use [Seeed forum](https://forum.seeedstudio.com/c/products/respeaker/15). 


