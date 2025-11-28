# Microsoft Defender for Endpoint - Server Onboarding Script

## Overview
This PowerShell script (`New-ServerOnboarding.ps1`) automates the onboarding of Windows Servers (2019 and above, including Server Core) to Microsoft Defender for Endpoint with comprehensive prerequisite checking and interactive remediation. The script is **location-independent** and can be run from any directory.

## Features

- **Comprehensive prerequisite checks** - OS version, disk space, services, connectivity, Windows Updates, Group Policy
- **Intelligent session tracking** - Complete summaries on any exit with detailed action tracking and exportable reports
- **Interactive remediation** - Automatic fixes for common issues with Windows Update integration
- **Flexible package management** - Location-independent with auto-discovery of .cmd, folder, or .zip formats
- **Complete lifecycle support** - Onboarding, offboarding, and re-onboarding with service management
- **Enterprise-ready** - Server Core support, Windows Server 2019/2022/2025, graceful interruption handling

## Quick Start

### Prerequisites
- Windows Server 2019, 2022, or 2025 (Full or Server Core)
- PowerShell 5.1 or higher
- Administrator privileges
- Internet connectivity

### Installation

1. **Download** the script to any location on your server
2. **Run as Administrator**:
   ```powershell
   .\New-ServerOnboarding.ps1
   ```
3. **Follow the prompts** - the script guides you through everything

### If You Don't Have the Onboarding Package

**Option 1: Let the script guide you**
- Run the script
- Choose option **2** when prompted
- Follow the on-screen instructions to download from the portal

