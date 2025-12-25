#!/bin/bash
# Comprehensive AC108 Diagnostic – Captures during recording for minimal state
# Output: machine-readable JSON to logs/

set -e

PROJECT_DIR="/home/adm_behnke/seeed-voicecard"
LOG_DIR="$PROJECT_DIR/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$LOG_DIR/ac108_comprehensive_${TIMESTAMP}.json"

mkdir -p "$LOG_DIR"

# Start background recording
arecord -D hw:0,0 -f S32_LE -r 16000 -c 4 -d 1 -t wav -q /tmp/diagnostic_test.wav &
ARECORD_PID=$!
sleep 0.3  # Let recording start

# Helper: read register via debugfs
read_reg() {
    local addr=$1
    local line=$((addr + 1))
    sudo sed -n "${line}p" /sys/kernel/debug/regmap/1-003b/registers 2>/dev/null | awk '{print $NF}'
}

# Key registers during capture
MOD_CLK_EN=$(read_reg 0x21)
MOD_RST_CTRL=$(read_reg 0x22)
I2S_CTRL=$(read_reg 0x30)
I2S_TX1_CTRL2=$(read_reg 0x39)
I2S_TX1_CHMP_CTRL1=$(read_reg 0x3c)
ADC_DIG_EN=$(read_reg 0x61)
ANA_ADC1_CTRL1=$(read_reg 0xA0)
ANA_ADC2_CTRL1=$(read_reg 0xA7)

# Wait for recording to finish
wait $ARECORD_PID 2>/dev/null || true

# Analyze recording
RMS=$(sox /tmp/diagnostic_test.wav -n stat 2>&1 | grep "RMS" | awk '{print $3}')

# Generate comprehensive JSON
cat > "$OUTPUT_FILE" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "audio_status": {
    "rms_amplitude": "$RMS",
    "silent": "$([ "$RMS" = "0.000000" ] && echo true || echo false)"
  },
  "register_snapshot": {
    "MOD_CLK_EN_0x21": "0x$MOD_CLK_EN",
    "MOD_RST_CTRL_0x22": "0x$MOD_RST_CTRL",
    "I2S_CTRL_0x30": "0x$I2S_CTRL",
    "I2S_TX1_CTRL2_0x39": "0x$I2S_TX1_CTRL2",
    "I2S_TX1_CHMP_CTRL1_0x3c": "0x$I2S_TX1_CHMP_CTRL1",
    "ADC_DIG_EN_0x61": "0x$ADC_DIG_EN",
    "ANA_ADC1_CTRL1_0xA0": "0x$ANA_ADC1_CTRL1",
    "ANA_ADC2_CTRL1_0xA7": "0x$ANA_ADC2_CTRL1"
  },
  "analysis": {
    "mod_clk_enabled": "$([ "$MOD_CLK_EN" != "00" ] && echo "true" || echo "false")",
    "i2s_tx_enabled": "$(echo "$I2S_CTRL" | grep -qE "^3[3-9a-fA-F]$|^[4-9a-fA-F]" && echo "true" || echo "false")",
    "adc_digital_enabled": "$([ "$ADC_DIG_EN" = "1f" ] && echo "true" || echo "false")",
    "ana_micbias_enabled_ch1": "$(echo "$ANA_ADC1_CTRL1" | grep -qE "^0[1357bdf9]$" && echo "true" || echo "false")"
  },
  "root_cause": "$(
    if [ "$RMS" = "0.000000" ]; then
      if [ "$MOD_CLK_EN" = "00" ]; then
        echo "Module clocks not enabled during capture"
      elif [ $((0x$I2S_CTRL & 0x0C)) -ne 0x0C ]; then
        echo "I2S TX/GEN not enabled (I2S_CTRL=0x$I2S_CTRL)"
      elif [ $((0x$ANA_ADC1_CTRL1 & 0x01)) -eq 0 ]; then
        echo "MICBIAS not enabled on analog path"
      else
        echo "All registers configured but audio silent - hardware or firmware issue"
      fi
    else
      echo "Audio signal detected - success"
    fi
  )",
  "required_actions": [
    "Confirm register values above match expected hardware state",
    "If MOD_CLK_EN=0x00, investigate regcache persistence issue",
    "If I2S_CTRL TXEN/GEN disabled, ensure codec startup sets bits 3:2",
    "If MICBIAS disabled, verify DAPM supply path activation",
    "Perform hardware scope test on MCLK, BCLK, LRCK, MIC input"
  ]
}
EOF

echo "Comprehensive diagnostic written to: $OUTPUT_FILE"
cat "$OUTPUT_FILE"
