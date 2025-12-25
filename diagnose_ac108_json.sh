#!/bin/bash
# Minimal AC108 register dump and diagnostic JSON for RPi 5
# Output: machine-readable JSON to logs/

set -e

PROJECT_DIR="/home/adm_behnke/seeed-voicecard"
LOG_DIR="$PROJECT_DIR/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$LOG_DIR/ac108_diag_${TIMESTAMP}.json"

mkdir -p "$LOG_DIR"

# Helper: read register via debugfs
read_reg() {
    local addr=$1
    local line=$((addr + 1))
    sudo sed -n "${line}p" /sys/kernel/debug/regmap/1-003b/registers 2>/dev/null | awk '{print $NF}'
}

# Key register addresses
REG_MOD_CLK_EN=0x21
REG_MOD_RST_CTRL=0x22
REG_I2S_CTRL=0x30
REG_I2S_TX1_CTRL2=0x39
REG_I2S_TX1_CHMP_CTRL1=0x3c
REG_ADC_DIG_EN=0x61
REG_ADC1_DVOL=0x70
REG_ADC2_DVOL=0x71
REG_ADC3_DVOL=0x72
REG_ADC4_DVOL=0x73

# Read register values
MOD_CLK_EN=$(read_reg $REG_MOD_CLK_EN)
MOD_RST_CTRL=$(read_reg $REG_MOD_RST_CTRL)
I2S_CTRL=$(read_reg $REG_I2S_CTRL)
I2S_TX1_CTRL2=$(read_reg $REG_I2S_TX1_CTRL2)
I2S_TX1_CHMP_CTRL1=$(read_reg $REG_I2S_TX1_CHMP_CTRL1)
ADC_DIG_EN=$(read_reg $REG_ADC_DIG_EN)
ADC1_DVOL=$(read_reg $REG_ADC1_DVOL)

# ALSA card detection
ALSA_CARD=""
if arecord -l 2>/dev/null | grep -q "seeed4micvoicec"; then
    ALSA_CARD="detected"
fi

# I2C detection
I2C_STATUS="unknown"
if i2cdetect -y 1 2>/dev/null | grep -q "3b"; then
    I2C_STATUS="ac108_detected"
fi

# Generate JSON
cat > "$OUTPUT_FILE" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "$([ "$MOD_CLK_EN" != "00" ] && echo "clocks_enabled" || echo "clocks_disabled")",
  "registers": {
    "MOD_CLK_EN_0x21": "0x$MOD_CLK_EN",
    "MOD_RST_CTRL_0x22": "0x$MOD_RST_CTRL",
    "I2S_CTRL_0x30": "0x$I2S_CTRL",
    "I2S_TX1_CTRL2_0x39": "0x$I2S_TX1_CTRL2",
    "I2S_TX1_CHMP_CTRL1_0x3c": "0x$I2S_TX1_CHMP_CTRL1",
    "ADC_DIG_EN_0x61": "0x$ADC_DIG_EN",
    "ADC1_DVOL_0x70": "0x$ADC1_DVOL"
  },
  "detection": {
    "alsa_card": "$ALSA_CARD",
    "i2c_ac108": "$I2C_STATUS"
  },
  "root_cause": "$(
    if [ "$MOD_CLK_EN" = "00" ]; then
      echo "Module clocks disabled (MOD_CLK_EN=0x00)"
    elif [ "$I2S_CTRL" = "30" ]; then
      echo "I2S_CTRL suggests TX/GEN disabled (0x30)"
    elif [ "$ADC_DIG_EN" = "1f" ]; then
      echo "ADC digital enabled but no analog signal (check MICBIAS/DSM analog path)"
    else
      echo "Silent capture despite register configuration"
    fi
  )",
  "required_actions": [
    "Verify MOD_CLK_EN persistent during capture",
    "Confirm I2S_CTRL TXEN/GEN enabled at stream start",
    "Check ADC analog path: MICBIAS voltage, DSM, PGA unmute"
  ]
}
EOF

echo "Diagnostic written to: $OUTPUT_FILE"
cat "$OUTPUT_FILE"
