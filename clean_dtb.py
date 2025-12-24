#!/usr/bin/env python3
import re

with open("bcm2712-rpi-5-b-original.dts", "r") as f:
    content = f.read()

# Remove seeed-voice-card properties (single lines)
content = re.sub(r'^\s+seeed-voice-card,.*$', '', content, flags=re.MULTILINE)

# Remove seeed-voice-card child nodes (multi-line blocks)
# Pattern: "seeed-voice-card,codec {" ... "}" or "seeed-voice-card,cpu {" ... "}"
def remove_node_blocks(text):
    lines = text.split('\n')
    result = []
    skip_depth = None
    current_depth = 0
    
    for line in lines:
        # Track indentation depth
        indent = len(line) - len(line.lstrip())
        
        # Check if this line starts a seeed-voice-card node
        if re.search(r'seeed-voice-card,(codec|cpu)\s*\{', line):
            skip_depth = indent
            current_depth = 1
            continue
        
        # If we're skipping, track brace depth
        if skip_depth is not None:
            current_depth += line.count('{')
            current_depth -= line.count('}')
            
            # When we close all braces, stop skipping
            if current_depth <= 0:
                skip_depth = None
            continue
        
        result.append(line)
    
    return '\n'.join(result)

content = remove_node_blocks(content)

# Remove empty lines
content = re.sub(r'\n\s*\n\s*\n', '\n\n', content)

with open("bcm2712-rpi-5-b-cleaned.dts", "w") as f:
    f.write(content)

print("✅ DTB cleaned")
