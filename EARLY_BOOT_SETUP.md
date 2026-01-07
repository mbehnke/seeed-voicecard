# Early Boot Capture & Diagnostic Setup

## Summary of Changes

### 1. **Early Boot Script** (`early_boot_capture.sh`)
- **Expanded** to collect comprehensive audio state immediately after kernel boot
- Runs at `@reboot` via cron (root)
- Logs to `/home/adm_behnke/seeed-voicecard/logs/early_boot_YYYYMMDD_HHMMSS.log`
- Outputs minimal machine-readable JSON status to `/home/adm_behnke/seeed-voicecard/logs/early_boot_YYYYMMDD_HHMMSS.json`

**Captures:**
- dmesg (ac108/seeed/i2s/asoc)
- lsmod (module status)
- arecord -l (ALSA card list)
- amixer scontrols (mixer controls)
- i2cdetect (I2C bus status)
- /sys/kernel/debug/asoc/cards and dais
- Test recording (1-2s) with sox analysis
- Device Tree codec info

**Output JSON:**
```json
{
  "status": "error|success",
  "error_code": -1|-2|-3|0,
  "key_metrics": {
    "device_detected": true|false,
    "i2c_status": "in_use|busy_or_failed|unknown",
    "alsa_controls": <count>,
    "recording_max_level": "<level>"
  },
  "root_cause": "ALSA card missing|AC108 controls missing|capture silent|ok",
  "required_actions": ["cmd1", "cmd2", ...]
}
```

### 2. **Diagnostic Script** (`diagnose_audio_2.sh`)
- **Rewritten** to produce valid JSON with proper metrics
- Logs stored in project directory (not /root)
- Runs DAI formats, DAPM routes, TDM logs, hwparams, mixer, I2C, and recording
- Emits same minimal JSON schema as early_boot script

### 3. **Device Tree Overlay Update** (`seeed-4mic-voicecard-rpi5-overlay.dts`)
- **TDM slot configuration**: Changed from 2 slots to **4 slots**
- **Slot masks**: `dai-tdm-slot-rx-mask = <1 1 1 1>` and `tx-mask = <1 1 1 1>`
- **Recompiled** to DTBO (1.8 KB)
- **Merged** into `/boot/firmware/bcm2712-rpi-5-b.dtb` via fdtoverlay

### 4. **Cron Integration**
- Added to root crontab: `@reboot /home/adm_behnke/seeed-voicecard/early_boot_capture.sh`
- Runs at every boot before any user login
- Captures fresh audio state before ALSA is heavily used

---

## How to Use

### **Step 1: Reboot with Updated DTB & Cron**
```bash
sudo reboot
```
- Kernel loads updated DTB with 4-channel TDM slots
- Cron triggers `early_boot_capture.sh` → logs to `/home/adm_behnke/seeed-voicecard/logs/`

### **Step 2: Check Early Boot Logs** (after reboot)
```bash
# View the latest early boot log
ls -lt /home/adm_behnke/seeed-voicecard/logs/early_boot_*.log | head -1
tail -100 /home/adm_behnke/seeed-voicecard/logs/early_boot_*.log

# View the status JSON
cat /home/adm_behnke/seeed-voicecard/logs/early_boot_*.json | jq .
```

### **Step 3: Run Enhanced Diagnostics**
```bash
sudo bash /home/adm_behnke/seeed-voicecard/diagnose_audio_2.sh
```
Outputs detailed logs in `/home/adm_behnke/seeed-voicecard/logs/ac108_debug_YYYYMMDD_HHMMSS/`

### **Step 4: Parse Machine-Readable Status**
```bash
# Example: Extract error code and root cause
jq '.error_code, .root_cause' /home/adm_behnke/seeed-voicecard/logs/early_boot_*.json

# Example: Extract required actions
jq '.required_actions[]' /home/adm_behnke/seeed-voicecard/logs/early_boot_*.json
```

---

## Key Metrics Interpretation

| Metric | Meaning |
|--------|---------|
| `device_detected` | ALSA card "seeed4micvoicec" found |
| `i2c_status` | "in_use" = codec bound, "busy_or_failed" = driver blocking |
| `alsa_controls` | Number of AC108 mixer controls (should be ≥4) |
| `recording_max_level` | Audio sample peak; "0.000000" = silent |

| error_code | Meaning |
|------------|---------|
| 0 | Success (all checks pass) |
| -1 | ALSA card not detected |
| -2 | AC108 mixer controls missing |
| -3 | Capture silent (max level = 0) |

---

## Files Modified/Created

1. **early_boot_capture.sh** – Enhanced, now ~120 lines
2. **diagnose_audio_2.sh** – JSON output fixed, ~196 lines
3. **seeed-4mic-voicecard-rpi5-overlay.dts** – TDM slots updated (2→4)
4. **seeed-4mic-voicecard-rpi5.dtbo** – Recompiled (1.8 KB)
5. **/boot/firmware/bcm2712-rpi-5-b.dtb** – Merged with updated overlay
6. **/root/.crontab** – @reboot entry added

---

## Next Steps After Reboot

1. **Check early boot logs** for device_detected, i2c_status, alsa_controls
2. **If silent**: Set gains → `amixer -c 0 sset "ADC1 PGA gain" 31`
3. **If missing controls**: Run → `sudo alsactl init`
4. **If card missing**: Check DTS → `cat /proc/device-tree/sound/compatible`
5. **Run diagnose_audio_2.sh** for detailed DAPM/DAI analysis

---

## Troubleshooting

**Problem:** early_boot_capture.sh not running
- **Check cron:** `sudo crontab -l`
- **Manual test:** `bash /home/adm_behnke/seeed-voicecard/early_boot_capture.sh`
- **Verify perms:** `ls -la /home/adm_behnke/seeed-voicecard/early_boot_capture.sh`

**Problem:** Logs directory permission denied
- **Fix:** `sudo chown -R adm_behnke:adm_behnke /home/adm_behnke/seeed-voicecard/logs`

**Problem:** JSON parse error
- **Check:** `jq . /path/to/status.json` for syntax errors
- **Fallback:** `cat /path/to/status.json` to inspect raw content

