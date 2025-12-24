#!/usr/bin/env python3
"""Remove TDM slot properties from simple-audio-card,cpu node in DTB."""

import re
import sys

def remove_tdm_properties(dts_content):
    """Remove dai-tdm-slot-* properties from simple-audio-card,cpu node."""
    
    # Pattern to match the entire simple-audio-card,cpu block
    # Find the block and remove TDM properties within it
    lines = dts_content.split('\n')
    result = []
    in_cpu_block = False
    brace_depth = 0
    
    for line in lines:
        # Check if we're entering the simple-audio-card,cpu block
        if 'simple-audio-card,cpu {' in line:
            in_cpu_block = True
            result.append(line)
            continue
        
        # If in cpu block, skip TDM property lines
        if in_cpu_block:
            # Track brace depth
            brace_depth += line.count('{') - line.count('}')
            
            # Skip TDM properties
            if 'dai-tdm-slot-' in line:
                continue
            
            result.append(line)
            
            # Exit block when braces close
            if brace_depth <= 0:
                in_cpu_block = False
                brace_depth = 0
        else:
            result.append(line)
    
    return '\n'.join(result)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} input.dts output.dts")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    # Read input DTS
    with open(input_file, 'r') as f:
        content = f.read()
    
    # Remove TDM properties
    cleaned = remove_tdm_properties(content)
    
    # Write output DTS
    with open(output_file, 'w') as f:
        f.write(cleaned)
    
    print(f"✓ Removed TDM properties from {input_file} → {output_file}")
