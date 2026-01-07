#!/bin/bash
# Quick Build Script für verschiedene RP5-Lösungswege
# 
# Verwendung:
#   ./build_solution.sh A    # Lösungsweg A: 2-Kanal-Workaround
#   ./build_solution.sh B    # Lösungsweg B: TDM-Slots
#   ./build_solution.sh default  # Standard ohne RP5-Hacks

set -e

SOLUTION="$1"

if [ -z "$SOLUTION" ]; then
    echo "Verwendung: $0 <A|B|default>"
    echo ""
    echo "Verfügbare Lösungswege:"
    echo "  A       = 2-Kanal-Workaround (stabil, nur 2 Mics)"
    echo "  B       = TDM-Slot-Programmierung (experimentell, 4 Mics)"
    echo "  default = Standard I2S (keine RP5-Anpassungen)"
    exit 1
fi

case "$SOLUTION" in
    A|a)
        echo "=== Building Solution A: 2-Channel Workaround ==="
        CFLAGS="-DRP5_2CH_WORKAROUND"
        ;;
    B|b)
        echo "=== Building Solution B: TDM Slots ==="
        CFLAGS="-DRP5_TDM_SLOTS"
        ;;
    default|DEFAULT)
        echo "=== Building Default (no RP5 hacks) ==="
        CFLAGS=""
        ;;
    *)
        echo "Unbekannter Lösungsweg: $SOLUTION"
        exit 1
        ;;
esac

# Clean previous build
make clean

# Build with selected solution
echo "Compiling with: $CFLAGS"
make EXTRA_CFLAGS="$CFLAGS" -j4

# Install
echo ""
read -p "Module installieren? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo make install
    sudo depmod -a
    echo ""
    echo "Module installiert. Zum Neuladen:"
    echo "  sudo rmmod snd_soc_seeed_voicecard snd_soc_ac108"
    echo "  sudo modprobe snd_soc_ac108 && sudo modprobe snd_soc_seeed_voicecard"
    echo ""
    echo "Oder Reboot für sauberen Test:"
    echo "  sudo reboot"
fi
