#\!/bin/bash
# Check PLL configuration registers

echo "=== Checking PLL Configuration ==="
echo ""
echo "Expected for 2.048MHz -> 24.576MHz:"
echo "  M1=0, M2=0, N=240 (0xF0), K1=9, K2=1"
echo ""

PLL_CTRL2=$(sudo i2cget -y 1 0x3b 0x11)
PLL_CTRL3=$(sudo i2cget -y 1 0x3b 0x12)
PLL_CTRL4=$(sudo i2cget -y 1 0x3b 0x13)
PLL_CTRL5=$(sudo i2cget -y 1 0x3b 0x14)

echo "Actual register values:"
printf "0x11 PLL_CTRL2 (M1/M2): 0x%02x\n" $PLL_CTRL2
printf "0x12 PLL_CTRL3 (N_MSB): 0x%02x\n" $PLL_CTRL3
printf "0x13 PLL_CTRL4 (N_LSB): 0x%02x\n" $PLL_CTRL4
printf "0x14 PLL_CTRL5 (K1/K2): 0x%02x\n" $PLL_CTRL5
echo ""

# Decode values
M1=$(( (PLL_CTRL2 >> 1) & 0x1F ))
M2=$(( PLL_CTRL2 & 0x01 ))
N_MSB=$(( PLL_CTRL3 & 0x03 ))
N_LSB=$PLL_CTRL4
N=$(( (N_MSB << 8) | N_LSB ))
K1=$(( (PLL_CTRL5 >> 1) & 0x1F ))
K2=$(( PLL_CTRL5 & 0x01 ))

echo "Decoded values:"
echo "  M1 = $M1"
echo "  M2 = $M2"
echo "  N  = $N (0x$(printf '%x' $N))"
echo "  K1 = $K1"
echo "  K2 = $K2"
echo ""

# Calculate frequency
# FOUT = (FIN * N) / [(M1+1) * (M2+1) * (K1+1) * (K2+1)]
# FIN = 2048000, expected FOUT = 24576000
FIN=2048000
FOUT=$(( (FIN * N) / ((M1 + 1) * (M2 + 1) * (K1 + 1) * (K2 + 1)) ))
echo "Calculated output frequency: $FOUT Hz (expected: 24576000 Hz)"

if [ $FOUT -eq 24576000 ]; then
    echo "✓ PLL configuration is CORRECT"
else
    echo "✗ PLL configuration is WRONG\!"
fi
