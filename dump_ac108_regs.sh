#!/bin/bash
# Dump AC108 registers via i2cget
# AC108 is at address 0x3b on i2c bus 1

echo "=== AC108 Register Dump ==="
echo ""
echo "PLL Registers:"
printf "0x10 PLL_CTRL1:     0x%02x\n" $(sudo i2cget -y 1 0x3b 0x10)
printf "0x11 PLL_CTRL2:     0x%02x\n" $(sudo i2cget -y 1 0x3b 0x11)
printf "0x12 PLL_CTRL3:     0x%02x\n" $(sudo i2cget -y 1 0x3b 0x12)
printf "0x13 PLL_CTRL4:     0x%02x\n" $(sudo i2cget -y 1 0x3b 0x13)
printf "0x14 PLL_CTRL5:     0x%02x\n" $(sudo i2cget -y 1 0x3b 0x14)
printf "0x16 PLL_CTRL6:     0x%02x\n" $(sudo i2cget -y 1 0x3b 0x16)
printf "0x17 PLL_CTRL7:     0x%02x\n" $(sudo i2cget -y 1 0x3b 0x17)
printf "0x18 PLL_LOCK_CTRL: 0x%02x\n" $(sudo i2cget -y 1 0x3b 0x18)
echo ""
echo "Clock Control:"
printf "0x20 SYSCLK_CTRL:   0x%02x\n" $(sudo i2cget -y 1 0x3b 0x20)
printf "0x21 MOD_CLK_EN:    0x%02x\n" $(sudo i2cget -y 1 0x3b 0x21)
printf "0x22 MOD_RST_CTRL:  0x%02x\n" $(sudo i2cget -y 1 0x3b 0x22)
echo ""
echo "I2S Control:"
printf "0x30 I2S_CTRL:      0x%02x\n" $(sudo i2cget -y 1 0x3b 0x30)
printf "0x31 I2S_BCLK_CTRL: 0x%02x\n" $(sudo i2cget -y 1 0x3b 0x31)
printf "0x32 I2S_LRCK_CTRL1:0x%02x\n" $(sudo i2cget -y 1 0x3b 0x32)
printf "0x33 I2S_LRCK_CTRL2:0x%02x\n" $(sudo i2cget -y 1 0x3b 0x33)
printf "0x34 I2S_FMT_CTRL1: 0x%02x\n" $(sudo i2cget -y 1 0x3b 0x34)
printf "0x35 I2S_FMT_CTRL2: 0x%02x\n" $(sudo i2cget -y 1 0x3b 0x35)
printf "0x36 I2S_FMT_CTRL3: 0x%02x\n" $(sudo i2cget -y 1 0x3b 0x36)
echo ""
echo "ADC Control:"
printf "0x60 ADC1_CTRL1:    0x%02x\n" $(sudo i2cget -y 1 0x3b 0x60)
printf "0x61 ADC1_CTRL2:    0x%02x\n" $(sudo i2cget -y 1 0x3b 0x61)
printf "0x62 ADC1_CTRL3:    0x%02x\n" $(sudo i2cget -y 1 0x3b 0x62)
printf "0x63 ADC2_CTRL1:    0x%02x\n" $(sudo i2cget -y 1 0x3b 0x63)
printf "0x64 ADC2_CTRL2:    0x%02x\n" $(sudo i2cget -y 1 0x3b 0x64)
printf "0x65 ADC2_CTRL3:    0x%02x\n" $(sudo i2cget -y 1 0x3b 0x65)
printf "0x66 ADC3_CTRL1:    0x%02x\n" $(sudo i2cget -y 1 0x3b 0x66)
printf "0x67 ADC3_CTRL2:    0x%02x\n" $(sudo i2cget -y 1 0x3b 0x67)
printf "0x68 ADC3_CTRL3:    0x%02x\n" $(sudo i2cget -y 1 0x3b 0x68)
printf "0x69 ADC4_CTRL1:    0x%02x\n" $(sudo i2cget -y 1 0x3b 0x69)
printf "0x6a ADC4_CTRL2:    0x%02x\n" $(sudo i2cget -y 1 0x3b 0x6a)
printf "0x6b ADC4_CTRL3:    0x%02x\n" $(sudo i2cget -y 1 0x3b 0x6b)
echo ""
echo "=== Check PLL_LOCKED bit in PLL_CTRL1 (bit 2) ==="
PLL_CTRL1=$(sudo i2cget -y 1 0x3b 0x10)
if (( (PLL_CTRL1 & 0x04) != 0 )); then
    echo "✓ PLL is LOCKED"
else
    echo "✗ PLL is NOT locked"
fi
