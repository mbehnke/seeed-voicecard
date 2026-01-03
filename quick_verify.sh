#!/bin/bash
#
# AC108 Regcache Fix - Quick Verification Script
# Validates that the I2C communication fix is properly installed
# Usage: sudo ./quick_verify.sh
#

set -e

COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${COLOR_BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${COLOR_BLUE}║       AC108 REGCACHE FIX - QUICK VERIFICATION              ║${NC}"
echo -e "${COLOR_BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# Test 1: Check if modules are loaded
echo -e "${COLOR_BLUE}[1/5]${NC} Checking if AC108 modules are loaded..."
if lsmod | grep -q ac108; then
    echo -e "${COLOR_GREEN}✅ PASS${NC}: snd_soc_ac108 module loaded"
    ((PASS_COUNT++))
else
    echo -e "${COLOR_YELLOW}⚠️  WARN${NC}: snd_soc_ac108 module NOT loaded (may need reboot or modprobe)"
    ((WARN_COUNT++))
fi

# Test 2: Check I2C device accessibility
echo ""
echo -e "${COLOR_BLUE}[2/5]${NC} Checking I2C device accessibility..."
I2C_STATUS=$(sudo i2cdetect -y 1 2>/dev/null | grep -o "3b\|UU" | head -1 || echo "MISSING")

if [ "$I2C_STATUS" = "3b" ]; then
    echo -e "${COLOR_GREEN}✅ PASS${NC}: Device shows '3b' (accessible)"
    ((PASS_COUNT++))
elif [ "$I2C_STATUS" = "UU" ]; then
    echo -e "${COLOR_RED}❌ FAIL${NC}: Device shows 'UU' (LOCKED - regcache fix not working)"
    ((FAIL_COUNT++))
else
    echo -e "${COLOR_RED}❌ FAIL${NC}: Device not detected at 0x3b"
    ((FAIL_COUNT++))
fi

# Test 3: Check register read functionality
echo ""
echo -e "${COLOR_BLUE}[3/5]${NC} Checking register read functionality..."
REG_READ=$(sudo i2cget -y 1 0x3b 0x21 w 2>/dev/null || echo "ERROR")

if [ "$REG_READ" != "ERROR" ] && [ ! -z "$REG_READ" ]; then
    echo -e "${COLOR_GREEN}✅ PASS${NC}: Register read successful (MOD_CLK_EN = $REG_READ)"
    ((PASS_COUNT++))
else
    echo -e "${COLOR_RED}❌ FAIL${NC}: Register read failed (possible regcache cache-only issue)"
    ((FAIL_COUNT++))
fi

# Test 4: Check kernel startup logs
echo ""
echo -e "${COLOR_BLUE}[4/5]${NC} Checking kernel startup logs..."
if sudo dmesg | grep -q "ac108:.*✅ COMPLETE"; then
    echo -e "${COLOR_GREEN}✅ PASS${NC}: Startup sequence completed successfully"
    ((PASS_COUNT++))
elif sudo dmesg | grep -q "ac108:.*ac108_audio_startup"; then
    echo -e "${COLOR_YELLOW}⚠️  WARN${NC}: Startup function called but may not be complete"
    ((WARN_COUNT++))
else
    echo -e "${COLOR_RED}❌ FAIL${NC}: No AC108 startup logs found (modules may not have loaded)"
    ((FAIL_COUNT++))
fi

# Test 5: Check ALSA card registration
echo ""
echo -e "${COLOR_BLUE}[5/5]${NC} Checking ALSA sound card registration..."
if cat /proc/asound/cards 2>/dev/null | grep -q "seeed"; then
    echo -e "${COLOR_GREEN}✅ PASS${NC}: seeed-voicecard sound card registered"
    ((PASS_COUNT++))
else
    echo -e "${COLOR_YELLOW}⚠️  WARN${NC}: seeed-voicecard NOT registered (separate ALSA issue)"
    ((WARN_COUNT++))
fi

# Summary
echo ""
echo -e "${COLOR_BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${COLOR_BLUE}║                    VERIFICATION SUMMARY                   ║${NC}"
echo -e "${COLOR_BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Results:"
echo -e "  ${COLOR_GREEN}✅ PASS${NC}: $PASS_COUNT/5"
echo -e "  ${COLOR_YELLOW}⚠️  WARN${NC}: $WARN_COUNT/5"
echo -e "  ${COLOR_RED}❌ FAIL${NC}: $FAIL_COUNT/5"
echo ""

if [ $FAIL_COUNT -eq 0 ] && [ $WARN_COUNT -le 1 ]; then
    echo -e "${COLOR_GREEN}🟢 REGCACHE FIX STATUS: WORKING${NC}"
    echo ""
    echo "✅ I2C Communication: RESTORED"
    echo "✅ Device Accessible: YES"
    echo "✅ Register Access: WORKING"
    echo ""
    if [ $WARN_COUNT -eq 0 ]; then
        echo "⚠️  Note: ALSA card not yet registered (separate issue)"
    fi
    exit 0
elif [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${COLOR_YELLOW}🟡 REGCACHE FIX STATUS: PARTIALLY WORKING${NC}"
    echo ""
    echo "Some components working, but issues remain"
    exit 1
else
    echo -e "${COLOR_RED}🔴 REGCACHE FIX STATUS: NOT WORKING${NC}"
    echo ""
    echo "❌ I2C Communication: FAILED"
    echo "❌ Device Not Accessible"
    echo ""
    echo "Possible solutions:"
    echo "1. Check if modules are loaded: lsmod | grep ac108"
    echo "2. Rebuild modules: cd /home/adm_behnke/seeed-voicecard && make clean && make && sudo make install"
    echo "3. Reboot system: sudo reboot"
    echo "4. Check kernel logs: sudo dmesg | grep -i 'ac108\|error'"
    exit 2
fi
