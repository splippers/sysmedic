#!/bin/bash
# SysMedic physical bypass detector
# Runs at boot: hold Left Shift + Right Shift simultaneously for 2 seconds

FLAG="/tmp/sysmedic-bypass.flag"
rm -f "$FLAG"

echo "  SysMedic: press Left+Right Shift for bypass... (2s)"

# Read raw keyboard input for 2 seconds, check for shift keycodes
INPUT=$(timeout 2 showkey -s 2>/dev/null | grep -E "0x2a|0x36|0xaa|0xb6")
if [ $? -eq 0 ] || [ -n "$INPUT" ]; then
  # Left Shift = 0x2a/0xaa, Right Shift = 0x36/0xb6
  LEFT=$(echo "$INPUT" | grep -c "0x2a")
  RIGHT=$(echo "$INPUT" | grep -c "0x36")
  if [ "$LEFT" -gt 0 ] && [ "$RIGHT" -gt 0 ]; then
    date > "$FLAG"
    echo "  ✓ Bypass flag set (both shifts detected)"
  fi
fi
