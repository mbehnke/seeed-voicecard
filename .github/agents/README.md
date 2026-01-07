# GitHub Copilot Agents Configuration

This directory contains custom GitHub Copilot agent configurations for the Seeed Voicecard project.

## Available Agents

### 1. RaspberryPi5_SeeedVoicecard_Expert
**File:** [seeed.agents.md](seeed.agents.md)

**Purpose:** Primary expert assistant for Seeed Studio ReSpeaker 4-Mic Array driver development and integration on Raspberry Pi 5 with Kernel 6.x.

**Specializations:**
- Device Tree Overlay (DTO) configuration for RPi 5 (bcm2712)
- I2S interface compatibility and DSP_A vs I2S format resolution
- AC108 multi-channel ADC codec driver development
- Kernel module compilation and DKMS integration
- ALSA plugin development and audio routing
- Clock management (24MHz MCLK generation)
- I2C debugging and communication analysis

**Key Features:**
- Comprehensive testing workflows
- Quick reference commands
- Common issue troubleshooting table
- Development best practices
- Project-specific file locations

**Use When:**
- Implementing new driver features
- Debugging kernel module issues
- Modifying Device Tree overlays
- Working with AC108 codec registers
- Resolving audio routing problems

---

### 2. SeeedVoicecard_Diagnostics_Expert
**File:** [diagnostics.agents.md](diagnostics.agents.md)

**Purpose:** Specialized diagnostic agent for audio troubleshooting and automated analysis on Raspberry Pi 5.

**Specializations:**
- Systematic diagnostic methodology (hardware → kernel → ALSA → audio)
- Kernel log analysis and error code interpretation
- I2C communication verification
- ALSA configuration validation
- Machine-readable JSON report generation
- CI/CD pipeline integration

**Key Features:**
- Priority-ordered diagnostic checks
- Error code interpretation table
- JSON diagnostic output schema
- Automated script templates
- Pre/post-reboot checklists
- Common diagnostic scenarios

**Use When:**
- Troubleshooting audio capture issues
- Analyzing kernel logs for errors
- Creating diagnostic scripts
- Implementing automated testing
- Generating CI/CD-compatible reports

---

### 3. SeeedVoicecard_Patch_Expert
**File:** [patch-management.agents.md](patch-management.agents.md)

**Purpose:** Patch management specialist for maintaining driver compatibility across multiple kernel versions.

**Specializations:**
- Kernel API evolution tracking (ASoC changes)
- Patch file creation and management
- DKMS integration and configuration
- Version-specific adaptation strategies
- Regression testing across kernel versions
- Upstream compatibility monitoring

**Key Features:**
- Kernel 5.x → 6.x API migration guide
- Patch naming conventions and organization
- Automated version detection logic
- Common patch scenarios with examples
- Regression test matrix
- Upstream submission guidelines

**Use When:**
- Adapting driver to new kernel versions
- Managing patches directory
- Resolving compilation errors after kernel upgrade
- Creating version-specific compatibility layers
- Planning upstream kernel submission

---

## Usage

### Local Testing
You can test these agents locally using the GitHub Copilot CLI:
```bash
# Install Copilot CLI (if not already installed)
gh extension install github/gh-copilot

# Test agent (requires GitHub authentication)
gh copilot --agent RaspberryPi5_SeeedVoicecard_Expert "How do I fix DSP_A format issues?"
```

### In VS Code
These agents are automatically available in VS Code when:
1. File is merged into the default repository branch
2. GitHub Copilot extension is installed and authenticated
3. Repository is opened in VS Code workspace

Invoke agents through:
- Chat panel: `@RaspberryPi5_SeeedVoicecard_Expert`
- Inline completions (context-aware)

---

## Agent Configuration Format

Both agents follow the GitHub Copilot custom agent schema:

```yaml
name: AgentName
description: >
  Brief description of agent purpose and specializations
instructions: |
  Detailed instructions, guidelines, and reference material
```

### Key Components

1. **Name**: Unique identifier for the agent
2. **Description**: Short summary shown in agent selection UI
3. **Instructions**: Comprehensive guidelines including:
   - Core competencies and specializations
   - Technical specifications and constraints
   - Command reference and examples
   - Troubleshooting guides
   - Best practices and workflows
   - Response format guidelines

---

## Integration with Project

### Copilot Instructions
The main [copilot-instructions.md](../copilot-instructions.md) provides project-wide context, while these agents offer specialized expertise.

**Hierarchy:**
```
copilot-instructions.md (Project context)
├── seeed.agents.md (Driver development)
└── diagnostics.agents.md (Troubleshooting)
```

