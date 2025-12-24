#!/usr/bin/env python3
import re

with open("bcm2712-rpi-5-b-original.dts", "r") as f:
    lines = f.readlines()

output = []
in_sound_node = False
in_seeed_child = False
child_depth = 0
sound_indent = 0

i = 0
while i < len(lines):
    line = lines[i]
    
    # Detect sound node start
    if re.match(r'\s+sound\s*\{', line):
        in_sound_node = True
        sound_indent = len(line) - len(line.lstrip())
        output.append(line)
        i += 1
        continue
    
    # Inside sound node
    if in_sound_node:
        current_indent = len(line) - len(line.lstrip())
        
        # Detect seeed-voice-card child node
        if re.search(r'seeed-voice-card,(codec|cpu)\s*\{', line):
            in_seeed_child = True
            child_depth = 1
            i += 1
            continue
        
        # Skip lines inside seeed-voice-card child
        if in_seeed_child:
            child_depth += line.count('{')
            child_depth -= line.count('}')
            if child_depth <= 0:
                in_seeed_child = False
            i += 1
            continue
        
        # Skip seeed-voice-card properties
        if re.match(r'\s+seeed-voice-card,', line):
            i += 1
            continue
        
        # Detect end of sound node
        if current_indent == sound_indent and '}' in line:
            in_sound_node = False
        
        output.append(line)
    else:
        output.append(line)
    
    i += 1

with open("bcm2712-rpi-5-b-cleaned.dts", "w") as f:
    f.writelines(output)

print("✅ Sound node fixed")
