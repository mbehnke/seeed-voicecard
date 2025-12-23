#!/bin/bash
OUT="/home/adm_behnke/seeed-voicecard/logs/early_boot_$(date +%Y%m%d_%H%M%S).log"
{
  echo "=== dmesg ac108/seeed ==="
  dmesg | grep -Ei "ac108|seeed|i2s|asoc" | tail -200
  echo
  echo "=== arecord -l ==="
  arecord -l
  echo
  echo "=== amixer controls ==="
  amixer -c 0 scontrols | head -20
} > "$OUT"
