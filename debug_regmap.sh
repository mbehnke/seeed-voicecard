#!/bin/bash

# =============================================
# AC108 Regmap Debug Script
# Check if regcache is blocking I2C access
# =============================================

echo "=== AC108 Regmap / Regcache Debug ==="
echo ""

# Check if device has regmap entry
echo "1. Checking regmap configuration..."
find /sys/class/regmap -name "*ac108*" 2>/dev/null && echo "   ✓ AC108 Regmap device found" || echo "   ! No AC108 Regmap found in sysfs"

echo ""
echo "2. Checking AC108 regcache status..."
for dev in $(find /sys -name "*ac108*" -o -name "*ac10x*" 2>/dev/null | head -10); do
    echo "   Device: $dev"
    if [ -f "$dev/cache_only" ]; then
        echo "   Cache-only: $(cat $dev/cache_only)"
    fi
    if [ -f "$dev/cache_sync" ]; then
        echo "   Cache-sync: $(cat $dev/cache_sync)"
    fi
done

echo ""
echo "3. Checking kernel codec status..."
dmesg | grep -i "ac108\|regmap" | tail -10

echo ""
echo "4. Testing regmap via debugfs..."
if [ -d /sys/kernel/debug/regmap ]; then
    echo "   Regmap debugfs entries:"
    ls -la /sys/kernel/debug/regmap/ 2>/dev/null | grep -E "ac108|ac10x" || echo "   (No AC108 entries)"
fi

echo ""
echo "5. Checking if regcache_bypass is disabled..."
if [ -f /sys/module/regmap/parameters/regcache_bypass ]; then
    BYPASS=$(cat /sys/module/regmap/parameters/regcache_bypass)
    echo "   regcache_bypass: $BYPASS (0=cache enabled, 1=bypass enabled)"
fi

echo ""
echo "6. Testing direct I2C write/read (may fail silently)..."
# Try to write and read AC108 register directly
RESULT=$(sudo i2cget -y 1 0x3b 0x00 2>&1)
if echo "$RESULT" | grep -q "0x"; then
    echo "   ✓ Direct I2C read succeeded: $RESULT"
else
    echo "   ✗ Direct I2C read failed: $RESULT"
fi

echo ""
echo "7. Checking for regmap bypass workaround..."
# Try to enable regcache bypass for debugging
if [ -f /sys/module/regmap_core/parameters/cache_bypass ]; then
    echo "   cache_bypass parameter found, attempting to enable..."
    # Note: This would require root
fi

echo ""
echo "=== Analysis ==="
echo "If regcache is in 'cache_only' mode, the hardware isn't actually being accessed."
echo "The driver reads/writes to an in-memory cache instead of the I2C bus."
echo ""
echo "Possible fixes:"
echo "1. Check ac108.c startup() function - verify regcache is disabled"
echo "2. Look for regcache_mark_dirty/regcache_sync calls"
echo "3. Ensure regmap operations include bypass flags when needed"