### Diagnostic Scripts
These agents inform the design of diagnostic scripts:
- [diagnose_audio.sh](../../diagnose_audio.sh)
- [diagnose_audio_2.sh](../../diagnose_audio_2.sh)
- [early_boot_capture.sh](../../early_boot_capture.sh)
- [final_check.sh](../../final_check.sh)

All scripts generate JSON output compatible with the schema defined in `diagnostics.agents.md`.

---

## JSON Output Schema

Both agents emphasize machine-readable JSON outputs for automation:

```json
{
  "status": "success|error|warning|partial",
  "error_code": 0,
  "timestamp": "2025-12-24T15:00:00Z",
  "key_metrics": {
    "hardware": { "i2c_device_detected": true },
    "kernel": { "modules_loaded": ["snd_soc_ac108"], "error_count": 0 },
    "device_tree": { "sound_node_present": true, "format": "i2s" },
    "alsa": { "card_name": "seeed4micvoicec", "device_count": 1 },
    "audio": { "capture_working": true, "channels": 4, "non_zero_samples": true }
  },
  "root_cause": "Technical explanation",
  "required_actions": ["command1", "command2"],
  "warnings": []
}
```

**Benefits:**
- Scriptable parsing with `jq`
- CI/CD pipeline integration
- Automated regression testing
- Historical trend analysis
- Log aggregation compatibility

---

## Maintenance

### Updating Agents
When modifying agent configurations:
1. Test changes locally with Copilot CLI
2. Update this README if adding new agents
3. Ensure JSON schemas remain consistent
4. Update diagnostic scripts to match new schemas
5. Commit changes to default branch

### Adding New Agents
To add specialized agents:
1. Create `[name].agents.md` in this directory
2. Follow the schema format (name, description, instructions)
3. Document in this README
4. Link to related scripts/documentation
5. Test with Copilot CLI before merging

---

## References

- [GitHub Copilot Custom Agents Documentation](https://gh.io/customagents/config)
- [Copilot CLI](https://gh.io/customagents/cli)
- [Project Instructions](../copilot-instructions.md)
- [Troubleshooting Guide](../../TROUBLESHOOTING.md)
- [RPi 5 Installation Guide](../../PI5-INSTALLATION.md)

---

## Quick Start Examples

### Example 1: Fixing I2S Format Issues
```
@RaspberryPi5_SeeedVoicecard_Expert I'm getting "error at snd_soc_dai_set_fmt" 
in dmesg. How do I fix the Device Tree overlay?
```

**Expected Response:**
- Diagnoses DSP_A incompatibility on RPi 5
- Provides DTS snippet with `format = "i2s"`
- Explains compilation and deployment steps
- Offers verification commands

### Example 2: Diagnosing Audio Capture
```
@SeeedVoicecard_Diagnostics_Expert Audio recording produces zero samples. 
Generate a diagnostic report.
```

**Expected Response:**
- Systematic check sequence (I2C → kernel → ALSA → audio)
- Specific commands to run for each layer
- JSON output template
- Likely root causes with fixes
- Verification procedure

### Example 3: Managing Kernel Patches
```
@SeeedVoicecard_Patch_Expert I upgraded to Kernel 6.13 and the driver fails to compile
with "implicit function declaration" errors. How do I create a patch?
```

**Expected Response:**
- Identifies changed API functions
- Shows how to detect kernel version
- Provides patch template with #if LINUX_VERSION_CODE guards
- Explains testing procedure
- Updates install.sh version detection logic

---

## Changelog

### 2025-12-24
- **Initial Creation**
  - Created `seeed.agents.md` (RaspberryPi5_SeeedVoicecard_Expert)
  - Created `diagnostics.agents.md` (SeeedVoicecard_Diagnostics_Expert)
  - Created `patch-management.agents.md` (SeeedVoicecard_Patch_Expert)
  - Added comprehensive instructions for RPi 5 Kernel 6.x
  - Documented JSON schema for diagnostic outputs
  - Integrated with existing diagnostic scripts
  - Added patch management workflows and version detection

### Future Enhancements
- [ ] Agent for ALSA plugin development (`ac108_plugin/`)
- [ ] Agent for Device Tree overlay comparison/diff
- [ ] Agent for kernel log parsing and visualization
- [ ] Integration with automated test suite
- [ ] Performance profiling agent (latency, jitter analysis)
- [ ] CI/CD pipeline agent for automated testing
- [ ] Documentation generator agent