**Option 2: Download it manually first**
- Go to: [Microsoft Defender Portal](https://security.microsoft.com/securitysettings/endpoints/onboarding)
- Select **Windows Server 2019, 2022, and 2025**
- Choose **Local Script** deployment method
- Download and place in any directory
- Run the script from that directory (or provide the path when asked)

### What Happens During Onboarding

1. **Welcome & Confirmation** - Introduction and prerequisite overview
2. **Automated Checks** - 13 comprehensive validation tests
3. **Third-Party AV Detection** - Checks for existing antivirus
4. **Windows Updates** - Optional installation of available updates  
5. **Readiness Report** - Summary with pass/fail status
6. **Interactive Remediation** - Automatic fixes for common issues (if needed)
7. **Signature Update** - Optional Defender signature refresh
8. **Onboarding** - Execution of MDE onboarding script
9. **Verification** - Post-onboarding status check
10. **Session Summary** - Complete report of all actions taken and changes made
11. **Next Steps** - Testing guidance and portal links

### Session Tracking & Exit Safety

**No matter when or how you exit the script, you'll always see:**
- ✅ **What was accomplished** during your session
- ✅ **What changes were made** to your system  
- ✅ **Which checks passed/failed**
- ✅ **Clear next steps** based on your situation
- ✅ **Log file locations** for detailed troubleshooting

**Exit scenarios handled:**
- User cancellation at any prompt
- Prerequisite failures
- Successful completion
- Script interruption (Ctrl+C)
- System reboots
- Onboarding/offboarding processes

## Post-Onboarding

### Verification
- Server appears in MDE portal within **5-30 minutes**
- Check status: [Microsoft 365 Defender Portal](https://security.microsoft.com/machines)

### Run a Detection Test
```powershell
powershell.exe -NoExit -ExecutionPolicy Bypass -WindowStyle Hidden $ErrorActionPreference = 'silentlycontinue';(New-Object System.Net.WebClient).DownloadFile('http://127.0.0.1/1.exe', 'C:\test-MDATP-test\invoice.exe');Start-Process 'C:\test-MDATP-test\invoice.exe'
```
This triggers a test alert in the MDE portal to confirm protection is active.

### Output Files
- **Log File**: `MDE_Onboarding_YYYYMMDD_HHMMSS.log` - All actions and results with timestamps
- **Report File**: `MDE_Readiness_Report_YYYYMMDD_HHMMSS.txt` - Complete prerequisite check results
- **Session Summary**: Displayed on-screen every time the script exits (no separate file needed)

## Troubleshooting

### Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| **Internet connectivity failures** | Configure firewall to allow MDE endpoints ([Documentation](https://docs.microsoft.com/en-us/microsoft-365/security/defender-endpoint/configure-proxy-internet)) |
| **Defender disabled by Group Policy** | Contact domain administrator to modify GPO: `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\DisableAntiSpyware` |
| **Onboarding package not found** | Script will prompt to provide path or download from portal - accepts .cmd, folder, or .zip |
| **Insufficient disk space** | Free up space (minimum 5 GB required) or extend volume |
| **Service startup failures** | Remove conflicting software or repair: `DISM /Online /Cleanup-Image /RestoreHealth` |
| **Windows Update failures** | Reset update components or start service manually |
| **Server Core browser issues** | Script automatically detects Server Core and shows URL instead of launching browser |

### Getting Help
1. **Review the session summary** displayed when the script exits - it shows exactly what happened
2. Check the generated log files in the script directory
3. Review the readiness report for specific issues
4. Consult [Microsoft MDE Documentation](https://docs.microsoft.com/en-us/microsoft-365/security/defender-endpoint/)
5. Contact your security administrator

## Technical Requirements

### Supported Platforms

| OS Version | Status | Minimum Build | Notes |
|------------|--------|---------------|-------|
| Windows Server 2019 | ✅ Supported | 17763 | Full & Core |
| Windows Server 2022 | ✅ Supported | 20348 | Full & Core |
| Windows Server 2025 | ✅ Supported | Latest | Full & Core |

### Network Requirements
- `winatp-gw-cus.microsoft.com` - DNS + TCP port 443
- `security.microsoft.com` - DNS + TCP port 443  
- Windows Update endpoints (for update functionality)

### Required Services
- **WinDefend** - Windows Defender Antivirus Service
- **Sense** - Windows Defender ATP Service
- **WdNisSvc** - Network Inspection Service (optional)

### Security Notes
- ✅ Administrator privileges required
- ✅ All actions logged for audit trails
- ✅ No credentials stored or transmitted
- ✅ Input validation prevents injection attacks
- ✅ Network endpoints validated before connections
- ✅ Updates installed from official Microsoft servers only

## Additional Resources

- [MDE Documentation](https://docs.microsoft.com/en-us/microsoft-365/security/defender-endpoint/) - Official Microsoft documentation
- [Onboarding Methods](https://docs.microsoft.com/en-us/microsoft-365/security/defender-endpoint/onboard-configure) - Alternative deployment options
- [Network Configuration](https://docs.microsoft.com/en-us/microsoft-365/security/defender-endpoint/configure-proxy-internet) - Firewall and proxy setup
- [Troubleshooting Guide](https://docs.microsoft.com/en-us/microsoft-365/security/defender-endpoint/troubleshoot-onboarding) - Official troubleshooting steps

---

## Version History

### v1.0 (November 27, 2025)

**Complete automation solution for MDE server onboarding**

**Core Features:**
- Comprehensive prerequisite validation
- Comprehensive session summaries shown on any exit (successful, cancelled, failed, or interrupted)
- Real-time action tracking of all system modifications and configuration changes
- Smart exit handling - graceful summary display regardless of exit method (Ctrl+C, user cancellation, etc.)
- Location-independent package handling - works from any directory
- Auto-discovery of onboarding/offboarding packages
- Support for .cmd files, folders, and .zip archives
- Interactive remediation assistant for common issues
- Server Core full support with automatic browser-skip detection
- Windows Update integration with automatic installation
- Third-party antivirus detection and passive mode configuration
- Offboarding capability for already-onboarded servers
- Detailed change reporting - registry modifications, service changes, Windows Updates installed
- Session duration tracking and phase monitoring

**User Experience:**
- Clear step-by-step instructions with visual feedback
- Color-coded console output for easy reading
- Comprehensive logging and exportable reports
- Smart reboot handling for Windows Updates
- Professional summary display with color-coded status indicators
- Actionable next steps based on session outcome
- Complete transparency of system modifications
- No hard-coded paths or directory structure requirements
- Graceful error handling and user-friendly prompts

**Supported Platforms:**
- Windows Server 2019, 2022, and 2025
- Full and Server Core installations
- All service pack levels and build numbers (Build 17763+)

---

For issues or questions, check the generated log files and readiness reports, or consult the [Microsoft MDE Documentation](https://docs.microsoft.com/en-us/microsoft-365/security/defender-endpoint/).

