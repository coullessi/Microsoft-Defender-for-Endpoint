<#
.SYNOPSIS
    Automated Microsoft Defender for Endpoint (MDE) Onboarding Script for Windows Servers

.DESCRIPTION
    This script automates the onboarding process for Windows Server 2019 and above (including Server Core)
    to Microsoft Defender for Endpoint. It performs comprehensive prerequisite checks and guides users
    through the onboarding process interactively.

.NOTES
    Author: MDE Automation
    Date: November 21, 2025
    Requires: PowerShell 5.1 or higher, Administrator privileges
    Supported: Windows Server 2019, 2022, and above (Full and Core installations)

.EXAMPLE
    .\New-ServerOnboarding.ps1
    
    Runs the MDE onboarding script interactively with comprehensive prerequisite checks
    and guided remediation.
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param()

# Set up trap to handle script interruption or unexpected exits
trap {
    Write-Host "`nScript interrupted or error occurred." -ForegroundColor Yellow
    if ($script:SessionSummary) {
        $script:SessionSummary.OnboardingStatus = "Interrupted"
        Add-SessionAction -Action "Script Interrupted" -Details "Script was interrupted or encountered an error: $($_.Exception.Message)" -Category "System"
        Show-SessionSummary -ExitReason "Script interrupted or error occurred"
    }
    Write-Host "Press any key to exit...`n" -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Script variables
$script:LogFile = "$(Get-Location)\MDE_Onboarding_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:OnboardingScriptPath = $null  # Will be set dynamically when found
$script:PrerequisitesPassed = $true
$script:LogWriteErrorShown = $false
$script:DefenderServiceIssues = @()  # Will store critical service issues for remediation
$script:SessionSummary = @{
    StartTime = Get-Date
    ActionsPerformed = @()
    ChecksCompleted = @()
    ConfigurationChanges = @()
    ServicesModified = @()
    RegistryChanges = @()
    UpdatesInstalled = @()
    ScriptPhase = "Initialization"
    ExitReason = $null
    OnboardingStatus = "Not Started"
}

#region Helper Functions

function Test-IsServerCore {
    <#
    .SYNOPSIS
        Checks if the server is running Server Core (no GUI).
    .DESCRIPTION
        Returns true if the server is Server Core, false otherwise.
    #>
    try {
        $installType = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name InstallationType -ErrorAction SilentlyContinue).InstallationType
        return ($installType -eq 'Server Core')
    }
    catch {
        return $false
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level]: $Message"
    
    # Color coding for console output
    $color = switch ($Level) {
        'INFO'    { 'Cyan' }
        'WARNING' { 'Yellow' }
        'ERROR'   { 'Red' }
        'SUCCESS' { 'Green' }
        default   { 'White' }
    }
    
    Write-Host $logMessage -ForegroundColor $color
    
    # Write to log file with error handling for network paths
    try {
        # Use Out-File with -Append instead of Add-Content for better network path handling
        $logMessage | Out-File -FilePath $script:LogFile -Append -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # If logging fails, silently continue to avoid disrupting the script
        # Only show error on first failure
        if (-not $script:LogWriteErrorShown) {
            Write-Host "[WARNING] Unable to write to log file: $($_.Exception.Message)" -ForegroundColor Yellow
            $script:LogWriteErrorShown = $true
        }
    }
}

function Write-Banner {
    param([string]$Text)
    
    $border = "-" * 80
    Write-Host "`n$border" -ForegroundColor White
    Write-Host "  $Text" -ForegroundColor White
    Write-Host "$border`n" -ForegroundColor White
}

function Get-ObfuscatedOrgId {
    <#
    .SYNOPSIS
        Obfuscates an Organization ID by showing only the first 4 and last 4 characters.
    
    .DESCRIPTION
        Takes an Organization ID and returns a string showing the first 4 characters,
        asterisks for the middle portion, and the last 4 characters for security purposes.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$OrgId
    )
    
    if ([string]::IsNullOrWhiteSpace($OrgId)) {
        return $OrgId
    }
    
    if ($OrgId.Length -le 8) {
        # If OrgId is 8 characters or less, show first 4 and asterisks for the rest
        $firstPart = $OrgId.Substring(0, [Math]::Min(4, $OrgId.Length))
        $remainingLength = $OrgId.Length - $firstPart.Length
        return "$firstPart" + ("*" * $remainingLength)
    }
    else {
        # Show first 4, asterisks for middle, last 4
        $firstPart = $OrgId.Substring(0, 4)
        $lastPart = $OrgId.Substring($OrgId.Length - 4, 4)
        $middleLength = $OrgId.Length - 8
        return "$firstPart" + ("*" * $middleLength) + "$lastPart"
    }
}

function Get-UserConfirmation {
    <#
    .SYNOPSIS
        Prompts user for Yes/No confirmation with input validation and clear default indication.
    
    .DESCRIPTION
        Displays a Yes/No prompt and validates user input. Accepts Y/y/N/n, yes/no, and empty (default).
        Loops until valid input is received. Makes the default choice crystal clear to avoid confusion.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [bool]$DefaultYes = $true
    )
    
    # Make the default choice absolutely clear
    if ($DefaultYes) {
        $prompt = "$Message"
        $defaultChoice = "YES"
    }
    else {
        $prompt = "$Message"
        $defaultChoice = "NO"
    }
    
    while ($true) {
        Write-Host ""
        Write-Host "  $prompt" -ForegroundColor White
        Write-Host "  Press Enter for default ($defaultChoice), or type Y/Yes/N/No:" -ForegroundColor White
        $response = Read-Host "  Choice"
        
        # Trim whitespace and convert to lowercase for easier comparison
        $response = $response.Trim().ToLower()
        
        # Empty response uses default
        if ([string]::IsNullOrWhiteSpace($response)) {
            Write-Host "  Using default: $defaultChoice" -ForegroundColor Cyan
            return $DefaultYes
        }
        
        # Accept various forms of yes/no input
        if ($response -match '^(y|yes)$') {
            Write-Host "  You chose: YES" -ForegroundColor Green
            return $true
        }
        elseif ($response -match '^(n|no)$') {
            Write-Host "  You chose: NO" -ForegroundColor Yellow
            return $false
        }
        
        # Invalid input - prompt again
        Write-Host "  X Invalid input. Please enter 'Y', 'Yes', 'N', 'No', or press Enter for default ($defaultChoice)." -ForegroundColor Red
    }
}

function Test-InternetConnectivity {
    Write-Log "Testing internet connectivity..." -Level INFO
    
    # Test basic DNS and network connectivity first
    $endpoints = @(
        @{Name = "Microsoft (DNS)"; Host = "www.microsoft.com"; Port = 80; Required = $true},
        @{Name = "MDE Service (DNS)"; Host = "winatp-gw-cus.microsoft.com"; Port = 443; Required = $true},
        @{Name = "Security Intelligence"; Host = "go.microsoft.com"; Port = 443; Required = $true}
    )
    
    $allPassed = $true
    $useWebRequest = $true
    
    # First try basic TCP connectivity test (more reliable than web requests)
    foreach ($endpoint in $endpoints) {
        try {
            # Test DNS resolution first
            $null = [System.Net.Dns]::GetHostAddresses($endpoint.Host)
            Write-Log "$($endpoint.Name): DNS resolution successful" -Level SUCCESS
            
            # Test TCP connectivity
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connect = $tcpClient.BeginConnect($endpoint.Host, $endpoint.Port, $null, $null)
            $wait = $connect.AsyncWaitHandle.WaitOne(5000, $false)
            
            if ($wait) {
                try {
                    $tcpClient.EndConnect($connect)
                    Write-Log "$($endpoint.Name): TCP port $($endpoint.Port) is reachable" -Level SUCCESS
                }
                catch {
                    if ($endpoint.Required) {
                        Write-Log "$($endpoint.Name): TCP connection failed - $($_.Exception.Message)" -Level WARNING
                        Write-Log "This may be due to firewall/proxy settings but DNS works" -Level INFO
                    }
                }
            }
            else {
                if ($endpoint.Required) {
                    Write-Log "$($endpoint.Name): TCP connection timeout" -Level WARNING
                    Write-Log "This may be due to firewall/proxy settings but DNS works" -Level INFO
                }
            }
            
            $tcpClient.Close()
            $tcpClient.Dispose()
        }
        catch {
            if ($endpoint.Required) {
                Write-Log "$($endpoint.Name): DNS resolution failed - $($_.Exception.Message)" -Level ERROR
                Write-Log "Please check DNS settings and internet connectivity" -Level ERROR
                $allPassed = $false
                $useWebRequest = $false
            }
            else {
                Write-Log "$($endpoint.Name): Failed - $($_.Exception.Message)" -Level WARNING
            }
        }
    }
    
    # If DNS works, try web requests (optional - won't fail the check)
    if ($useWebRequest) {
        Write-Log "Testing HTTP/HTTPS connectivity (informational)..." -Level INFO
        
        $webEndpoints = @(
            @{Name = "Microsoft Update"; Url = "http://www.microsoft.com"},
            @{Name = "MDE Service HTTPS"; Url = "https://winatp-gw-cus.microsoft.com"}
        )
        
        foreach ($endpoint in $webEndpoints) {
            try {
                # Use system proxy settings
                $webRequest = [System.Net.WebRequest]::Create($endpoint.Url)
                $webRequest.Timeout = 10000
                $webRequest.Method = "HEAD"
                $webRequest.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
                $webRequest.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                
                $response = $webRequest.GetResponse()
                $response.Close()
                Write-Log "$($endpoint.Name): HTTP request successful" -Level SUCCESS
            }
            catch {
                Write-Log "$($endpoint.Name): HTTP request failed (may work during actual onboarding)" -Level WARNING
                Write-Log "Reason: $($_.Exception.Message)" -Level INFO
            }
        }
    }
    
    if ($allPassed) {
        Write-Log "Internet connectivity test passed (DNS resolution works)" -Level SUCCESS
    }
    else {
        Write-Log "Internet connectivity test failed (DNS resolution issues detected)" -Level ERROR
    }
    
    return $allPassed
}

function Test-OSVersion {
    Write-Log "Checking operating system version..." -Level INFO
    
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $productType = $os.ProductType
    
    Write-Log "OS: $($os.Caption)" -Level INFO
    Write-Log "Version: $($os.Version)" -Level INFO
    Write-Log "Build: $($os.BuildNumber)" -Level INFO
    
    # Check if Server Core
    $isServerCore = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name InstallationType -ErrorAction SilentlyContinue).InstallationType -eq 'Server Core'
    if ($isServerCore) {
        Write-Log "Installation Type: Server Core" -Level INFO
    }
    else {
        Write-Log "Installation Type: Server with Desktop Experience" -Level INFO
    }
    
    # Check if it's a server (ProductType: 2 = Domain Controller, 3 = Server)
    if ($productType -ne 2 -and $productType -ne 3) {
        Write-Log "This machine is not a Windows Server" -Level ERROR
        return $false
    }
    
    # Check for Windows Server 2019 or higher (Build 17763+)
    if ($os.BuildNumber -lt 17763) {
        Write-Log "Windows Server 2019 or higher is required (Build 17763+)" -Level ERROR
        Write-Log "Current build: $($os.BuildNumber)" -Level ERROR
        return $false
    }
    
    Write-Log "Operating system is supported" -Level SUCCESS
    return $true
}

function Test-DefenderService {
    Write-Log "Checking Windows Defender services..." -Level INFO
    
    $services = @(
        @{Name = "WinDefend"; DisplayName = "Windows Defender Antivirus Service"; Critical = $true},
        @{Name = "Sense"; DisplayName = "Windows Defender Advanced Threat Protection Service"; Critical = $true},
        @{Name = "WdNisSvc"; DisplayName = "Windows Defender Antivirus Network Inspection Service"; Critical = $true}
    )
    
    $allPassed = $true
    $criticalIssues = @()
    
    foreach ($svc in $services) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        
        if ($null -eq $service) {
            if ($svc.Critical) {
                Write-Log "$($svc.DisplayName) not found" -Level ERROR
                $criticalIssues += @{
                    Service = $svc
                    Issue = "NotFound"
                    Description = "Service is not installed on this system"
                }
                $allPassed = $false
            }
            else {
                Write-Log "$($svc.DisplayName) not found (Optional)" -Level WARNING
            }
        }
        else {
            # Check service status
            $statusSymbol = if ($service.Status -eq 'Running') { '' } else { '[!]' }
            $level = if ($service.Status -eq 'Running') { 'SUCCESS' } else { 'WARNING' }
            Write-Log "$statusSymbol $($svc.DisplayName): $($service.Status)" -Level $level
            
            # Check startup type
            $startType = $service.StartType
            Write-Log "Startup Type: $startType" -Level INFO
            
            # Check if service is disabled
            if ($startType -eq 'Disabled') {
                if ($svc.Critical) {
                    Write-Log "[X] Critical service is disabled" -Level ERROR
                    $criticalIssues += @{
                        Service = $svc
                        Issue = "Disabled"
                        Description = "Service startup type is set to Disabled"
                        ServiceObject = $service
                    }
                    $allPassed = $false
                }
                else {
                    Write-Log "[!] Optional service is disabled" -Level WARNING
                }
            }
            # Collect all issues for this service before attempting remediation
            $serviceIssues = @()
            
            # Check if critical service should be set to Automatic but isn't
            # Note: WdNisSvc (Network Inspection Service) is designed to run Manual and start on-demand
            if ($svc.Critical -and $startType -ne 'Automatic' -and $svc.Name -ne 'WdNisSvc') {
                $serviceIssues += @{
                    Service = $svc
                    Issue = "ManualStartup"
                    Description = "Service startup type should be Automatic but is currently $startType"
                    ServiceObject = $service
                }
            }
            
            # Check if critical service is not running
            if ($svc.Critical -and $service.Status -ne 'Running') {
                $serviceIssues += @{
                    Service = $svc
                    Issue = "Stopped"
                    Description = "Service is not running but should be (Status: $($service.Status))"
                    ServiceObject = $service
                }
            }
            
            # Report all issues for this service once
            if ($serviceIssues.Count -gt 0) {
                foreach ($issue in $serviceIssues) {
                    Write-Log "[!] $($issue.Description)" -Level WARNING
                }
                
                # Try immediate remediation if service is stopped
                $stoppedIssue = $serviceIssues | Where-Object { $_.Issue -eq "Stopped" }
                if ($stoppedIssue) {
                    Write-Log "Attempting to start critical service: $($svc.DisplayName)..." -Level INFO
                    try {
                        # Check if service can be started (not disabled)
                        if ($service.StartType -eq 'Disabled') {
                            Write-Log "Service is disabled - setting to Manual first..." -Level INFO
                            Set-Service -Name $svc.Name -StartupType Manual -ErrorAction Stop
                            # Remove the ManualStartup issue since we're handling it
                            $serviceIssues = $serviceIssues | Where-Object { $_.Issue -ne "ManualStartup" }
                        }
                        
                        Start-Service -Name $svc.Name -ErrorAction Stop
                        Write-Log "Service started successfully" -Level SUCCESS
                        
                        # Verify it's actually running
                        Start-Sleep -Seconds 3
                        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
                        if ($service -and $service.Status -eq 'Running') {
                            Write-Log "Service is now running and verified" -Level SUCCESS
                            Add-ConfigurationChange -Type "Service" -Description "Started service: $($svc.DisplayName)" -Location $svc.Name -Success $true
                            Add-SessionAction -Action "Service Started" -Details "$($svc.DisplayName) service started and verified" -Category "Service"
                            # Remove the Stopped issue since it's now resolved
                            $serviceIssues = $serviceIssues | Where-Object { $_.Issue -ne "Stopped" }
                        }
                        else {
                            Write-Log "[!] Service started but may not be stable (current status: $($service.Status))" -Level WARNING
                            Add-ConfigurationChange -Type "Service" -Description "Started service: $($svc.DisplayName) (unstable)" -Location $svc.Name -Success $false
                            $allPassed = $false
                        }
                    }
                    catch {
                        Write-Log "[X] Failed to start critical service $($svc.DisplayName): $($_.Exception.Message)" -Level ERROR
                        Add-ConfigurationChange -Type "Service" -Description "Failed to start service: $($svc.DisplayName)" -Location $svc.Name -Success $false
                        $allPassed = $false
                    }
                }
                
                # Add remaining unresolved issues to the critical issues list
                $criticalIssues += $serviceIssues
            }
        }
    }
    
    # If we have unresolved critical issues, report them
    if ($criticalIssues.Count -gt 0) {
        Write-Log "Found $($criticalIssues.Count) unresolved critical service issue(s):" -Level WARNING
        foreach ($issue in $criticalIssues) {
            Write-Log "$($issue.Service.DisplayName): $($issue.Description)" -Level ERROR
        }
        
        # Store issues for later remediation
        $script:DefenderServiceIssues = $criticalIssues
    }
    else {
        Write-Log "All critical Windows Defender services are properly configured" -Level SUCCESS
    }
    
    return $allPassed
}

function Repair-DefenderServices {
    <#
    .SYNOPSIS
        Attempts to repair Windows Defender services by starting them and setting them to automatic startup.
    #>
    Write-Log "Starting Windows Defender service repair process..." -Level INFO
    
    $services = @(
        @{Name = "WinDefend"; DisplayName = "Windows Defender Antivirus Service"; Critical = $true},
        @{Name = "Sense"; DisplayName = "Windows Defender Advanced Threat Protection Service"; Critical = $true},
        @{Name = "WdNisSvc"; DisplayName = "Windows Defender Antivirus Network Inspection Service"; Critical = $true},
        @{Name = "WdFilter"; DisplayName = "Microsoft Defender Antivirus Mini-Filter Driver"; Critical = $false},
        @{Name = "WdBoot"; DisplayName = "Microsoft Defender Antivirus Boot Driver"; Critical = $false},
        @{Name = "SecurityHealthService"; DisplayName = "Windows Security Service"; Critical = $false},
        @{Name = "wscsvc"; DisplayName = "Windows Security Center Service"; Critical = $false},
        @{Name = "Wecsvc"; DisplayName = "Windows Event Collector"; Critical = $false},
        @{Name = "WinRM"; DisplayName = "Windows Remote Management (WS-Management)"; Critical = $false}
    )
    
    $repairSuccess = $true
    $servicesRepaired = @()
    
    Write-Host ""
    Write-Host "  WINDOWS DEFENDER SERVICE REPAIR:" -ForegroundColor Yellow
    Write-Host "  ================================" -ForegroundColor Yellow
    Write-Host "  The following services will be checked and repaired:" -ForegroundColor White
    
    foreach ($svc in $services) {
        Write-Host "    - $($svc.DisplayName)" -ForegroundColor Cyan
    }
    
    Write-Host ""
    Write-Host "  Actions to be performed:" -ForegroundColor White
    Write-Host "    1. Check current service status and startup type" -ForegroundColor White
    Write-Host "    2. Set startup type to 'Automatic' if not already set" -ForegroundColor White
    Write-Host "    3. Start stopped services" -ForegroundColor White
    Write-Host "    4. Verify service is running and stable" -ForegroundColor White
    Write-Host ""
    
    if (-not (Get-UserConfirmation -Message "REPAIR: Proceed with Windows Defender service repair?" -DefaultYes $true)) {
        Write-Log "Service repair cancelled by user" -Level INFO
        return $false
    }
    
    Write-Host ""
    Write-Host "  Starting service repair process..." -ForegroundColor Cyan
    
    foreach ($svc in $services) {
        Write-Host ""
        Write-Host "  Processing: $($svc.DisplayName)" -ForegroundColor Yellow
        Write-Log "Processing service: $($svc.Name)" -Level INFO
        
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        
        if ($null -eq $service) {
            if ($svc.Critical) {
                Write-Host "    [X] Service not found - this is a critical issue" -ForegroundColor Red
                Write-Log "Critical service $($svc.Name) not found on system" -Level ERROR
                $repairSuccess = $false
            }
            else {
                Write-Host "    [!] Optional service not found - this is normal on some systems" -ForegroundColor Yellow
                Write-Log "Optional service $($svc.Name) not found (acceptable)" -Level WARNING
            }
            continue
        }
        
        Write-Host "    Current Status: $($service.Status)" -ForegroundColor $(if ($service.Status -eq 'Running') { 'Green' } else { 'Yellow' })
        Write-Host "    Current Startup Type: $($service.StartType)" -ForegroundColor $(if ($service.StartType -eq 'Automatic') { 'Green' } else { 'Yellow' })
        
        # Step 1: Fix startup type if needed (set to Automatic for most Defender services)
        # Note: WdNisSvc is designed to be Manual and starts on-demand
        $targetStartupType = if ($svc.Name -eq 'WdNisSvc') { 'Manual' } else { 'Automatic' }
        
        if ($service.StartType -ne $targetStartupType) {
            Write-Host "    [REPAIR] Setting startup type to $targetStartupType..." -ForegroundColor Cyan
            try {
                Set-Service -Name $svc.Name -StartupType $targetStartupType -ErrorAction Stop
                Write-Host "    [OK] Startup type set to $targetStartupType" -ForegroundColor Green
                Write-Log "Set startup type to $targetStartupType for $($svc.DisplayName)" -Level SUCCESS
                Add-ConfigurationChange -Type "Service" -Description "Set startup type to $targetStartupType`: $($svc.DisplayName)" -Location $svc.Name -Success $true
                Add-SessionAction -Action "Service Startup Type" -Details "$($svc.DisplayName) startup type set to $targetStartupType" -Category "Service"
                $servicesRepaired += "$($svc.DisplayName): Startup type set to $targetStartupType"
            }
            catch [System.Management.Automation.ActionPreferenceStopException] {
                $errorDetails = $_.Exception.InnerException.Message
                if ($errorDetails -match "Access is denied") {
                    Write-Host "    [X] Access denied - insufficient permissions to modify service startup type" -ForegroundColor Red
                    Write-Host "        Ensure you are running as Administrator" -ForegroundColor Yellow
                    Write-Log "Access denied when setting startup type for $($svc.DisplayName) - insufficient permissions" -Level ERROR
                }
                elseif ($errorDetails -match "service does not exist") {
                    Write-Host "    [X] Service registry entry is corrupted or missing" -ForegroundColor Red
                    Write-Host "        May require Windows Defender reinstallation" -ForegroundColor Yellow
                    Write-Log "Service registry entry missing for $($svc.DisplayName)" -Level ERROR
                }
                elseif ($errorDetails -match "handle is invalid") {
                    Write-Host "    [X] Service control manager handle is invalid" -ForegroundColor Red
                    Write-Host "        Service may be in a transitional state, try again in a moment" -ForegroundColor Yellow
                    Write-Log "Invalid service handle for $($svc.DisplayName)" -Level ERROR
                }
                else {
                    Write-Host "    [X] Failed to set startup type: $errorDetails" -ForegroundColor Red
                    Write-Log "Failed to set startup type for $($svc.DisplayName): $errorDetails" -Level ERROR
                }
                Add-ConfigurationChange -Type "Service" -Description "Failed to set startup type for: $($svc.DisplayName)" -Location $svc.Name -Success $false
                if ($svc.Critical) {
                    $repairSuccess = $false
                }
                continue
            }
            catch {
                Write-Host "    [X] Unexpected error setting startup type: $($_.Exception.Message)" -ForegroundColor Red
                Write-Log "Unexpected error setting startup type for $($svc.DisplayName): $($_.Exception.Message)" -Level ERROR
                Add-ConfigurationChange -Type "Service" -Description "Failed to set startup type for: $($svc.DisplayName)" -Location $svc.Name -Success $false
                if ($svc.Critical) {
                    $repairSuccess = $false
                }
                continue
            }
        }
        else {
            Write-Host "    [OK] Startup type is already $targetStartupType" -ForegroundColor Green
        }
        
        # Step 2: Start service if stopped (refresh service object first)
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service -and $service.Status -ne 'Running') {
            Write-Host "    [REPAIR] Starting service..." -ForegroundColor Cyan
            try {
                Start-Service -Name $svc.Name -ErrorAction Stop
                Write-Host "    [OK] Service start command executed" -ForegroundColor Green
                
                # Wait and verify with multiple checks
                Write-Host "    [VERIFY] Waiting for service to stabilize..." -ForegroundColor Cyan
                Start-Sleep -Seconds 3
                
                $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
                if ($service -and $service.Status -eq 'Running') {
                    Write-Host "    [OK] Service is now running and verified" -ForegroundColor Green
                    Write-Log "Successfully started $($svc.DisplayName)" -Level SUCCESS
                    Add-ConfigurationChange -Type "Service" -Description "Started service: $($svc.DisplayName)" -Location $svc.Name -Success $true
                    Add-SessionAction -Action "Service Started" -Details "$($svc.DisplayName) successfully started and verified" -Category "Service"
                    $servicesRepaired += "$($svc.DisplayName): Service started successfully"
                }
                else {
                    Write-Host "    [!] Service may have started but status is unclear" -ForegroundColor Yellow
                    Write-Log "Service $($svc.DisplayName) start status unclear after 3 seconds" -Level WARNING
                    Add-ConfigurationChange -Type "Service" -Description "Started service (status unclear): $($svc.DisplayName)" -Location $svc.Name -Success $false
                    if ($svc.Critical) {
                        $repairSuccess = $false
                    }
                }
            }
            catch [System.Management.Automation.ActionPreferenceStopException] {
                $errorDetails = $_.Exception.InnerException.Message
                if ($errorDetails -match "Access is denied") {
                    Write-Host "    [X] Access denied - insufficient permissions to start service" -ForegroundColor Red
                    Write-Host "        Ensure you are running as Administrator with service control rights" -ForegroundColor Yellow
                    Write-Log "Access denied when starting $($svc.DisplayName) - insufficient permissions" -Level ERROR
                }
                elseif ($errorDetails -match "service is disabled") {
                    Write-Host "    [X] Service is disabled and cannot be started" -ForegroundColor Red
                    Write-Host "        The startup type must be changed first (this should have been done above)" -ForegroundColor Yellow
                    Write-Log "Cannot start $($svc.DisplayName) - service is disabled" -Level ERROR
                }
                elseif ($errorDetails -match "service did not respond|timeout") {
                    Write-Host "    [X] Service failed to start within timeout period" -ForegroundColor Red
                    Write-Host "        Service may be experiencing dependency issues or slow startup" -ForegroundColor Yellow
                    Write-Log "Timeout starting $($svc.DisplayName)" -Level ERROR
                }
                elseif ($errorDetails -match "service depends on|dependency") {
                    Write-Host "    [X] Service dependency failure" -ForegroundColor Red
                    Write-Host "        One or more dependent services are not running" -ForegroundColor Yellow
                    Write-Log "Dependency failure starting $($svc.DisplayName)" -Level ERROR
                }
                elseif ($errorDetails -match "service cannot be started|start type") {
                    Write-Host "    [X] Service cannot be started due to configuration issue" -ForegroundColor Red
                    Write-Host "        Check service configuration and startup type" -ForegroundColor Yellow
                    Write-Log "Configuration issue preventing start of $($svc.DisplayName)" -Level ERROR
                }
                else {
                    Write-Host "    [X] Failed to start service: $errorDetails" -ForegroundColor Red
                    Write-Log "Failed to start $($svc.DisplayName): $errorDetails" -Level ERROR
                }
                Add-ConfigurationChange -Type "Service" -Description "Failed to start service: $($svc.DisplayName)" -Location $svc.Name -Success $false
                
                # Try additional diagnostics for critical services
                if ($svc.Critical) {
                    Write-Host "    [INFO] Running diagnostics for critical service..." -ForegroundColor Cyan
                    Get-ServiceDiagnostics -ServiceName $svc.Name | Out-Null
                    $repairSuccess = $false
                }
            }
            catch {
                Write-Host "    [X] Unexpected error starting service: $($_.Exception.Message)" -ForegroundColor Red
                Write-Log "Unexpected error starting $($svc.DisplayName): $($_.Exception.Message)" -Level ERROR
                Add-ConfigurationChange -Type "Service" -Description "Failed to start service: $($svc.DisplayName)" -Location $svc.Name -Success $false
                
                # Try additional diagnostics for critical services
                if ($svc.Critical) {
                    Write-Host "    [INFO] Running diagnostics for critical service..." -ForegroundColor Cyan
                    Get-ServiceDiagnostics -ServiceName $svc.Name | Out-Null
                    $repairSuccess = $false
                }
            }
        }
        else {
            Write-Host "    [OK] Service is already running" -ForegroundColor Green
        }
        
        # Final status check
        $finalService = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($finalService) {
            # Determine if the service is properly configured
            $expectedStartup = if ($svc.Name -eq 'WdNisSvc') { 'Manual' } else { 'Automatic' }
            $isProperlyConfigured = ($finalService.StartType -eq $expectedStartup)
            
            # For WdNisSvc, it's OK if it's stopped when startup type is Manual (starts on-demand)
            if ($svc.Name -eq 'WdNisSvc' -and $finalService.StartType -eq 'Manual') {
                $statusColor = if ($finalService.Status -eq 'Running') { 'Green' } else { 'Cyan' }
            }
            else {
                $statusColor = if ($finalService.Status -eq 'Running' -and $isProperlyConfigured) { 'Green' } else { 'Yellow' }
            }
            
            Write-Host "    Final Status: $($finalService.Status) | Startup: $($finalService.StartType)" -ForegroundColor $statusColor
        }
    }
    
    # Summary of repairs
    Write-Host ""
    Write-Host "  SERVICE REPAIR SUMMARY:" -ForegroundColor Yellow
    Write-Host "  ======================" -ForegroundColor Yellow
    
    if ($servicesRepaired.Count -gt 0) {
        Write-Host "  Services successfully repaired: $($servicesRepaired.Count)" -ForegroundColor Green
        foreach ($repair in $servicesRepaired) {
            Write-Host "    [OK] $repair" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  No service repairs were needed or no repairs were successful" -ForegroundColor Cyan
    }
    
    Write-Host ""
    if ($repairSuccess) {
        Write-Host "  [RESULT] Service repair completed successfully" -ForegroundColor Green
        Write-Log "Windows Defender service repair completed successfully" -Level SUCCESS
        Add-SessionAction -Action "Service Repair Complete" -Details "All critical Defender services repaired successfully" -Category "Remediation"
    }
    else {
        Write-Host "  [RESULT] Service repair completed with some issues" -ForegroundColor Yellow
        Write-Log "Windows Defender service repair completed with issues" -Level WARNING
        Add-SessionAction -Action "Service Repair Partial" -Details "Service repair completed but some issues remain" -Category "Remediation"
    }
    
    return $repairSuccess
}

function Get-ServiceDiagnostics {
    <#
    .SYNOPSIS
        Provides detailed diagnostics for a Windows service including dependencies and permissions.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )
    
    Write-Log "Diagnosing $ServiceName service..." -Level INFO
    
    try {
        # Get service details
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Log "[X] Service not found in system" -Level ERROR
            return $false
        }
        
        # Get WMI service info for more details
        $wmiService = Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
        
        if ($wmiService) {
            Write-Log "Service Details:" -Level INFO
            Write-Log "Display Name: $($wmiService.DisplayName)" -Level INFO
            Write-Log "Status: $($wmiService.State)" -Level INFO
            Write-Log "Start Mode: $($wmiService.StartMode)" -Level INFO
            Write-Log "Service Account: $($wmiService.StartName)" -Level INFO
            Write-Log "Process ID: $($wmiService.ProcessId)" -Level INFO
            Write-Log "Path: $($wmiService.PathName)" -Level INFO
            
            # Check service dependencies
            if ($wmiService.ServicesDependedOn) {
                Write-Log "Dependencies (services this depends on):" -Level INFO
                foreach ($dep in $wmiService.ServicesDependedOn) {
                    $depService = Get-Service -Name $dep -ErrorAction SilentlyContinue
                    $depStatus = if ($depService) { $depService.Status } else { "Not Found" }
                    Write-Log "$dep : $depStatus" -Level INFO
                }
            }
            
            # Check dependent services
            if ($wmiService.ServicesDependent) {
                Write-Log "Dependent Services (services that depend on this):" -Level INFO
                foreach ($dep in $wmiService.ServicesDependent) {
                    $depService = Get-Service -Name $dep -ErrorAction SilentlyContinue
                    $depStatus = if ($depService) { $depService.Status } else { "Not Found" }
                    Write-Log "$dep : $depStatus" -Level INFO
                }
            }
            
            # Check if service executable exists
            if ($wmiService.PathName) {
                # Extract executable path (remove parameters)
                $exePath = $wmiService.PathName -replace '^"([^"]+)".*', '$1'
                $exePath = $wmiService.PathName -replace '^([^\s]+).*', '$1'
                
                if (Test-Path -Path $exePath) {
                    Write-Log "Service executable found: $exePath" -Level SUCCESS
                    
                    # Get file version
                    try {
                        $fileInfo = Get-ItemProperty -Path $exePath -ErrorAction SilentlyContinue
                        if ($fileInfo.VersionInfo) {
                            Write-Log "Version: $($fileInfo.VersionInfo.FileVersion)" -Level INFO
                        }
                    }
                    catch { }
                }
                else {
                    Write-Log "[X] Service executable not found: $exePath" -Level ERROR
                    return $false
                }
            }
            
            # Check for common issues
            if ($wmiService.StartMode -eq "Disabled") {
                Write-Log "[!] Service is disabled - this may prevent MDE from working" -Level WARNING
                return $false
            }
            
            if ($wmiService.State -ne "Running" -and $ServiceName -in @("WinDefend", "Sense")) {
                Write-Log "[!] Critical service is not running" -Level WARNING
                return $false
            }
        }
        
        return $true
    }
    catch {
        Write-Log "[X] Failed to get service diagnostics: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Test-DefenderPlatform {
    Write-Log "Checking Windows Defender platform version..." -Level INFO
    
    try {
        $defenderVersion = Get-MpComputerStatus -ErrorAction Stop
        
        Write-Log "Antivirus Version: $($defenderVersion.AMProductVersion)" -Level INFO
        Write-Log "Engine Version: $($defenderVersion.AMEngineVersion)" -Level INFO
        Write-Log "Signature Version: $($defenderVersion.AntivirusSignatureVersion)" -Level INFO
        Write-Log "Last Update: $($defenderVersion.AntivirusSignatureLastUpdated)" -Level INFO
        
        # Check if antimalware is enabled
        if (-not $defenderVersion.AntivirusEnabled) {
            Write-Log "Windows Defender Antivirus is not enabled" -Level WARNING
            
            Write-Host ""
            Write-Host "  WINDOWS DEFENDER ENABLEMENT REQUIRED:" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  The following system change will be made:" -ForegroundColor White
            Write-Host "  Windows Defender Preference: DisableRealtimeMonitoring = False" -ForegroundColor Cyan
            Write-Host "  Registry Location: HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection" -ForegroundColor Cyan
            Write-Host "  Registry Key: DisableRealtimeMonitoring = 0" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  This change will:" -ForegroundColor White
            Write-Host "  Enable Windows Defender real-time protection" -ForegroundColor White
            Write-Host "  Allow file system monitoring and threat detection" -ForegroundColor White
            Write-Host "  Prepare the system for MDE onboarding" -ForegroundColor White
            Write-Host ""
            
            if (Get-UserConfirmation -Message "ENABLE: Windows Defender Antivirus with real-time protection?" -DefaultYes $true) {
                try {
                    Write-Host "  Setting Windows Defender preference..." -ForegroundColor Cyan
                    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
                    Write-Log "Windows Defender Antivirus enabled successfully" -Level SUCCESS
                    Write-Host "  Registry change completed: DisableRealtimeMonitoring = 0" -ForegroundColor Green
                    Add-ConfigurationChange -Type "Registry" -Description "Enabled Windows Defender real-time monitoring" -Location "Windows Defender Preferences" -Success $true
                    Add-SessionAction -Action "Defender Enabled" -Details "Windows Defender Antivirus real-time protection enabled" -Category "Configuration"
                }
                catch {
                    Write-Log "Failed to enable Windows Defender: $($_.Exception.Message)" -Level ERROR
                    Add-ConfigurationChange -Type "Registry" -Description "Failed to enable Windows Defender real-time monitoring" -Location "Windows Defender Preferences" -Success $false
                    return $false
                }
            }
        }
        else {
            Write-Log "Windows Defender Antivirus is enabled" -Level SUCCESS
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to get Defender status: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Test-DefenderPlatformDirectory {
    Write-Log "Checking Windows Defender platform directory..." -Level INFO
    
    $platformPath = "C:\ProgramData\Microsoft\Windows Defender\Platform"
    
    if (Test-Path -Path $platformPath -PathType Container) {
        Write-Log "Platform directory exists: $platformPath" -Level SUCCESS
        
        # Check if there are any platform versions installed
        $platformVersions = Get-ChildItem -Path $platformPath -Directory -ErrorAction SilentlyContinue
        if ($platformVersions.Count -gt 0) {
            $latestVersion = $platformVersions | Sort-Object Name -Descending | Select-Object -First 1
            Write-Log "Latest platform version: $($latestVersion.Name)" -Level INFO
            
            # Check for MpCmdRun.exe
            $mpCmdPath = Join-Path -Path $latestVersion.FullName -ChildPath "MpCmdRun.exe"
            if (Test-Path -Path $mpCmdPath) {
                Write-Log "MpCmdRun.exe found in platform directory" -Level SUCCESS
            }
            else {
                Write-Log "MpCmdRun.exe not found (may affect functionality)" -Level WARNING
            }
        }
        else {
            Write-Log "No platform versions found in directory" -Level WARNING
        }
        
        return $true
    }
    else {
        Write-Log "Platform directory not found: $platformPath" -Level ERROR
        Write-Log "Windows Defender Antimalware platform is not installed or corrupted" -Level ERROR
        Write-Log "This is required for MDE onboarding and Sense service operation" -Level ERROR
        return $false
    }
}

function Test-DefenderPlatformVersion {
    Write-Log "Checking Windows Defender platform version status..." -Level INFO
    
    try {
        $defenderStatus = Get-MpComputerStatus -ErrorAction Stop
        
        # Get the current platform version
        $currentPlatformVersion = $defenderStatus.AMProductVersion
        Write-Log "Current Platform Version: $currentPlatformVersion" -Level INFO
        
        # Get the signature age
        $signatureLastUpdated = $defenderStatus.AntivirusSignatureLastUpdated
        if ($null -ne $signatureLastUpdated) {
            $daysSinceUpdate = ((Get-Date) - $signatureLastUpdated).Days
            Write-Log "Signature Last Updated: $signatureLastUpdated ($daysSinceUpdate days ago)" -Level INFO
            
            # Check if signatures are outdated (more than 7 days old)
            if ($daysSinceUpdate -gt 7) {
                Write-Log "Platform signatures are outdated (more than 7 days old)" -Level WARNING
                Write-Log "Strongly recommended to update before onboarding" -Level WARNING
                
                Write-Host ""
                Write-Host "  WINDOWS DEFENDER UPDATE REQUIRED:" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  The following updates will be performed:" -ForegroundColor White
                Write-Host "  Download latest Windows Defender platform files" -ForegroundColor Cyan
                Write-Host "  Update antivirus signature definitions" -ForegroundColor Cyan
                Write-Host "  Update anti-spyware definitions" -ForegroundColor Cyan
                Write-Host "  Refresh Network Inspection System signatures" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  Update details:" -ForegroundColor White
                Write-Host "  Source: Microsoft Update servers" -ForegroundColor White
                Write-Host "  Current signature age: $daysSinceUpdate days" -ForegroundColor White
                Write-Host "  Target: Latest available definitions" -ForegroundColor White
                Write-Host "  Network required: Yes (downloads from Microsoft)" -ForegroundColor White
                Write-Host ""
                
                if (Get-UserConfirmation -Message "UPDATE: Windows Defender platform and signatures?" -DefaultYes $true) {
                    Write-Log "Downloading and installing Windows Defender updates..." -Level INFO
                    Write-Host "  Connecting to Microsoft Update servers..." -ForegroundColor Cyan
                    try {
                        Update-MpSignature -ErrorAction Stop
                        Write-Log "Platform and signatures updated successfully" -Level SUCCESS
                        
                        # Re-check the version after update
                        $updatedStatus = Get-MpComputerStatus -ErrorAction Stop
                        Write-Log "Updated Platform Version: $($updatedStatus.AMProductVersion)" -Level INFO
                        Write-Log "Updated Signature Version: $($updatedStatus.AntivirusSignatureVersion)" -Level INFO
                        Add-ConfigurationChange -Type "Update" -Description "Windows Defender platform and signatures updated" -Location "Microsoft Update" -Success $true
                        Add-SessionAction -Action "Platform Updated" -Details "Windows Defender platform version: $($updatedStatus.AMProductVersion)" -Category "Update"
                        return $true
                    }
                    catch {
                        Write-Log "Failed to update platform: $($_.Exception.Message)" -Level ERROR
                        Write-Log "This may cause issues during onboarding" -Level ERROR
                        Add-ConfigurationChange -Type "Update" -Description "Failed to update Windows Defender platform" -Location "Microsoft Update" -Success $false
                        return $false
                    }
                }
                else {
                    Write-Log "User declined platform update - proceeding with outdated version" -Level WARNING
                    return $true
                }
            }
            else {
                Write-Log "Platform is up-to-date (updated within last 7 days)" -Level SUCCESS
                return $true
            }
        }
        else {
            Write-Log "Unable to determine last update time" -Level WARNING
            return $true
        }
    }
    catch {
        Write-Log "Failed to check platform version: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Test-DiskSpace {
    Write-Log "Checking available disk space..." -Level INFO
    
    $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
    $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
    $totalSpaceGB = [math]::Round($systemDrive.Size / 1GB, 2)
    $freeSpacePercent = [math]::Round(($systemDrive.FreeSpace / $systemDrive.Size) * 100, 2)
    
    Write-Log "System Drive: $($systemDrive.DeviceID)" -Level INFO
    Write-Log "Free Space: $freeSpaceGB GB / $totalSpaceGB GB ($freeSpacePercent%)" -Level INFO
    
    if ($freeSpaceGB -lt 5) {
        Write-Log "Insufficient disk space (minimum 5 GB required)" -Level ERROR
        return $false
    }
    
    Write-Log "Sufficient disk space available" -Level SUCCESS
    return $true
}

function Test-SystemResources {
    Write-Log "Checking system resources..." -Level INFO
    
    # Check RAM
    $memory = Get-CimInstance -ClassName Win32_ComputerSystem
    $totalMemoryGB = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
    Write-Log "Total RAM: $totalMemoryGB GB" -Level INFO
    
    if ($totalMemoryGB -lt 2) {
        Write-Log "Low RAM detected (minimum 2 GB recommended)" -Level WARNING
    }
    else {
        Write-Log "Sufficient RAM" -Level SUCCESS
    }
    
    # Check CPU
    $cpu = Get-CimInstance -ClassName Win32_Processor
    Write-Log "CPU: $($cpu.Name)" -Level INFO
    Write-Log "Cores: $($cpu.NumberOfCores)" -Level INFO
    Write-Log "Logical Processors: $($cpu.NumberOfLogicalProcessors)" -Level INFO
    
    return $true
}

function Test-WindowsUpdates {
    Write-Log "Checking for Windows Updates..." -Level INFO
    
    try {
        # Check if Windows Update service is running
        $wuService = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
        if ($null -eq $wuService) {
            Write-Log "Windows Update service not found" -Level WARNING
            return $true
        }
        
        if ($wuService.Status -ne 'Running') {
            Write-Log "Starting Windows Update service..." -Level INFO
            try {
                Start-Service -Name "wuauserv" -ErrorAction Stop
                Write-Log "Windows Update service started" -Level SUCCESS
            }
            catch {
                Write-Log "Could not start Windows Update service: $($_.Exception.Message)" -Level WARNING
                return $true
            }
        }
        
        # Check for available updates using Windows Update COM object
        Write-Log "Searching for available updates (this may take a few minutes)..." -Level INFO
        
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        
        # Search for updates that are not installed
        $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
        
        $updateCount = $searchResult.Updates.Count
        
        if ($updateCount -eq 0) {
            Write-Log "No updates available - system is up to date" -Level SUCCESS
            return $true
        }
        
        # Categorize updates
        $criticalCount = 0
        $securityCount = 0
        $importantCount = 0
        $optionalCount = 0
        $defenderUpdates = @()
        
        foreach ($update in $searchResult.Updates) {
            # Check if it's a Defender update
            if ($update.Title -match "Defender|Definition|Signature|Antimalware") {
                $defenderUpdates += $update
            }
            
            # Categorize by severity
            $criticalCount += if ($update.MsrcSeverity -eq "Critical") { 1 } else { 0 }
            $importantCount += if ($update.MsrcSeverity -eq "Important") { 1 } else { 0 }
            $securityCount += if ($update.Categories | Where-Object { $_.Name -eq "Security Updates" }) { 1 } else { 0 }
            $optionalCount += if ($update.MsrcSeverity -eq "Optional") { 1 } else { 0 }
        }
        
        Write-Log "$updateCount update(s) available" -Level WARNING
        if ($criticalCount -gt 0) {
            Write-Log "Critical: $criticalCount" -Level ERROR
        }
        if ($importantCount -gt 0) {
            Write-Log "Important: $importantCount" -Level WARNING
        }
        if ($securityCount -gt 0) {
            Write-Log "Security: $securityCount" -Level WARNING
        }
        if ($optionalCount -gt 0) {
            Write-Log "Optional: $optionalCount" -Level INFO
        }
        if ($defenderUpdates.Count -gt 0) {
            Write-Log "Windows Defender: $($defenderUpdates.Count)" -Level INFO
        }
        
        Write-Host ""
        Write-Host "  WINDOWS UPDATES AVAILABLE FOR INSTALLATION:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Update summary to be installed:" -ForegroundColor White
        Write-Host "  Total updates: $updateCount" -ForegroundColor Cyan
        if ($criticalCount -gt 0) {
            Write-Host "  Critical updates: $criticalCount" -ForegroundColor Red
        }
        if ($importantCount -gt 0) {
            Write-Host "  Important updates: $importantCount" -ForegroundColor Yellow
        }
        if ($securityCount -gt 0) {
            Write-Host "  Security updates: $securityCount" -ForegroundColor Yellow
        }
        if ($defenderUpdates.Count -gt 0) {
            Write-Host "  Windows Defender updates: $($defenderUpdates.Count)" -ForegroundColor Cyan
        }
        if ($optionalCount -gt 0) {
            Write-Host "  Optional updates: $optionalCount" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "  Installation details:" -ForegroundColor White
        Write-Host "  Download source: Microsoft Update servers" -ForegroundColor White
        Write-Host "  Installation method: Windows Update COM API" -ForegroundColor White
        Write-Host "  System restart: May be required after installation" -ForegroundColor White
        Write-Host "  Recommended: Yes (improves MDE onboarding success)" -ForegroundColor White
        Write-Host ""
        
        if (Get-UserConfirmation -Message "INSTALL: All available Windows Updates?" -DefaultYes $true) {
            return Install-WindowsUpdates -SearchResult $searchResult
        }
        else {
            Write-Log "User declined to install updates" -Level WARNING
            Write-Log "Proceeding without updates - this may affect onboarding" -Level WARNING
            return $true
        }
    }
    catch {
        Write-Log "Could not check for updates: $($_.Exception.Message)" -Level WARNING
        Write-Log "This is not critical - continuing with onboarding" -Level INFO
        return $true
    }
}

function Install-WindowsUpdates {
    param(
        [Parameter(Mandatory = $true)]
        [Object]$SearchResult
    )
    
    Write-Log "Installing Windows Updates..." -Level INFO
    Write-Host ""
    Write-Host "  Starting Windows Update installation..." -ForegroundColor Cyan
    Write-Host "  This process may take 15-60 minutes depending on the number of updates." -ForegroundColor Yellow
    Write-Host "  Please do not interrupt this process." -ForegroundColor Yellow
    Write-Host ""
    
    try {
        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        
        $installCount = 0
        foreach ($update in $SearchResult.Updates) {
            if ($update.EulaAccepted -eq $false) {
                $update.AcceptEula()
            }
            $updatesToInstall.Add($update) | Out-Null
            $installCount++
        }
        
        if ($installCount -eq 0) {
            Write-Log "  No updates to install" -Level INFO
            return $true
        }
        
        Write-Log "  Preparing to install $installCount update(s)..." -Level INFO
        
        # Download updates
        Write-Host "  [1/3] Downloading updates..." -ForegroundColor Cyan
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $downloader = $updateSession.CreateUpdateDownloader()
        $downloader.Updates = $updatesToInstall
        
        $downloadResult = $downloader.Download()
        
        if ($downloadResult.ResultCode -eq 2) {
            Write-Log "Updates downloaded successfully" -Level SUCCESS
        }
        else {
            Write-Log "Update download failed with result code: $($downloadResult.ResultCode)" -Level ERROR
            return $false
        }
        
        # Install updates
        Write-Host "  [2/3] Installing updates..." -ForegroundColor Cyan
        $installer = $updateSession.CreateUpdateInstaller()
        $installer.Updates = $updatesToInstall
        
        $installResult = $installer.Install()
        
        Write-Host ""
        Write-Log "  Installation Result Code: $($installResult.ResultCode)" -Level INFO
        Write-Log "  Reboot Required: $($installResult.RebootRequired)" -Level INFO
        
        # Check results
        $successCount = 0
        $failedCount = 0
        for ($i = 0; $i -lt $updatesToInstall.Count; $i++) {
            $update = $updatesToInstall.Item($i)
            $result = $installResult.GetUpdateResult($i)
            
            if ($result.ResultCode -eq 2) {
                $successCount++
                # Track successfully installed update
                $script:SessionSummary.UpdatesInstalled += @{
                    Title = $update.Title
                    Description = $update.Description
                    Timestamp = Get-Date
                }
                Add-SessionAction -Action "Update Installed" -Details $update.Title -Category "Update"
            }
            else {
                $failedCount++
                Write-Log "Failed to install: $($update.Title)" -Level WARNING
            }
        }
        
        Write-Host ""
        Write-Log "[3/3] Installation Summary:" -Level INFO
        Write-Log "Successfully installed: $successCount" -Level SUCCESS
        if ($failedCount -gt 0) {
            Write-Log "Failed: $failedCount" -Level WARNING
        }
        
        # Handle reboot requirement
        if ($installResult.RebootRequired) {
            Write-Host ""
            Write-Host "  [REBOOT] SYSTEM REBOOT REQUIRED" -ForegroundColor Yellow
            Write-Host "  =========================" -ForegroundColor Yellow
            Write-Host "  Windows updates require a system restart to complete" -ForegroundColor White
            Write-Host "  The server must reboot before continuing MDE onboarding" -ForegroundColor White
            Write-Host "  You will need to re-run this script after the reboot" -ForegroundColor White
            Write-Host ""
            Write-Host "  OPTIONS:" -ForegroundColor Cyan
            Write-Host "  Reboot now: Automatic restart in 30 seconds" -ForegroundColor White
            Write-Host "  Manual reboot: You control when to restart" -ForegroundColor White
            Write-Host ""
            
            if (Get-UserConfirmation -Message "REBOOT: Restart the server now?" -DefaultYes $false) {
                Write-Log "  User chose to reboot now" -Level INFO
                Write-Host ""
                Write-Host "  The server will reboot in 30 seconds..." -ForegroundColor Yellow
                Write-Host "  Please re-run this script after the reboot to continue onboarding." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Press any key to cancel the reboot..." -ForegroundColor Cyan
                
                $timeout = New-TimeSpan -Seconds 30
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                
                while ($stopwatch.Elapsed -lt $timeout) {
                    if ([Console]::KeyAvailable) {
                        [Console]::ReadKey($true) | Out-Null
                        Write-Host ""
                        Write-Log "  Reboot cancelled by user" -Level INFO
                        Write-Host "  Reboot cancelled. Please reboot manually before continuing with MDE onboarding." -ForegroundColor Yellow
                        $script:SessionSummary.OnboardingStatus = "Reboot Required"
                        Add-SessionAction -Action "Reboot Cancelled" -Details "User cancelled automatic reboot - manual reboot required" -Category "User"
                        Exit-WithSummary -ExitReason "Reboot required - user cancelled automatic restart" -ExitCode 0
                    }
                    Start-Sleep -Milliseconds 500
                }
                
                Write-Log "  Initiating system reboot..." -Level INFO
                Add-SessionAction -Action "Automatic Reboot" -Details "System reboot initiated after Windows Updates" -Category "System"
                $script:SessionSummary.OnboardingStatus = "Reboot Required"
                Show-SessionSummary -ExitReason "System reboot after Windows Updates installation"
                Restart-Computer -Force
                exit 0
            }
            else {
                Write-Log "  User declined to reboot now" -Level WARNING
                Write-Host ""
                Write-Host "  Please reboot the server manually before continuing with MDE onboarding." -ForegroundColor Yellow
                $script:SessionSummary.OnboardingStatus = "Reboot Required"
                Add-SessionAction -Action "Manual Reboot Required" -Details "User declined automatic reboot - manual restart needed" -Category "User"
                Exit-WithSummary -ExitReason "Reboot required - user chose manual restart" -ExitCode 0
            }
        }
        
        Write-Host ""
        Write-Log "Windows Updates installed successfully" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Failed to install updates: $($_.Exception.Message)" -Level ERROR
        Write-Log "You may continue with onboarding, but updates are recommended" -Level WARNING
        return $true
    }
}

function Test-GroupPolicy {
    Write-Log "Checking Group Policy settings..." -Level INFO
    
    try {
        # Check if Defender is disabled by Group Policy
        $defenderGPO = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -ErrorAction SilentlyContinue
        
        if ($null -ne $defenderGPO -and $defenderGPO.DisableAntiSpyware -eq 1) {
            Write-Log "Windows Defender is disabled by Group Policy" -Level ERROR
            Write-Log "Please contact your domain administrator to enable Windows Defender" -Level ERROR
            return $false
        }
        
        Write-Log "No blocking Group Policy detected" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Could not verify Group Policy settings: $($_.Exception.Message)" -Level WARNING
        return $true
    }
}

function Test-OnboardingScript {
    Write-Log "Checking for onboarding script..." -Level INFO
    
    # Search in current directory for any onboarding CMD file
    $currentLocation = Get-Location
    $localOnboardingScripts = Get-ChildItem -Path $currentLocation -Filter "*Onboarding*.cmd" -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "WindowsDefenderATP.*Onboarding" }
    
    if ($localOnboardingScripts) {
        $foundScript = $localOnboardingScripts[0]
        Write-Log "Found onboarding script: $($foundScript.FullName)" -Level SUCCESS
        $script:OnboardingScriptPath = $foundScript.FullName
        return $true
    }
    
    # Not found - ask user to provide location or download
    Write-Log "Onboarding script not found in current location" -Level ERROR
    Write-Log "Current location: $currentLocation" -Level ERROR
    Write-Host ""
    Write-Host "  The MDE onboarding package was not found in the current directory." -ForegroundColor Yellow
    Write-Host "  Current directory: $currentLocation" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor White
    Write-Host "    1. Provide the path to an existing onboarding package" -ForegroundColor White
    Write-Host "    2. Download the onboarding package from Microsoft Defender portal" -ForegroundColor White
    Write-Host ""
    
    # Loop until valid input is received
    $validChoice = $false
    while (-not $validChoice) {
        $choice = Read-Host "  Enter your choice (1 or 2)"
        
        # Trim whitespace
        $choice = $choice.Trim()
        
        switch ($choice) {
            "1" {
                $validChoice = $true
                Write-Host ""
                Write-Host "  Please provide the path to the onboarding package." -ForegroundColor Cyan
                Write-Host "  You can provide:" -ForegroundColor White
                Write-Host "  Path to the .cmd file (e.g., C:\Downloads\WindowsDefenderATPLocalOnboardingScript.cmd)" -ForegroundColor White
                Write-Host "  Path to a folder containing the .cmd file" -ForegroundColor White
                Write-Host "  Path to a .zip file" -ForegroundColor White
                Write-Host ""
                
                while ($true) {
                    $userPath = Read-Host "  Enter path (or type 'exit' to quit)"
                    
                    # Check if user wants to exit
                    if ($userPath -eq 'exit') {
                        Write-Log "  User chose to exit" -Level INFO
                        $script:SessionSummary.OnboardingStatus = "Cancelled"
                        Add-SessionAction -Action "User Exit" -Details "User typed 'exit' during onboarding script selection" -Category "User"
                        Exit-WithSummary -ExitReason "User chose to exit during onboarding script location" -ExitCode 0
                    }
                    
                    if ([string]::IsNullOrWhiteSpace($userPath)) {
                        Write-Host "  [!] No path provided" -ForegroundColor Yellow
                        continue
                    }
                    
                    # Clean up the path - remove quotes, trim whitespace
                    $userPath = $userPath.Trim().Trim('"').Trim("'")
                    
                    # Check if path exists
                    if (-not (Test-Path -Path $userPath)) {
                        Write-Host "  [X] Path not found: $userPath" -ForegroundColor Red
                        continue
                    }
                    
                    # Determine what type of path it is
                    $item = Get-Item -Path $userPath
                    
                    if ($item.PSIsContainer) {
                        # It's a folder - look for .cmd file
                        $cmdFiles = Get-ChildItem -Path $userPath -Filter "*Onboarding*.cmd" -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "WindowsDefenderATP.*Onboarding" }
                        
                        if ($cmdFiles) {
                            $sourceScript = $cmdFiles[0].FullName
                            Write-Log "Found onboarding script: $sourceScript" -Level SUCCESS
                            $script:OnboardingScriptPath = $sourceScript
                            return $true
                        }
                        else {
                            Write-Host "  [X] No onboarding script found in folder: $userPath" -ForegroundColor Red
                            continue
                        }
                    }
                    elseif ($item.Extension -eq ".zip") {
                        # It's a ZIP file - extract and find .cmd
                        Write-Log "[INFO] Extracting ZIP file: $userPath" -Level INFO
                        
                        try {
                            $tempExtractPath = Join-Path -Path $env:TEMP -ChildPath "MDEOnboarding_$((Get-Date).Ticks)"
                            Expand-Archive -Path $userPath -DestinationPath $tempExtractPath -Force -ErrorAction Stop
                            
                            $cmdFiles = Get-ChildItem -Path $tempExtractPath -Filter "*Onboarding*.cmd" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "WindowsDefenderATP.*Onboarding" }
                            
                            if ($cmdFiles) {
                                $sourceScript = $cmdFiles[0].FullName
                                Write-Log "Found onboarding script in ZIP: $($cmdFiles[0].Name)" -Level SUCCESS
                                
                                # Copy to current location for future use
                                $destPath = Join-Path -Path $currentLocation -ChildPath $cmdFiles[0].Name
                                Copy-Item -Path $sourceScript -Destination $destPath -Force -ErrorAction Stop
                                Write-Log "Onboarding script copied to current location" -Level SUCCESS
                                
                                $script:OnboardingScriptPath = $destPath
                                
                                # Clean up temp folder
                                Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
                                return $true
                            }
                            else {
                                Write-Host "  [X] No onboarding script found in ZIP file" -ForegroundColor Red
                                Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
                                continue
                            }
                        }
                        catch {
                            Write-Log "Failed to extract ZIP file: $($_.Exception.Message)" -Level ERROR
                            continue
                        }
                    }
                    elseif ($item.Extension -eq ".cmd") {
                        # It's a .cmd file - verify it's the right one
                        if ($item.Name -match "WindowsDefenderATP.*Onboarding") {
                            Write-Log "Found onboarding script: $($item.FullName)" -Level SUCCESS
                            $script:OnboardingScriptPath = $item.FullName
                            return $true
                        }
                        else {
                            Write-Host "  [X] This doesn't appear to be a valid MDE onboarding script" -ForegroundColor Red
                            continue
                        }
                    }
                    else {
                        Write-Host "  [X] Unsupported file type: $($item.Extension)" -ForegroundColor Red
                        Write-Host "  Please provide a .cmd file, folder, or .zip file" -ForegroundColor Yellow
                        continue
                    }
                }
                
                # Should not reach here (user would have exited or found script)
                Write-Log "Could not locate onboarding package" -Level ERROR
                return $false
            }
            "2" {
                $validChoice = $true
                Write-Host ""
                Write-Host "  Opening Microsoft Defender portal..." -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  Steps to download the onboarding package:" -ForegroundColor Yellow
                Write-Host "    1. Sign in to the Microsoft Defender portal" -ForegroundColor White
                Write-Host "    2. Go to: Settings > Endpoints > Onboarding" -ForegroundColor White
                Write-Host "    3. Select 'Windows Server 2019, 2022, and 2025' as the operating system" -ForegroundColor White
                Write-Host "    4. Select 'Local Script' as the deployment method" -ForegroundColor White
                Write-Host "    5. Click 'Download onboarding package'" -ForegroundColor White
                Write-Host "    6. Extract or copy the onboarding script to this directory:" -ForegroundColor White
                Write-Host "       $currentLocation" -ForegroundColor Cyan
                Write-Host "    7. Return to this PowerShell session and re-run this script" -ForegroundColor White
                Write-Host ""
                
                # Check if Server Core - don't attempt to open browser
                if (Test-IsServerCore) {
                    Write-Host "  [!] Server Core detected - browser cannot be opened automatically" -ForegroundColor Yellow
                    Write-Host "  Please navigate to the portal from another machine:" -ForegroundColor Yellow
                    Write-Host "  https://security.microsoft.com/securitysettings/endpoints/onboarding" -ForegroundColor Cyan
                }
                else {
                    Write-Host "  Press any key to open the portal in your browser..." -ForegroundColor Yellow
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    Write-Host ""
                    
                    try {
                        Start-Process "https://security.microsoft.com/securitysettings/endpoints/onboarding"
                        Write-Log "  Portal opened in browser" -Level INFO
                    }
                    catch {
                        Write-Log "Failed to open browser: $($_.Exception.Message)" -Level ERROR
                        Write-Host "  Please manually navigate to: https://security.microsoft.com/securitysettings/endpoints/onboarding" -ForegroundColor Yellow
                    }
                }
                
                Write-Host ""
                $script:SessionSummary.OnboardingStatus = "Cancelled"
                Add-SessionAction -Action "Portal Download" -Details "User redirected to Microsoft Defender portal for onboarding package download" -Category "User"
                Exit-WithSummary -ExitReason "User redirected to download onboarding package from portal" -ExitCode 0
            }
            default {
                Write-Host "  Invalid choice. Please enter 1 or 2." -ForegroundColor Yellow
            }
        }
    }
    
    # Should not reach here
    return $false
}

function Test-ExistingOnboarding {
    Write-Log "Checking for existing MDE onboarding..." -Level INFO
    
    try {
        # Check registry for onboarding status
        $orgId = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status" -Name "OrgId" -ErrorAction SilentlyContinue
        
        if ($null -ne $orgId -and ![string]::IsNullOrWhiteSpace($orgId.OrgId)) {
            Write-Log "Server is already onboarded to MDE" -Level SUCCESS
            Write-Log "Organization ID: $(Get-ObfuscatedOrgId -OrgId $orgId.OrgId)" -Level INFO
            
            # Get and report Defender operational mode
            $defenderMode = Get-DefenderOperationalMode
            Write-Log "Defender Mode: $defenderMode" -Level INFO
            
            Write-Host ""
            Write-Host "  This server is already onboarded to Microsoft Defender for Endpoint." -ForegroundColor Green
            Write-Host "  Organization ID: $(Get-ObfuscatedOrgId -OrgId $orgId.OrgId)" -ForegroundColor Cyan
            Write-Host "  Defender Mode: $defenderMode" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  You have the following options:" -ForegroundColor Yellow
            Write-Host "    1. Offboard this server from MDE" -ForegroundColor White
            Write-Host "    2. Cancel and exit (keep current onboarding)" -ForegroundColor White
            Write-Host ""
            
            # Loop until valid input is received
            $validChoice = $false
            while (-not $validChoice) {
                $choice = Read-Host "  Enter your choice (1 or 2)"
                
                # Trim whitespace and convert to string for comparison
                $choice = $choice.Trim()
                
                switch ($choice) {
                    "1" {
                        $validChoice = $true
                        Write-Log "  User chose to offboard the server" -Level INFO
                        if (Start-OffboardingProcess) {
                            Write-Log "  Server offboarded successfully" -Level SUCCESS
                            Write-Host "`nServer has been offboarded from MDE." -ForegroundColor Green
                            $script:SessionSummary.OnboardingStatus = "Offboarded"
                            Add-SessionAction -Action "Offboarding Completed" -Details "Server successfully offboarded from MDE" -Category "Onboarding"
                            Exit-WithSummary -ExitReason "Server successfully offboarded from MDE" -ExitCode 0
                        }
                        else {
                            Write-Log "  Offboarding failed" -Level ERROR
                            $script:SessionSummary.OnboardingStatus = "Offboarding Failed"
                            Add-SessionAction -Action "Offboarding Failed" -Details "Failed to offboard server from MDE" -Category "Onboarding"
                            Exit-WithSummary -ExitReason "Offboarding process failed" -ExitCode 1
                        }
                    }
                    "2" {
                        $validChoice = $true
                        Write-Log "  User chose to keep current onboarding - exiting" -Level INFO
                        Write-Host "`nServer remains onboarded to MDE. No changes made." -ForegroundColor Green
                        $script:SessionSummary.OnboardingStatus = "Already Onboarded"
                        Add-SessionAction -Action "Keep Existing" -Details "User chose to keep existing MDE onboarding" -Category "User"
                        Exit-WithSummary -ExitReason "User chose to keep existing MDE onboarding" -ExitCode 0
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        exit 0
                    }
                    default {
                        Write-Host "  Invalid choice. Please enter 1 or 2." -ForegroundColor Yellow
                    }
                }
            }
        }
        
        Write-Log "Server is not currently onboarded - ready for new onboarding" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Could not verify onboarding status: $($_.Exception.Message)" -Level WARNING
        return $true
    }
}

function Update-DefenderSignatures {
    Write-Log "Updating Windows Defender signatures..." -Level INFO
    
    try {
        Update-MpSignature -ErrorAction Stop
        Write-Log "Signatures updated successfully" -Level SUCCESS
        Add-ConfigurationChange -Type "Update" -Description "Windows Defender signatures updated" -Location "Microsoft Update" -Success $true
        Add-SessionAction -Action "Signatures Updated" -Details "Windows Defender signature definitions updated" -Category "Update"
        return $true
    }
    catch {
        Write-Log "Failed to update signatures: $($_.Exception.Message)" -Level WARNING
        Write-Log "Continuing with onboarding..." -Level INFO
        Add-ConfigurationChange -Type "Update" -Description "Failed to update Windows Defender signatures" -Location "Microsoft Update" -Success $false
        return $true
    }
}

function Start-OnboardingProcess {
    Write-Log "Starting MDE onboarding process..." -Level INFO
    Add-SessionAction -Action "Executing Onboarding Script" -Details "Running onboarding script: $script:OnboardingScriptPath" -Category "Onboarding"
    
    try {
        Write-Host "`nExecuting onboarding script..." -ForegroundColor Yellow
        Write-Host "Please follow the prompts in the onboarding script.`n" -ForegroundColor Yellow
        
        # Execute the onboarding script
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$script:OnboardingScriptPath`"" -Wait -NoNewWindow -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Log "Onboarding script completed successfully" -Level SUCCESS
            Add-SessionAction -Action "Onboarding Script Success" -Details "Onboarding script executed with exit code 0" -Category "Onboarding"
            return $true
        }
        else {
            Write-Log "Onboarding script failed with exit code: $($process.ExitCode)" -Level ERROR
            Add-SessionAction -Action "Onboarding Script Failed" -Details "Onboarding script failed with exit code: $($process.ExitCode)" -Category "Onboarding"
            return $false
        }
    }
    catch {
        Write-Log "Failed to execute onboarding script: $($_.Exception.Message)" -Level ERROR
        Add-SessionAction -Action "Onboarding Script Error" -Details "Exception during script execution: $($_.Exception.Message)" -Category "Onboarding"
        return $false
    }
}

function Start-OffboardingProcess {
    Write-Log "Starting MDE offboarding process..." -Level INFO
    
    # Search for offboarding script in current directory
    $currentLocation = Get-Location
    $offboardingScripts = Get-ChildItem -Path $currentLocation -Filter "*Offboarding*.cmd" -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "WindowsDefenderATP.*Offboarding" }
    
    $offboardingScriptPath = $null
    if ($offboardingScripts) {
        $offboardingScriptPath = $offboardingScripts[0].FullName
    }
    
    if (-not $offboardingScriptPath -or -not (Test-Path -Path $offboardingScriptPath)) {
        Write-Log "Offboarding script not found in current location" -Level ERROR
        Write-Log "Current location: $currentLocation" -Level ERROR
        Write-Host ""
        Write-Host "  The offboarding script was not found in the current directory." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Options:" -ForegroundColor White
        Write-Host "    1. Provide the path to an existing offboarding package" -ForegroundColor White
        Write-Host "    2. Download the offboarding package from Microsoft Defender portal" -ForegroundColor White
        Write-Host ""
        
        # Loop until valid input is received
        $validChoice = $false
        while (-not $validChoice) {
            $choice = Read-Host "  Enter your choice (1 or 2)"
            
            # Trim whitespace
            $choice = $choice.Trim()
            
            switch ($choice) {
                "1" {
                    $validChoice = $true
                    Write-Host ""
                    Write-Host "  Please provide the path to the offboarding package." -ForegroundColor Cyan
                    Write-Host "  You can provide:" -ForegroundColor White
                    Write-Host "    - Path to the .cmd file (e.g., C:\Downloads\WindowsDefenderATPOffboardingScript.cmd)" -ForegroundColor White
                    Write-Host "    - Path to a folder containing the .cmd file" -ForegroundColor White
                    Write-Host "    - Path to a .zip file" -ForegroundColor White
                    Write-Host ""
                    
                    while ($true) {
                        $userPath = Read-Host "  Enter path (or type 'exit' to quit)"
                        
                        # Check if user wants to exit
                        if ($userPath -eq 'exit') {
                            Write-Log "  User chose to exit" -Level INFO
                            $script:SessionSummary.OnboardingStatus = "Cancelled"
                            Add-SessionAction -Action "User Exit" -Details "User typed 'exit' during offboarding script selection" -Category "User"
                            Exit-WithSummary -ExitReason "User chose to exit during offboarding process" -ExitCode 0
                        }
                        
                        if ([string]::IsNullOrWhiteSpace($userPath)) {
                            Write-Host "  Path cannot be empty. Please try again." -ForegroundColor Yellow
                            continue
                        }
                        
                        # Remove quotes if present
                        $userPath = $userPath.Trim('"').Trim("'")
                        
                        if (-not (Test-Path -Path $userPath)) {
                            Write-Host "  Path not found: $userPath" -ForegroundColor Red
                            continue
                        }
                        
                        $item = Get-Item -Path $userPath
                        
                        if ($item.PSIsContainer) {
                            # It's a directory - search for offboarding script
                            $scripts = Get-ChildItem -Path $userPath -Filter "*Offboarding*.cmd" -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "WindowsDefenderATP.*Offboarding" }
                            if ($scripts) {
                                $offboardingScriptPath = $scripts[0].FullName
                                Write-Log "Found offboarding script: $offboardingScriptPath" -Level SUCCESS
                                break
                            }
                            else {
                                Write-Host "  No offboarding script found in the specified directory." -ForegroundColor Red
                            }
                        }
                        elseif ($item.Extension -eq ".zip") {
                            # It's a zip file - need to extract it
                            Write-Host "  Extracting ZIP file..." -ForegroundColor Cyan
                            try {
                                $extractPath = Join-Path -Path $env:TEMP -ChildPath "MDE_Offboarding_$([guid]::NewGuid())"
                                Expand-Archive -Path $userPath -DestinationPath $extractPath -Force -ErrorAction Stop
                                
                                $scripts = Get-ChildItem -Path $extractPath -Filter "*Offboarding*.cmd" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "WindowsDefenderATP.*Offboarding" }
                                if ($scripts) {
                                    $offboardingScriptPath = $scripts[0].FullName
                                    Write-Log "Extracted and found offboarding script: $offboardingScriptPath" -Level SUCCESS
                                    break
                                }
                                else {
                                    Write-Host "  No offboarding script found in the ZIP file." -ForegroundColor Red
                                }
                            }
                            catch {
                                Write-Host "  Failed to extract ZIP file: $($_.Exception.Message)" -ForegroundColor Red
                            }
                        }
                        elseif ($item.Extension -eq ".cmd") {
                            # It's a CMD file - verify it's an offboarding script
                            if ($item.Name -match "WindowsDefenderATP.*Offboarding") {
                                $offboardingScriptPath = $item.FullName
                                Write-Log "Found offboarding script: $offboardingScriptPath" -Level SUCCESS
                                break
                            }
                            else {
                                Write-Host "  The specified file does not appear to be a valid MDE offboarding script." -ForegroundColor Red
                            }
                        }
                        else {
                            Write-Host "  Invalid file type. Please provide a .cmd file, folder, or .zip file." -ForegroundColor Red
                        }
                    }
                    
                    # Check if we successfully found the script
                    if (-not $offboardingScriptPath -or -not (Test-Path -Path $offboardingScriptPath)) {
                        Write-Log "Could not locate offboarding package" -Level ERROR
                        return $false
                    }
                }
                "2" {
                    $validChoice = $true
                    Write-Host ""
                    Write-Host "  Opening Microsoft Defender portal..." -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "  Steps to download the offboarding package:" -ForegroundColor Yellow
                    Write-Host "    1. Sign in to the Microsoft Defender portal" -ForegroundColor White
                    Write-Host "    2. Select 'Windows Server 2019, 2022, and 2025'" -ForegroundColor White
                    Write-Host "    3. Select 'Local Script' as the deployment method" -ForegroundColor White
                    Write-Host "    4. Click 'Download offboarding package'" -ForegroundColor White
                    Write-Host "    5. Extract or save the offboarding script" -ForegroundColor White
                    Write-Host "    6. Return to this PowerShell session to continue" -ForegroundColor White
                    Write-Host ""
                    
                    # Check if Server Core - don't attempt to open browser
                    if (Test-IsServerCore) {
                        Write-Host "  [!] Server Core detected - browser cannot be opened automatically" -ForegroundColor Yellow
                        Write-Host "  Please navigate to the portal from another machine:" -ForegroundColor Yellow
                        Write-Host "  https://security.microsoft.com/securitysettings/endpoints/offboarding" -ForegroundColor Cyan
                    }
                    else {
                        Write-Host "  Press any key to open the portal in your browser..." -ForegroundColor Yellow
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        Write-Host ""
                        
                        try {
                            Start-Process "https://security.microsoft.com/securitysettings/endpoints/offboarding"
                            Write-Log "  Portal opened in browser" -Level INFO
                        }
                        catch {
                            Write-Log "Failed to open browser: $($_.Exception.Message)" -Level ERROR
                            Write-Host "  Please manually navigate to: https://security.microsoft.com/securitysettings/endpoints/offboarding" -ForegroundColor Yellow
                        }
                    }
                    
                    Write-Host ""
                    
                    # Now ask for the location
                    Write-Host "  Please provide the path to the downloaded offboarding package." -ForegroundColor Cyan
                    Write-Host "  You can provide:" -ForegroundColor White
                    Write-Host "    - Path to the .cmd file" -ForegroundColor White
                    Write-Host "    - Path to a folder containing the .cmd file" -ForegroundColor White
                    Write-Host "    - Path to a .zip file" -ForegroundColor White
                    Write-Host ""
                    
                    while ($true) {
                        $userPath = Read-Host "  Enter path (or type 'exit' to quit)"
                        
                        # Check if user wants to exit
                        if ($userPath -eq 'exit') {
                            Write-Log "  User chose to exit" -Level INFO
                            $script:SessionSummary.OnboardingStatus = "Cancelled"
                            Add-SessionAction -Action "User Exit" -Details "User typed 'exit' during offboarding package location" -Category "User"
                            Exit-WithSummary -ExitReason "User chose to exit during offboarding package selection" -ExitCode 0
                        }
                        
                        if ([string]::IsNullOrWhiteSpace($userPath)) {
                            Write-Host "  Path cannot be empty. Please try again." -ForegroundColor Yellow
                            continue
                        }
                        
                        # Remove quotes if present
                        $userPath = $userPath.Trim('"').Trim("'")
                        
                        if (-not (Test-Path -Path $userPath)) {
                            Write-Host "  Path not found: $userPath" -ForegroundColor Red
                            continue
                        }
                        
                        $item = Get-Item -Path $userPath
                        
                        if ($item.PSIsContainer) {
                            # It's a directory - search for offboarding script
                            $scripts = Get-ChildItem -Path $userPath -Filter "*Offboarding*.cmd" -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "WindowsDefenderATP.*Offboarding" }
                            if ($scripts) {
                                $offboardingScriptPath = $scripts[0].FullName
                                Write-Log "Found offboarding script: $offboardingScriptPath" -Level SUCCESS
                                break
                            }
                            else {
                                Write-Host "  No offboarding script found in the specified directory." -ForegroundColor Red
                            }
                        }
                        elseif ($item.Extension -eq ".zip") {
                            # It's a zip file - need to extract it
                            Write-Host "  Extracting ZIP file..." -ForegroundColor Cyan
                            try {
                                $extractPath = Join-Path -Path $env:TEMP -ChildPath "MDE_Offboarding_$([guid]::NewGuid())"
                                Expand-Archive -Path $userPath -DestinationPath $extractPath -Force -ErrorAction Stop
                                
                                $scripts = Get-ChildItem -Path $extractPath -Filter "*Offboarding*.cmd" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "WindowsDefenderATP.*Offboarding" }
                                if ($scripts) {
                                    $offboardingScriptPath = $scripts[0].FullName
                                    Write-Log "Extracted and found offboarding script: $offboardingScriptPath" -Level SUCCESS
                                    break
                                }
                                else {
                                    Write-Host "  No offboarding script found in the ZIP file." -ForegroundColor Red
                                }
                            }
                            catch {
                                Write-Host "  Failed to extract ZIP file: $($_.Exception.Message)" -ForegroundColor Red
                            }
                        }
                        elseif ($item.Extension -eq ".cmd") {
                            # It's a CMD file - verify it's an offboarding script
                            if ($item.Name -match "WindowsDefenderATP.*Offboarding") {
                                $offboardingScriptPath = $item.FullName
                                Write-Log "Found offboarding script: $offboardingScriptPath" -Level SUCCESS
                                break
                            }
                            else {
                                Write-Host "  The specified file does not appear to be a valid MDE offboarding script." -ForegroundColor Red
                            }
                        }
                        else {
                            Write-Host "  Invalid file type. Please provide a .cmd file, folder, or .zip file." -ForegroundColor Red
                        }
                    }
                    
                    # Check if we successfully found the script
                    if (-not $offboardingScriptPath -or -not (Test-Path -Path $offboardingScriptPath)) {
                        Write-Log "Could not locate offboarding package" -Level ERROR
                        return $false
                    }
                }
                default {
                    Write-Host "  Invalid choice. Please enter 1 or 2." -ForegroundColor Yellow
                }
            }
        }
    }
    
    Write-Log "Offboarding script found: $offboardingScriptPath" -Level SUCCESS
    Write-Host ""
    Write-Host "  WARNING: CRITICAL WARNING: OFFBOARDING CONSEQUENCES" -ForegroundColor Red
    Write-Host "  ===================================================" -ForegroundColor Red
    Write-Host "  This server will be REMOVED from Microsoft Defender for Endpoint" -ForegroundColor Yellow
    Write-Host "  MDE protection and monitoring will be DISABLED" -ForegroundColor Yellow
    Write-Host "  Security alerts and threat detection will STOP" -ForegroundColor Yellow
    Write-Host "  This action requires management approval to reverse" -ForegroundColor Yellow
    Write-Host ""
    
    if (-not (Get-UserConfirmation -Message "CONFIRM: Do you want to proceed with offboarding this server from MDE?" -DefaultYes $false)) {
        Write-Log "  Offboarding cancelled by user" -Level INFO
        Write-Host ""
        Write-Host "  Offboarding cancelled. Server remains protected by MDE." -ForegroundColor Green
        return $false
    }
    
    try {
        Write-Host "`nExecuting offboarding script..." -ForegroundColor Yellow
        Write-Host "Please wait...`n" -ForegroundColor Yellow
        
        Add-SessionAction -Action "Executing Offboarding Script" -Details "Running offboarding script: $offboardingScriptPath" -Category "Onboarding"
        
        # Execute the offboarding script
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$offboardingScriptPath`"" -Wait -NoNewWindow -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Log "Offboarding script completed successfully" -Level SUCCESS
            Add-SessionAction -Action "Offboarding Script Success" -Details "Offboarding script executed successfully" -Category "Onboarding"
            
            # Stop the Sense service
            Write-Log "  Stopping MDE services..." -Level INFO
            try {
                $senseService = Get-Service -Name "Sense" -ErrorAction SilentlyContinue
                if ($null -ne $senseService -and $senseService.Status -eq 'Running') {
                    Stop-Service -Name "Sense" -Force -ErrorAction Stop
                    Write-Log "Sense service stopped" -Level SUCCESS
                    Add-ConfigurationChange -Type "Service" -Description "Stopped Sense service during offboarding" -Location "Sense" -Success $true
                }
            }
            catch {
                Write-Log "Could not stop Sense service: $($_.Exception.Message)" -Level WARNING
            }
            
            # Verify offboarding
            Start-Sleep -Seconds 3
            $orgId = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status" -Name "OrgId" -ErrorAction SilentlyContinue
            if ($null -eq $orgId -or [string]::IsNullOrWhiteSpace($orgId.OrgId)) {
                Write-Log "Server successfully offboarded from MDE" -Level SUCCESS
            }
            else {
                Write-Log "Offboarding may take a few minutes to complete" -Level WARNING
            }
            
            return $true
        }
        else {
            Write-Log "Offboarding script failed with exit code: $($process.ExitCode)" -Level ERROR
            return $false
        }
    }
    catch {
        Write-Log "Failed to execute offboarding script: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Test-OnboardingSuccess {
    Write-Log "Verifying onboarding status..." -Level INFO
    Add-SessionAction -Action "Verification Started" -Details "Checking onboarding success indicators" -Category "Onboarding"
    
    Start-Sleep -Seconds 5
    
    try {
        # Check Sense service
        $senseService = Get-Service -Name "Sense" -ErrorAction SilentlyContinue
        if ($null -eq $senseService -or $senseService.Status -ne 'Running') {
            Write-Log "Sense service is not running" -Level WARNING
            Add-SessionAction -Action "Sense Service Check" -Details "Sense service not running - may need time to start" -Category "Verification"
        }
        else {
            Write-Log "Sense service is running" -Level SUCCESS
            Add-SessionAction -Action "Sense Service Check" -Details "Sense service is running successfully" -Category "Verification"
        }
        
        # Check registry for OrgId
        $orgId = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status" -Name "OrgId" -ErrorAction SilentlyContinue
        if ($null -ne $orgId -and ![string]::IsNullOrWhiteSpace($orgId.OrgId)) {
            Write-Log "Organization ID found: $(Get-ObfuscatedOrgId -OrgId $orgId.OrgId)" -Level SUCCESS
            Write-Log "Server successfully onboarded to MDE!" -Level SUCCESS
            Add-SessionAction -Action "Onboarding Verified" -Details "Organization ID confirmed: $(Get-ObfuscatedOrgId -OrgId $orgId.OrgId)" -Category "Verification"
            return $true
        }
        else {
            Write-Log "Organization ID not found in registry" -Level WARNING
            Write-Log "The server may take a few minutes to complete onboarding" -Level INFO
            Add-SessionAction -Action "OrgID Check" -Details "Organization ID not yet present - onboarding may still be in progress" -Category "Verification"
            return $true
        }
    }
    catch {
        Write-Log "Could not verify onboarding: $($_.Exception.Message)" -Level WARNING
        Add-SessionAction -Action "Verification Error" -Details "Error during verification: $($_.Exception.Message)" -Category "Verification"
        return $true
    }
}

function Show-PostOnboardingInfo {
    Write-Banner "Post-Onboarding Information"
    
    Write-Host "The onboarding process is complete. Please note the following:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. It may take 5-30 minutes for the server to appear in the MDE portal" -ForegroundColor White
    Write-Host "2. The time depends on internet connectivity and machine power state" -ForegroundColor White
    Write-Host "3. You can check the status in the Microsoft 365 Defender portal:" -ForegroundColor White
    Write-Host "   https://security.microsoft.com/machines" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "4. To run a detection test, execute the following command:" -ForegroundColor White
    Write-Host "   powershell.exe -NoExit -ExecutionPolicy Bypass -WindowStyle Hidden `$ErrorActionPreference = 'silentlycontinue';(New-Object System.Net.WebClient).DownloadFile('http://127.0.0.1/1.exe', 'C:\\test-MDATP-test\\invoice.exe');Start-Process 'C:\\test-MDATP-test\\invoice.exe'" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "5. Log file location: $script:LogFile" -ForegroundColor White
    Write-Host ""
}

function Show-ReadinessReport {
    param(
        [Parameter(Mandatory = $true)]
        [array]$CheckResults
    )
    
    Write-Banner "Server Readiness Report"
    
    $passedCount = ($CheckResults | Where-Object { $_.Passed -eq $true }).Count
    $failedCount = ($CheckResults | Where-Object { $_.Passed -eq $false }).Count
    $totalCount = $CheckResults.Count
    
    # Display summary statistics
    Write-Host "  Overall Status: " -NoNewline -ForegroundColor White
    if ($failedCount -eq 0) {
        Write-Host "READY FOR ONBOARDING" -ForegroundColor Green
    }
    else {
        Write-Host "NOT READY - $failedCount issue(s) found" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  Checks Passed: $passedCount / $totalCount" -ForegroundColor $(if ($passedCount -eq $totalCount) { 'Green' } else { 'Yellow' })
    Write-Host "  Checks Failed: $failedCount / $totalCount" -ForegroundColor $(if ($failedCount -eq 0) { 'Green' } else { 'Red' })
    Write-Host ""
    Write-Host ("-" * 80) -ForegroundColor White
    Write-Host ""
    
    # Display detailed results
    Write-Host "Detailed Results:" -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($result in $CheckResults) {
        $symbol = if ($result.Passed) { "" } else { "[X]" }
        $color = if ($result.Passed) { "Green" } else { "Red" }
        $status = if ($result.Passed) { "PASSED" } else { "FAILED" }
        
        Write-Host "  [$symbol] " -NoNewline -ForegroundColor $color
        Write-Host "$($result.Name): " -NoNewline -ForegroundColor White
        Write-Host "$status" -ForegroundColor $color
        
        # Show remediation steps for failed checks
        if (-not $result.Passed -and $result.Remediation) {
            Write-Host "      Remediation: $($result.Remediation)" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # Export report to file
    $reportPath = "$PSScriptRoot\MDE_Readiness_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $reportContent = @"
--------------------------------------------------------------------------------
Microsoft Defender for Endpoint - Server Readiness Report
--------------------------------------------------------------------------------
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Server: $env:COMPUTERNAME

Overall Status: $(if ($failedCount -eq 0) { "READY FOR ONBOARDING" } else { "NOT READY - $failedCount issue(s) found" })
Checks Passed: $passedCount / $totalCount
Checks Failed: $failedCount / $totalCount

--------------------------------------------------------------------------------
Detailed Results
--------------------------------------------------------------------------------

"@
    

    
    foreach ($result in $CheckResults) {
        $status = if ($result.Passed) { "PASSED" } else { "FAILED" }
        $reportContent += "$status - $($result.Name)`n"
        if (-not $result.Passed -and $result.Remediation) {
            $reportContent += "  Remediation: $($result.Remediation)`n"
        }
        $reportContent += "`n"
    }
    
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "  [INFO] Full report saved to: $reportPath" -ForegroundColor Cyan
    Write-Host ""
}

function Get-RemediationSteps {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CheckName
    )
    
    $remediations = @{
        "Operating System Version" = "Upgrade to Windows Server 2019 or higher. Visit: https://www.microsoft.com/en-us/windows-server"
        "Disk Space" = "Free up disk space on the system drive. Delete unnecessary files or extend the volume."
        "Internet Connectivity" = "Check firewall rules and proxy settings. Ensure access to MDE endpoints: https://docs.microsoft.com/en-us/microsoft-365/security/defender-endpoint/configure-proxy-internet"
        "Windows Defender Services" = "Critical Windows Defender services (WinDefend, Sense) must be enabled and running. Check if services are disabled, stopped, or missing. May require Windows Defender feature installation."
        "Windows Defender Platform" = "Install Windows Defender or update Windows. Run: Update-MpSignature"
        "Windows Defender Platform Directory" = "Install or repair Windows Defender Antimalware. Run: Add-WindowsFeature -Name Windows-Defender or use DISM: DISM /Online /Enable-Feature /FeatureName:Windows-Defender"
        "Windows Defender Platform Version" = "Update Windows Defender platform and signatures. Run: Update-MpSignature or use Windows Update"
        "Group Policy" = "Contact your domain administrator to modify Group Policy settings for Windows Defender"
        "Onboarding Script" = "Download the onboarding package from Microsoft 365 Defender portal: https://security.microsoft.com/securitysettings/endpoints/onboarding"
        "Existing Onboarding" = "Server is already onboarded. Choose to re-onboard or cancel the process."
    }
    
    if ($remediations.ContainsKey($CheckName)) {
        return $remediations[$CheckName]
    }
    return "Please review the error messages above for more information."
}

function Start-InteractiveRemediation {
    param(
        [Parameter(Mandatory = $true)]
        [array]$FailedChecks
    )
    
    Write-Banner "Interactive Remediation Assistant"
    
    Write-Host "The following issues were detected. Let's try to fix them:`n" -ForegroundColor Cyan
    
    $remediationSuccess = $true
    
    foreach ($check in $FailedChecks) {
        Write-Host ("-" * 80) -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Issue: " -NoNewline -ForegroundColor Yellow
        Write-Host "$($check.Name)" -ForegroundColor White
        Write-Host "Remediation: " -NoNewline -ForegroundColor Yellow
        Write-Host "$($check.Remediation)" -ForegroundColor White
        Write-Host ""
        
        switch ($check.Name) {
            "Windows Defender Services" {
                # Show what changes will be made before asking confirmation
                Write-Host ""
                Write-Host "  WINDOWS DEFENDER SERVICE FIXES REQUIRED:" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  The following system changes will be made:" -ForegroundColor White
                
                if ($script:DefenderServiceIssues -and $script:DefenderServiceIssues.Count -gt 0) {
                    foreach ($issue in $script:DefenderServiceIssues) {
                        $svcName = $issue.Service.Name
                        $svcDisplayName = $issue.Service.DisplayName
                        
                        Write-Host "    Service: $svcDisplayName ($svcName)" -ForegroundColor Cyan
                        Write-Host "      Issue: $($issue.Issue)" -ForegroundColor White
                        
                        switch ($issue.Issue) {
                            "Disabled" {
                                Write-Host "      Change: Set startup type to Automatic" -ForegroundColor Yellow
                                Write-Host "      Registry: HKLM:\SYSTEM\CurrentControlSet\Services\$svcName" -ForegroundColor Gray
                                Write-Host "      Key: Start = 2 (Automatic)" -ForegroundColor Gray
                                Write-Host "      Action: Start the service" -ForegroundColor Yellow
                            }
                            "ManualStartup" {
                                Write-Host "      Change: Set startup type from Manual to Automatic" -ForegroundColor Yellow
                                Write-Host "      Registry: HKLM:\SYSTEM\CurrentControlSet\Services\$svcName" -ForegroundColor Gray
                                Write-Host "      Key: Start = 2 (Automatic)" -ForegroundColor Gray
                                Write-Host "      Reason: Critical services should start automatically" -ForegroundColor White
                            }
                            "Stopped" {
                                Write-Host "      Action: Start the service" -ForegroundColor Yellow
                            }
                            "NotFound" {
                                Write-Host "      Issue: Service not installed (manual intervention required)" -ForegroundColor Red
                            }
                        }
                        Write-Host ""
                    }
                }
                else {
                    Write-Host "  Enable and start critical Windows Defender services" -ForegroundColor Cyan
                    Write-Host "  Modify registry keys for service startup configuration" -ForegroundColor Cyan
                    Write-Host "  Verify service operational status" -ForegroundColor Cyan
                }
                Write-Host ""
                
                # Use the comprehensive service repair function
                $repairResult = Repair-DefenderServices
                
                if ($repairResult) {
                    Write-Host "  [REPAIR] Windows Defender services have been successfully repaired" -ForegroundColor Green
                    Add-SessionAction -Action "Service Repair Success" -Details "Windows Defender services successfully repaired using comprehensive repair function" -Category "Remediation"
                }
                else {
                    Write-Host "  [WARNING] Service repair completed with some issues" -ForegroundColor Yellow
                    Write-Host "  Some services may require manual intervention or system restart" -ForegroundColor Yellow
                    $remediationSuccess = $false
                }
            }
            
            "Windows Defender Platform" {
                Write-Host ""
                Write-Host "    WINDOWS DEFENDER PLATFORM ENABLEMENT:" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "    Change to be made:" -ForegroundColor White
                Write-Host "    Set Windows Defender real-time monitoring: Enabled" -ForegroundColor Cyan
                Write-Host "    Registry path: HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection" -ForegroundColor Cyan
                Write-Host "    Registry key: DisableRealtimeMonitoring = 0" -ForegroundColor Cyan
                Write-Host ""
                
                if (Get-UserConfirmation -Message "ENABLE: Windows Defender platform now?" -DefaultYes $true) {
                    Write-Host "  Setting Windows Defender preference..." -ForegroundColor Cyan
                    try {
                        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
                        Write-Host "    Windows Defender Antivirus enabled successfully" -ForegroundColor Green
                        Write-Host "    Registry change completed: DisableRealtimeMonitoring = 0" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "    [X] Failed to enable Windows Defender: $($_.Exception.Message)" -ForegroundColor Red
                        $remediationSuccess = $false
                    }
                }
                else {
                    $remediationSuccess = $false
                }
            }
            
            "Windows Defender Platform Directory" {
                Write-Host "  Action Required: Install or repair Windows Defender Antimalware" -ForegroundColor Yellow
                Write-Host "    The Windows Defender platform directory is missing or incomplete." -ForegroundColor White
                Write-Host "    This is critical for MDE onboarding." -ForegroundColor White
                Write-Host ""
                Write-Host "    WINDOWS DEFENDER FEATURE INSTALLATION:" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "    System changes to be made:" -ForegroundColor White
                Write-Host "    Install Windows Defender feature using Windows Feature management" -ForegroundColor Cyan
                Write-Host "    Feature name: Windows-Defender" -ForegroundColor Cyan
                Write-Host "    Installation method: Install-WindowsFeature cmdlet" -ForegroundColor Cyan
                Write-Host "    System restart: May be required after installation" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "    This will:" -ForegroundColor White
                Write-Host "    Add Windows Defender core components to the system" -ForegroundColor White
                Write-Host "    Create necessary service definitions and registry entries" -ForegroundColor White
                Write-Host "    Enable antivirus and antimalware capabilities" -ForegroundColor White
                Write-Host ""
                
                if (Get-UserConfirmation -Message "INSTALL: Windows Defender feature?" -DefaultYes $true) {
                    Write-Host "  Installing Windows Defender feature..." -ForegroundColor Cyan
                    try {
                        # Try to install Windows Defender feature
                        $feature = Get-WindowsFeature -Name Windows-Defender -ErrorAction SilentlyContinue
                        if ($null -ne $feature -and -not $feature.Installed) {
                            Write-Host "    Installing Windows Defender feature..." -ForegroundColor Cyan
                            Install-WindowsFeature -Name Windows-Defender -ErrorAction Stop
                            Write-Host "    Windows Defender feature installed" -ForegroundColor Green
                            Write-Host "    [!] A system restart may be required" -ForegroundColor Yellow
                        }
                        elseif ($null -ne $feature -and $feature.Installed) {
                            Write-Host "    [!] Windows Defender feature is already installed but platform directory is missing" -ForegroundColor Yellow
                            Write-Host "    Run DISM repair: DISM /Online /Cleanup-Image /RestoreHealth" -ForegroundColor Cyan
                        }
                        else {
                            Write-Host "    [!] Windows Defender feature not available on this system" -ForegroundColor Yellow
                            Write-Host "    Manual installation required" -ForegroundColor Yellow
                        }
                    }
                    catch {
                        Write-Host "    [X] Failed to install Windows Defender: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                $remediationSuccess = $false
            }
            
            "Windows Defender Platform Version" {
                Write-Host ""
                Write-Host "    WINDOWS DEFENDER PLATFORM UPDATE:" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "    Updates to be downloaded and installed:" -ForegroundColor White
                Write-Host "    Latest Windows Defender platform binaries" -ForegroundColor Cyan
                Write-Host "    Current antivirus signature definitions" -ForegroundColor Cyan
                Write-Host "    Anti-spyware definition updates" -ForegroundColor Cyan
                Write-Host "    Network Inspection System signatures" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "    Update process:" -ForegroundColor White
                Write-Host "    Source: Microsoft Update servers" -ForegroundColor White
                Write-Host "    Method: Update-MpSignature cmdlet" -ForegroundColor White
                Write-Host "    Network access: Required for download" -ForegroundColor White
                Write-Host ""
                
                if (Get-UserConfirmation -Message "UPDATE: Windows Defender platform and signatures?" -DefaultYes $true) {
                    Write-Host "  Downloading and installing platform updates..." -ForegroundColor Cyan
                    try {
                        Update-MpSignature -ErrorAction Stop
                        Write-Host "    Platform and signatures updated successfully" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "    [X] Failed to update platform: $($_.Exception.Message)" -ForegroundColor Red
                        Write-Host "    Try running Windows Update or manually downloading updates" -ForegroundColor Yellow
                        $remediationSuccess = $false
                    }
                }
                else {
                    $remediationSuccess = $false
                }
            }
            
            "Onboarding Script" {
                Write-Host "  Action Required: Download the onboarding package manually" -ForegroundColor Yellow
                if (Get-UserConfirmation -Message "Would you like to open the MDE portal now?" -DefaultYes $true) {
                    try {
                        Start-Process "https://security.microsoft.com/securitysettings/endpoints/onboarding"
                        Write-Host "    Opening MDE portal in browser..." -ForegroundColor Green
                        Write-Host "    Please download the onboarding package and extract it to:" -ForegroundColor Cyan
                        Write-Host "    $PSScriptRoot\GatewayWindowsDefenderATPOnboardingPackage\" -ForegroundColor Yellow
                    }
                    catch {
                        Write-Host "    [X] Failed to open browser: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                $remediationSuccess = $false
            }
            
            "Internet Connectivity" {
                Write-Host "  Action Required: Check network and firewall configuration" -ForegroundColor Yellow
                if (Get-UserConfirmation -Message "Would you like to open the MDE network requirements documentation?" -DefaultYes $true) {
                    try {
                        Start-Process "https://docs.microsoft.com/en-us/microsoft-365/security/defender-endpoint/configure-proxy-internet"
                        Write-Host "    Opening documentation in browser..." -ForegroundColor Green
                    }
                    catch {
                        Write-Host "    [X] Failed to open browser: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                $remediationSuccess = $false
            }
            
            "Group Policy" {
                Write-Host "  Action Required: Contact your domain administrator" -ForegroundColor Yellow
                Write-Host "    Windows Defender is disabled by Group Policy and requires administrative intervention." -ForegroundColor White
                $remediationSuccess = $false
            }
            
            "Disk Space" {
                Write-Host "  Action Required: Free up disk space manually" -ForegroundColor Yellow
                if (Get-UserConfirmation -Message "Would you like to see disk space usage?" -DefaultYes $true) {
                    Write-Host ""
                    Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | ForEach-Object {
                        $freeGB = [math]::Round($_.FreeSpace / 1GB, 2)
                        $totalGB = [math]::Round($_.Size / 1GB, 2)
                        $percentFree = [math]::Round(($_.FreeSpace / $_.Size) * 100, 2)
                        Write-Host "    Drive $($_.DeviceID) - Free: $freeGB GB / $totalGB GB ($percentFree%)" -ForegroundColor Cyan
                    }
                    Write-Host ""
                }
                $remediationSuccess = $false
            }
            
            "Operating System Version" {
                Write-Host "  Action Required: OS upgrade required" -ForegroundColor Yellow
                Write-Host "    This server does not meet the minimum OS requirements." -ForegroundColor White
                Write-Host "    Required: Windows Server 2019 (Build 17763) or higher" -ForegroundColor White
                $remediationSuccess = $false
            }
            
            default {
                Write-Host "  Manual intervention required" -ForegroundColor Yellow
                $remediationSuccess = $false
            }
        }
        
        Write-Host ""
    }
    
    return $remediationSuccess
}

function Get-DefenderOperationalMode {
    <#
    .SYNOPSIS
        Gets the current operational mode of Windows Defender.
    #>
    try {
        $defenderStatus = Get-MpComputerStatus -ErrorAction Stop
        
        # Check for passive mode registry key
        $passiveModeKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection" -Name "ForceDefenderPassiveMode" -ErrorAction SilentlyContinue
        
        if ($passiveModeKey -and $passiveModeKey.ForceDefenderPassiveMode -eq 1) {
            return "Passive (Forced)"
        }
        
        # Check AMRunningMode
        if ($defenderStatus.AMRunningMode) {
            switch ($defenderStatus.AMRunningMode) {
                "Normal" { return "Active" }
                "Passive" { return "Passive" }
                "EDR Block Mode" { return "EDR Block" }
                "SxS Passive Mode" { return "SxS Passive" }
                default { return $defenderStatus.AMRunningMode }
            }
        }
        
        # Fallback based on service status
        if ($defenderStatus.AntivirusEnabled) {
            return "Active"
        }
        else {
            return "Disabled or Passive"
        }
    }
    catch {
        return "Unknown"
    }
}

function Test-ThirdPartyAntivirus {
    <#
    .SYNOPSIS
        Checks for the presence of third-party antivirus software.
    #>
    Write-Log "Checking for third-party antivirus software..." -Level INFO
    
    $detectedAV = @()
    
    try {
        # Method 1: Check using SecurityCenter2 (Windows 8+)
        Write-Log "Checking Windows Security Center..." -Level INFO
        $avProducts = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "AntiVirusProduct" -ErrorAction SilentlyContinue
        
        if ($avProducts) {
            $thirdPartyAV = $avProducts | Where-Object { $_.displayName -notmatch "Windows Defender|Microsoft Defender" }
            
            if ($thirdPartyAV) {
                foreach ($av in $thirdPartyAV) {
                    $detectedAV += $av.displayName
                    Write-Log "Found: $($av.displayName)" -Level INFO
                }
            }
        }
    }
    catch {
        Write-Log "Could not check SecurityCenter2: $($_.Exception.Message)" -Level WARNING
    }
    
    try {
        # Method 2: Check for common AV processes
        Write-Log "Checking running processes..." -Level INFO
        $avProcesses = @(
            'mbam',           # Malwarebytes Anti-Malware
            'mbamservice',    # Malwarebytes Service
            'mbamtray',       # Malwarebytes Tray
            'avp',            # Kaspersky
            'avgnt',          # Avira
            'avguard',        # Avira Guard
            'avgidsagent',    # AVG
            'avgsvc',         # AVG Service
            'avgwdsvc',       # AVG WatchDog
            'sophossps',      # Sophos
            'savservice',     # Sophos Endpoint
            'mcshield',       # McAfee
            'mfemms',         # McAfee
            'mfevtp',         # McAfee
            'ntrtscan',       # Trend Micro
            'tmproxy',        # Trend Micro
            'ccevtmgr',       # Norton/Symantec
            'ccapp',          # Norton Application
            'rtvscan',        # Norton Real-time Scanner
            'bdagent',        # Bitdefender
            'vsserv',         # Bitdefender Core Service
            'fsma32',         # F-Secure
            'fsgk32st',       # F-Secure Gatekeeper
            'wrsa',           # Webroot
            'wrsvc',          # Webroot Service
            'ekrn',           # ESET
            'egui',           # ESET GUI
            'aswidsagent',    # Avast
            'avastui',        # Avast UI
            'avastsvc',       # Avast Service
            'psanhost',       # Panda Security
            'pavfnsvr',       # Panda Antivirus
            'zlclient'        # ZoneAlarm
        )
        
        $runningAVProcesses = Get-Process | Where-Object { 
            $processName = $_.ProcessName.ToLower()
            $avProcesses | ForEach-Object { 
                if ($processName -like "*$_*") { return $true }
            }
        }
        
        if ($runningAVProcesses) {
            foreach ($proc in $runningAVProcesses) {
                $productName = "Unknown AV Product (Process: $($proc.ProcessName))"
                
                # Try to get the product name from file description
                try {
                    if ($proc.MainModule -and $proc.MainModule.FileName) {
                        $fileInfo = Get-ItemProperty -Path $proc.MainModule.FileName -ErrorAction SilentlyContinue
                        if ($fileInfo -and $fileInfo.VersionInfo.ProductName) {
                            $productName = $fileInfo.VersionInfo.ProductName
                        }
                    }
                }
                catch { }
                
                if ($detectedAV -notcontains $productName) {
                    $detectedAV += $productName
                    Write-Log "Found: $productName" -Level INFO
                }
            }
        }
    }
    catch {
        Write-Log "Could not check running processes: $($_.Exception.Message)" -Level WARNING
    }
    
    try {
        # Method 3: Check registry for installed security software
        Write-Log "Checking installed programs..." -Level INFO
        $uninstallKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        $avKeywords = @(
            'antivirus', 'anti-virus', 'malwarebytes', 'kaspersky', 'avira', 'avg', 
            'sophos', 'mcafee', 'trend micro', 'norton', 'symantec', 'bitdefender', 
            'f-secure', 'webroot', 'eset', 'avast', 'panda', 'zonealarm',
            'endpoint protection', 'security essentials', 'internet security'
        )
        
        foreach ($keyPath in $uninstallKeys) {
            $installedPrograms = Get-ItemProperty -Path $keyPath -ErrorAction SilentlyContinue | 
                Where-Object { 
                    $_.DisplayName -and 
                    $_.DisplayName -notmatch "Windows Defender|Microsoft Defender|Windows Security" 
                }
            
            foreach ($program in $installedPrograms) {
                $displayName = $program.DisplayName.ToLower()
                
                foreach ($keyword in $avKeywords) {
                    if ($displayName -like "*$keyword*") {
                        if ($detectedAV -notcontains $program.DisplayName) {
                            $detectedAV += $program.DisplayName
                            Write-Log "Found: $($program.DisplayName)" -Level INFO
                        }
                        break
                    }
                }
            }
        }
    }
    catch {
        Write-Log "Could not check installed programs: $($_.Exception.Message)" -Level WARNING
    }
    
    try {
        # Method 4: Check for specific Malwarebytes registry entries
        Write-Log "Checking for Malwarebytes specific entries..." -Level INFO
        $mbKeys = @(
            "HKLM:\SOFTWARE\Malwarebytes",
            "HKLM:\SOFTWARE\WOW6432Node\Malwarebytes",
            "HKLM:\SYSTEM\CurrentControlSet\Services\MBAMService",
            "HKLM:\SYSTEM\CurrentControlSet\Services\mbamchameleon",
            "HKLM:\SYSTEM\CurrentControlSet\Services\MBAMWebAccessControl"
        )
        
        foreach ($mbKey in $mbKeys) {
            if (Test-Path -Path $mbKey) {
                if ($detectedAV -notcontains "Malwarebytes") {
                    $detectedAV += "Malwarebytes (Registry Detection)"
                    Write-Log "Found: Malwarebytes (Registry Detection)" -Level INFO
                }
                break
            }
        }
    }
    catch {
        Write-Log "Could not check Malwarebytes registry: $($_.Exception.Message)" -Level WARNING
    }
    
    # Report results
    if ($detectedAV.Count -gt 0) {
        Write-Log "Third-party security software detected:" -Level WARNING
        foreach ($av in $detectedAV) {
            Write-Log "$av" -Level WARNING
        }
        return $true
    }
    else {
        Write-Log "No third-party antivirus detected" -Level SUCCESS
        return $false
    }
}

function Set-DefenderPassiveMode {
    <#
    .SYNOPSIS
        Sets Windows Defender to passive mode via registry.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enable
    )
    
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection"
    $regName = "ForceDefenderPassiveMode"
    
    try {
        if ($Enable) {
            Write-Host ""
            Write-Host "  REGISTRY CHANGES TO BE MADE:" -ForegroundColor Yellow
            Write-Host "  =============================" -ForegroundColor Yellow
            Write-Host "    Location: $regPath" -ForegroundColor Cyan
            Write-Host "    Value:    $regName = 1 (DWORD)" -ForegroundColor Cyan
            Write-Host "    Purpose:  Force Windows Defender into Passive Mode" -ForegroundColor White
            Write-Host "    Effect:   Allows third-party AV to be primary, Defender provides EDR only" -ForegroundColor White
            Write-Host ""
            
            # Create registry path if it doesn't exist
            if (-not (Test-Path -Path $regPath)) {
                Write-Log "Creating registry path: $regPath" -Level INFO
                New-Item -Path $regPath -Force | Out-Null
                Write-Log "Registry path created successfully" -Level SUCCESS
            }
            
            Write-Log "Setting registry value: $regPath\$regName = 1" -Level INFO
            Set-ItemProperty -Path $regPath -Name $regName -Value 1 -Type DWord -ErrorAction Stop
            Write-Log "Windows Defender set to Passive Mode" -Level SUCCESS
            
            Add-ConfigurationChange -Type "Registry" -Description "Enabled Windows Defender Passive Mode" -Location $regPath -Success $true
            Add-SessionAction -Action "Passive Mode Enabled" -Details "Windows Defender set to passive mode for third-party AV compatibility" -Category "Configuration"
            
            Write-Host "  REGISTRY CHANGE COMPLETED:" -ForegroundColor Green
            Write-Host "    Status: Windows Defender is now in Passive Mode" -ForegroundColor Green
            Write-Host "    Result: Third-party antivirus can operate as primary protection" -ForegroundColor Green
            Write-Host ""
            return $true
        }
        else {
            Write-Host ""
            Write-Host "  REGISTRY CHANGES TO BE MADE:" -ForegroundColor Yellow
            Write-Host "  =============================" -ForegroundColor Yellow
            Write-Host "    Location: $regPath" -ForegroundColor Cyan
            Write-Host "    Action:   Remove $regName value" -ForegroundColor Cyan
            Write-Host "    Purpose:  Disable Forced Passive Mode" -ForegroundColor White
            Write-Host "    Effect:   Allow Windows Defender normal operation" -ForegroundColor White
            Write-Host ""
            
            # Remove the key to allow normal operation
            Write-Log "Removing registry value: $regPath\$regName" -Level INFO
            $keyExisted = Test-Path -Path "$regPath" -ErrorAction SilentlyContinue
            if ($keyExisted) {
                $valueExists = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
                if ($valueExists) {
                    Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
                    Write-Log "Windows Defender Passive Mode disabled" -Level SUCCESS
                    Add-ConfigurationChange -Type "Registry" -Description "Disabled Windows Defender Passive Mode" -Location $regPath -Success $true
                    Add-SessionAction -Action "Passive Mode Disabled" -Details "Windows Defender restored to active mode" -Category "Configuration"
                    Write-Host "  REGISTRY CHANGE COMPLETED:" -ForegroundColor Green
                    Write-Host "    Action: Removed $regName value" -ForegroundColor Cyan
                    Write-Host "    Effect: Allows Windows Defender to operate in Active Mode" -ForegroundColor Yellow
                }
                else {
                    Write-Log "Passive Mode was already disabled (registry value not present)" -Level SUCCESS
                    Add-SessionAction -Action "Passive Mode Check" -Details "Passive Mode was already disabled" -Category "Configuration"
                    Write-Host "  No registry change needed - Passive Mode was already disabled" -ForegroundColor Green
                }
            }
            else {
                Write-Log "Passive Mode was already disabled (registry path not present)" -Level SUCCESS
                Write-Host "  No registry change needed - Passive Mode was already disabled" -ForegroundColor Green
            }
            return $true
        }
    }
    catch {
        Write-Log "Failed to set Defender mode: $($_.Exception.Message)" -Level ERROR
        Write-Host "  Registry Change Failed:" -ForegroundColor Red
        Write-Host "    Target: $regPath\$regName" -ForegroundColor Yellow
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-DefenderPassiveMode {
    <#
    .SYNOPSIS
        Checks if Defender should be in passive mode and configures it accordingly.
    #>
    Write-Log "Checking Windows Defender operational mode..." -Level INFO
    
    # Check for third-party AV
    $hasThirdPartyAV = Test-ThirdPartyAntivirus
    
    # Get current Defender mode
    $currentMode = Get-DefenderOperationalMode
    Write-Log "  Current Defender Mode: $currentMode" -Level INFO
    
    # Check passive mode registry setting
    $passiveModeKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection" -Name "ForceDefenderPassiveMode" -ErrorAction SilentlyContinue
    $isPassiveModeSet = ($passiveModeKey -and $passiveModeKey.ForceDefenderPassiveMode -eq 1)
    
    if ($hasThirdPartyAV) {
        Write-Log "Third-party antivirus detected" -Level WARNING
        
        if (-not $isPassiveModeSet) {
            Write-Host ""
            Write-Host "  WARNING: THIRD-PARTY ANTIVIRUS DETECTED" -ForegroundColor Yellow
            Write-Host "  =====================================" -ForegroundColor Yellow
            Write-Host "    - Third-party antivirus software is running on this server" -ForegroundColor White
            Write-Host "    - Windows Defender should be set to Passive Mode" -ForegroundColor White
            Write-Host "    - This prevents conflicts between security products" -ForegroundColor White
            Write-Host "    - MDE will still provide endpoint detection and response" -ForegroundColor White
            Write-Host ""
            Write-Host "  RECOMMENDATION: Enable Passive Mode for optimal compatibility" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  REGISTRY CHANGES TO BE MADE:" -ForegroundColor Yellow
            Write-Host "    Location: HKLM:\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection" -ForegroundColor Cyan
            Write-Host "    Value: ForceDefenderPassiveMode = 1 (DWORD)" -ForegroundColor Cyan
            Write-Host "    Purpose: Force Windows Defender into Passive Mode" -ForegroundColor White
            Write-Host "    Effect: Allows third-party AV to be primary, Defender provides EDR only" -ForegroundColor White
            Write-Host ""
            
            if (Get-UserConfirmation -Message "CONFIGURE: Set Windows Defender to Passive Mode?" -DefaultYes $true) {
                return Set-DefenderPassiveMode -Enable $true
            }
            else {
                Write-Log "User declined to set Passive Mode - may cause conflicts" -Level WARNING
                Write-Host ""
                Write-Host "  WARNING:  WARNING: Proceeding without Passive Mode may cause conflicts" -ForegroundColor Yellow
                return $true
            }
        }
        else {
            Write-Log "Passive Mode is already configured" -Level SUCCESS
            return $true
        }
    }
    else {
        if ($isPassiveModeSet) {
            Write-Log "Passive Mode is set but no third-party AV detected" -Level WARNING
            Write-Host ""
            Write-Host "  WINDOWS DEFENDER PASSIVE MODE DISABLEMENT:" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Current situation:" -ForegroundColor White
            Write-Host "  Windows Defender is in Passive Mode" -ForegroundColor White
            Write-Host "  No third-party antivirus detected" -ForegroundColor White
            Write-Host "  System has limited real-time protection" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Registry change to be made:" -ForegroundColor White
            Write-Host "  Path: HKLM:\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection" -ForegroundColor Cyan
            Write-Host "  Action: Remove ForceDefenderPassiveMode key" -ForegroundColor Cyan
            Write-Host "  Result: Windows Defender will provide full active protection" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  This will restore:" -ForegroundColor White
            Write-Host "  Real-time file and process scanning" -ForegroundColor White
            Write-Host "  Active threat detection and remediation" -ForegroundColor White
            Write-Host "  Full Windows Defender protection capabilities" -ForegroundColor White
            Write-Host ""
            
            if (Get-UserConfirmation -Message "DISABLE: Passive Mode to enable full Windows Defender protection?" -DefaultYes $true) {
                return Set-DefenderPassiveMode -Enable $false
            }
        }
        
        Write-Log "Defender mode is appropriate for current configuration" -Level SUCCESS
        return $true
    }
}

#endregion

#region Session Tracking Functions

function Add-SessionAction {
    <#
    .SYNOPSIS
        Adds an action to the session summary tracking.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,
        
        [Parameter(Mandatory = $false)]
        [string]$Details = "",
        
        [Parameter(Mandatory = $false)]
        [string]$Category = "General"
    )
    
    $script:SessionSummary.ActionsPerformed += @{
        Timestamp = Get-Date
        Action = $Action
        Details = $Details
        Category = $Category
    }
}

function Add-CheckResult {
    <#
    .SYNOPSIS
        Records the result of a prerequisite check.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$CheckName,
        
        [Parameter(Mandatory = $true)]
        [bool]$Passed,
        
        [Parameter(Mandatory = $false)]
        [string]$Details = ""
    )
    
    $script:SessionSummary.ChecksCompleted += @{
        CheckName = $CheckName
        Passed = $Passed
        Details = $Details
        Timestamp = Get-Date
    }
}

function Add-ConfigurationChange {
    <#
    .SYNOPSIS
        Records a configuration change made during the session.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type,
        
        [Parameter(Mandatory = $true)]
        [string]$Description,
        
        [Parameter(Mandatory = $false)]
        [string]$Location = "",
        
        [Parameter(Mandatory = $false)]
        [bool]$Success = $true
    )
    
    $change = @{
        Type = $Type
        Description = $Description
        Location = $Location
        Success = $Success
        Timestamp = Get-Date
    }
    
    switch ($Type) {
        "Registry" { $script:SessionSummary.RegistryChanges += $change }
        "Service" { $script:SessionSummary.ServicesModified += $change }
        default { $script:SessionSummary.ConfigurationChanges += $change }
    }
}

function Set-ScriptPhase {
    <#
    .SYNOPSIS
        Updates the current phase of the script execution.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Phase
    )
    
    $script:SessionSummary.ScriptPhase = $Phase
    Add-SessionAction -Action "Phase Changed" -Details "Entered: $Phase" -Category "Navigation"
}

function Show-SessionSummary {
    <#
    .SYNOPSIS
        Displays a comprehensive summary of what was accomplished during the session.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$ExitReason = "User Exit"
    )
    
    $script:SessionSummary.ExitReason = $ExitReason
    $duration = (Get-Date) - $script:SessionSummary.StartTime
    
    # Create summary display
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host "  MICROSOFT DEFENDER FOR ENDPOINT - SESSION SUMMARY" -ForegroundColor White
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Session Information:" -ForegroundColor Yellow
    Write-Host "    Start Time: $($script:SessionSummary.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    Write-Host "    End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
    Write-Host "    Duration: $($duration.Hours)h $($duration.Minutes)m $($duration.Seconds)s" -ForegroundColor White
    Write-Host "    Final Phase: $($script:SessionSummary.ScriptPhase)" -ForegroundColor White
    Write-Host "    Exit Reason: $ExitReason" -ForegroundColor White
    Write-Host "    Onboarding Status: $($script:SessionSummary.OnboardingStatus)" -ForegroundColor $(if ($script:SessionSummary.OnboardingStatus -eq "Completed") { "Green" } elseif ($script:SessionSummary.OnboardingStatus -eq "Failed") { "Red" } else { "Yellow" })
    Write-Host ""
    
    # Show checks completed
    if ($script:SessionSummary.ChecksCompleted.Count -gt 0) {
        $passedChecks = ($script:SessionSummary.ChecksCompleted | Where-Object { $_.Passed }).Count
        $failedChecks = ($script:SessionSummary.ChecksCompleted | Where-Object { -not $_.Passed }).Count
        
        Write-Host "  Prerequisite Checks Completed: $($script:SessionSummary.ChecksCompleted.Count)" -ForegroundColor Yellow
        Write-Host "    Passed: $passedChecks" -ForegroundColor $(if ($passedChecks -gt 0) { "Green" } else { "Gray" })
        Write-Host "    Failed: $failedChecks" -ForegroundColor $(if ($failedChecks -gt 0) { "Red" } else { "Gray" })
        
        if ($failedChecks -gt 0) {
            Write-Host ""
            Write-Host "  Failed Checks:" -ForegroundColor Red
            foreach ($check in ($script:SessionSummary.ChecksCompleted | Where-Object { -not $_.Passed })) {
                Write-Host "    [X] $($check.CheckName)" -ForegroundColor Red
                if ($check.Details) {
                    Write-Host "      $($check.Details)" -ForegroundColor Gray
                }
            }
        }
        Write-Host ""
    }
    
    # Show configuration changes
    $totalChanges = $script:SessionSummary.ConfigurationChanges.Count + 
                   $script:SessionSummary.RegistryChanges.Count + 
                   $script:SessionSummary.ServicesModified.Count
    
    if ($totalChanges -gt 0) {
        Write-Host "  Configuration Changes Made: $totalChanges" -ForegroundColor Yellow
        
        if ($script:SessionSummary.RegistryChanges.Count -gt 0) {
            Write-Host "    Registry Changes: $($script:SessionSummary.RegistryChanges.Count)" -ForegroundColor Cyan
            foreach ($change in $script:SessionSummary.RegistryChanges) {
                $status = if ($change.Success) { "[OK]" } else { "[X]" }
                $color = if ($change.Success) { "Green" } else { "Red" }
                Write-Host "      $status $($change.Description)" -ForegroundColor $color
                if ($change.Location) {
                    Write-Host "        Location: $($change.Location)" -ForegroundColor Gray
                }
            }
        }
        
        if ($script:SessionSummary.ServicesModified.Count -gt 0) {
            Write-Host "    Service Changes: $($script:SessionSummary.ServicesModified.Count)" -ForegroundColor Cyan
            foreach ($change in $script:SessionSummary.ServicesModified) {
                $status = if ($change.Success) { "[OK]" } else { "[X]" }
                $color = if ($change.Success) { "Green" } else { "Red" }
                Write-Host "      $status $($change.Description)" -ForegroundColor $color
            }
        }
        
        if ($script:SessionSummary.ConfigurationChanges.Count -gt 0) {
            Write-Host "    Other Changes: $($script:SessionSummary.ConfigurationChanges.Count)" -ForegroundColor Cyan
            foreach ($change in $script:SessionSummary.ConfigurationChanges) {
                $status = if ($change.Success) { "[OK]" } else { "[X]" }
                $color = if ($change.Success) { "Green" } else { "Red" }
                Write-Host "      $status $($change.Description)" -ForegroundColor $color
            }
        }
        Write-Host ""
    }
    
    # Show updates installed
    if ($script:SessionSummary.UpdatesInstalled.Count -gt 0) {
        Write-Host "  Windows Updates Installed: $($script:SessionSummary.UpdatesInstalled.Count)" -ForegroundColor Yellow
        foreach ($update in $script:SessionSummary.UpdatesInstalled) {
            Write-Host "    [OK] $($update.Title)" -ForegroundColor Green
        }
        Write-Host ""
    }
    
    # Show key actions performed
    if ($script:SessionSummary.ActionsPerformed.Count -gt 0) {
        $keyActions = $script:SessionSummary.ActionsPerformed | Where-Object { 
            $_.Category -in @("Configuration", "Service", "Update", "Onboarding", "Remediation") 
        }
        
        if ($keyActions.Count -gt 0) {
            Write-Host "  Key Actions Performed: $($keyActions.Count)" -ForegroundColor Yellow
            foreach ($action in $keyActions | Select-Object -Last 10) {
                Write-Host "    - $($action.Action)" -ForegroundColor White
                if ($action.Details) {
                    Write-Host "      $($action.Details)" -ForegroundColor Gray
                }
            }
            Write-Host ""
        }
    }
    
    # Show next steps or recommendations
    Write-Host "  Recommendations:" -ForegroundColor Yellow
    
    switch ($script:SessionSummary.OnboardingStatus) {
        "Completed" {
            Write-Host "    [OK] MDE onboarding completed successfully" -ForegroundColor Green
            Write-Host "    - Monitor the MDE portal for this server to appear (5-30 minutes)" -ForegroundColor White
            Write-Host "    - Verify endpoint detection and response capabilities" -ForegroundColor White
            Write-Host "    - Review security alerts and configure policies as needed" -ForegroundColor White
        }
        "Failed" {
            Write-Host "    [X] MDE onboarding failed" -ForegroundColor Red
            Write-Host "    - Review the log file for detailed error information" -ForegroundColor White
            Write-Host "    - Check network connectivity to Microsoft endpoints" -ForegroundColor White
            Write-Host "    - Verify the onboarding package is valid and current" -ForegroundColor White
            Write-Host "    - Re-run this script after resolving issues" -ForegroundColor White
        }
        "Cancelled" {
            Write-Host "    - No onboarding was performed (user cancelled)" -ForegroundColor Yellow
            Write-Host "    - Re-run this script when ready to proceed" -ForegroundColor White
            Write-Host "    - All prerequisite checks and changes remain in effect" -ForegroundColor White
        }
        "Prerequisites Failed" {
            Write-Host "    [X] Prerequisites not met for onboarding" -ForegroundColor Red
            Write-Host "    - Review failed checks above and resolve issues" -ForegroundColor White
            Write-Host "    - Use the automatic remediation option if available" -ForegroundColor White
            Write-Host "    - Re-run this script after making necessary changes" -ForegroundColor White
        }
        default {
            Write-Host "    - Onboarding process was interrupted" -ForegroundColor Yellow
            Write-Host "    - Re-run this script to continue from where you left off" -ForegroundColor White
            Write-Host "    - Review any configuration changes that were made" -ForegroundColor White
        }
    }
    
    Write-Host ""
    Write-Host "  Log File Location:" -ForegroundColor Yellow
    Write-Host "    $script:LogFile" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""
}

function Exit-WithSummary {
    <#
    .SYNOPSIS
        Exits the script with a session summary.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$ExitReason = "User Exit",
        
        [Parameter(Mandatory = $false)]
        [int]$ExitCode = 0
    )
    
    Show-SessionSummary -ExitReason $ExitReason
    
    Write-Host "Press any key to exit...`n" -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
    exit $ExitCode
}

#endregion

#region Main Script

function Start-MDEOnboarding {
    Clear-Host
    
    Write-Banner "Microsoft Defender for Endpoint - Server Onboarding"
    
    Write-Host "This script will guide you through the MDE onboarding process for Windows Servers." -ForegroundColor Cyan
    Write-Host "Supported: Windows Server 2019 and above (Desktop Experience and Core installations)`n" -ForegroundColor Cyan
    
    Write-Log "Script started" -Level INFO
    Write-Log "Log file: $script:LogFile" -Level INFO
    
    # Initialize session tracking
    Set-ScriptPhase "Startup"
    Add-SessionAction -Action "Script Started" -Details "MDE Onboarding script initialized" -Category "System"
    
    Write-Host ""
    Write-Host "  This script will:" -ForegroundColor Cyan
    Write-Host "    - Check system prerequisites for MDE onboarding" -ForegroundColor White
    Write-Host "    - Verify Windows Defender services and configuration" -ForegroundColor White
    Write-Host "    - Guide you through the onboarding process" -ForegroundColor White
    Write-Host "    - Provide detailed logging and remediation options" -ForegroundColor White
    Write-Host ""
    
    if (-not (Get-UserConfirmation -Message "Do you want to start the MDE onboarding process?" -DefaultYes $true)) {
        Write-Log "Onboarding cancelled by user" -Level INFO
        $script:SessionSummary.OnboardingStatus = "Cancelled"
        Add-SessionAction -Action "Onboarding Cancelled" -Details "User declined to start the process" -Category "User"
        Exit-WithSummary -ExitReason "User declined to start onboarding process" -ExitCode 0
    }
    
    # Run prerequisite checks
    Write-Banner "Running Prerequisite Checks"
    Set-ScriptPhase "Prerequisite Checks"
    Add-SessionAction -Action "Starting Prerequisites" -Details "Beginning system compatibility checks" -Category "Check"
    
    $checks = @(
        @{Name = "Operating System Version"; Function = { Test-OSVersion }},
        @{Name = "Disk Space"; Function = { Test-DiskSpace }},
        @{Name = "System Resources"; Function = { Test-SystemResources }},
        @{Name = "Internet Connectivity"; Function = { Test-InternetConnectivity }},
        @{Name = "Windows Updates"; Function = { Test-WindowsUpdates }},
        @{Name = "Windows Defender Platform Directory"; Function = { Test-DefenderPlatformDirectory }},
        @{Name = "Windows Defender Services"; Function = { Test-DefenderService }},
        @{Name = "Windows Defender Platform"; Function = { Test-DefenderPlatform }},
        @{Name = "Windows Defender Platform Version"; Function = { Test-DefenderPlatformVersion }},
        @{Name = "Windows Defender Passive Mode"; Function = { Test-DefenderPassiveMode }},
        @{Name = "Group Policy"; Function = { Test-GroupPolicy }},
        @{Name = "Existing Onboarding"; Function = { Test-ExistingOnboarding }},
        @{Name = "Onboarding Script"; Function = { Test-OnboardingScript }}
    )
    
    $checkResults = @()
    
    foreach ($check in $checks) {
        Write-Host ""
        $result = & $check.Function
        $remediation = if (-not $result) { Get-RemediationSteps -CheckName $check.Name } else { $null }
        $checkResults += @{Name = $check.Name; Passed = $result; Remediation = $remediation}
        
        # Record the check result
        Add-CheckResult -CheckName $check.Name -Passed $result -Details $(if (-not $result) { "Check failed - remediation may be available" } else { "Check passed" })
        
        if (-not $result) {
            $script:PrerequisitesPassed = $false
        }
    }
    
    # Display readiness report
    Write-Host ""
    Show-ReadinessReport -CheckResults $checkResults
    
    if (-not $script:PrerequisitesPassed) {
        Write-Log "Prerequisite checks failed. Attempting interactive remediation..." -Level WARNING
        
        $failedChecks = $checkResults | Where-Object { -not $_.Passed }
        
        Write-Host ""
        Write-Host "  [TOOL] AUTOMATIC REMEDIATION AVAILABLE" -ForegroundColor Cyan
        Write-Host "  =====================================" -ForegroundColor Cyan
        Write-Host "    - $($failedChecks.Count) issue(s) detected that may be fixable" -ForegroundColor White
        Write-Host "    - Automatic remediation can resolve common problems" -ForegroundColor White
        Write-Host "    - Service configuration, registry settings, and features" -ForegroundColor White
        Write-Host "    - You will see detailed progress for each fix attempt" -ForegroundColor White
        Write-Host ""
        
        if (Get-UserConfirmation -Message "REMEDIATE: Attempt automatic fixes for detected issues?" -DefaultYes $true) {
            Set-ScriptPhase "Remediation"
            Add-SessionAction -Action "Starting Remediation" -Details "Attempting automatic fixes for $($failedChecks.Count) issues" -Category "Remediation"
            Start-InteractiveRemediation -FailedChecks $failedChecks | Out-Null
            
            Write-Host ""
            Write-Host "  [CHECK] RE-CHECK PREREQUISITES" -ForegroundColor Green
            Write-Host "  =========================" -ForegroundColor Green
            Write-Host "    - Remediation attempts completed" -ForegroundColor White
            Write-Host "    - Running checks again to verify fixes" -ForegroundColor White
            Write-Host "    - This will show if issues were resolved" -ForegroundColor White
            Write-Host ""
            
            if (Get-UserConfirmation -Message "VERIFY: Re-run prerequisite checks to confirm fixes?" -DefaultYes $true) {
                Write-Host ""
                Write-Banner "Re-running Prerequisite Checks"
                Set-ScriptPhase "Re-verification"
                Add-SessionAction -Action "Re-running Checks" -Details "Verifying remediation results" -Category "Check"
                
                # Clear previous state
                $script:PrerequisitesPassed = $true
                $checkResults = @()
                
                foreach ($check in $checks) {
                    Write-Host ""
                    $result = & $check.Function
                    $remediation = if (-not $result) { Get-RemediationSteps -CheckName $check.Name } else { $null }
                    $checkResults += @{Name = $check.Name; Passed = $result; Remediation = $remediation}
                    
                    # Update check results in session tracking
                    Add-CheckResult -CheckName "$($check.Name) (Re-check)" -Passed $result -Details $(if (-not $result) { "Still failing after remediation" } else { "Passed after remediation" })
                    
                    if (-not $result) {
                        $script:PrerequisitesPassed = $false
                    }
                }
                
                Write-Host ""
                Show-ReadinessReport -CheckResults $checkResults
            }
        }
        
        if (-not $script:PrerequisitesPassed) {
            Write-Log "Prerequisites still not met. Please resolve the issues and run the script again." -Level ERROR
            $script:SessionSummary.OnboardingStatus = "Prerequisites Failed"
            Add-SessionAction -Action "Prerequisites Failed" -Details "System requirements not met, onboarding cannot proceed" -Category "Check"
            Exit-WithSummary -ExitReason "Prerequisites not met after remediation attempts" -ExitCode 1
        }
    }
    
    Write-Log "All prerequisite checks passed! Server is ready for onboarding." -Level SUCCESS
    Set-ScriptPhase "Pre-Onboarding"
    Add-SessionAction -Action "Prerequisites Passed" -Details "All system checks completed successfully" -Category "Check"
    Write-Host ""
    
    # Ask if user wants to update signatures
    if (Get-UserConfirmation -Message "Would you like to update Windows Defender signatures before onboarding?" -DefaultYes $true) {
        Write-Host ""
        Add-SessionAction -Action "Updating Signatures" -Details "User requested signature update before onboarding" -Category "Update"
        Update-DefenderSignatures
    }
    
    # Final confirmation
    Write-Host ""
    Write-Host "  [START] FINAL CONFIRMATION - MDE ONBOARDING" -ForegroundColor Green
    Write-Host "  =======================================" -ForegroundColor Green
    Write-Host "    - All prerequisite checks have passed" -ForegroundColor White
    Write-Host "    - System is ready for MDE onboarding" -ForegroundColor White
    Write-Host "    - The onboarding script will be executed" -ForegroundColor White
    Write-Host "    - This will enable MDE protection on this server" -ForegroundColor White
    Write-Host ""
    
    if (-not (Get-UserConfirmation -Message "PROCEED: Execute MDE onboarding on this server?" -DefaultYes $true)) {
        Write-Log "Onboarding cancelled by user at final confirmation" -Level INFO
        $script:SessionSummary.OnboardingStatus = "Cancelled"
        Add-SessionAction -Action "Onboarding Cancelled" -Details "User declined at final confirmation step" -Category "User"
        Exit-WithSummary -ExitReason "User cancelled onboarding at final confirmation" -ExitCode 0
    }
    
    # Start onboarding
    Write-Banner "Onboarding to Microsoft Defender for Endpoint"
    Set-ScriptPhase "Onboarding"
    Add-SessionAction -Action "Starting Onboarding" -Details "Executing MDE onboarding process" -Category "Onboarding"
    
    $onboardingSuccess = Start-OnboardingProcess
    
    if ($onboardingSuccess) {
        Write-Host ""
        Test-OnboardingSuccess
        Write-Host ""
        Show-PostOnboardingInfo
        Write-Log "MDE onboarding process completed" -Level SUCCESS
        $script:SessionSummary.OnboardingStatus = "Completed"
        Add-SessionAction -Action "Onboarding Completed" -Details "MDE onboarding executed successfully" -Category "Onboarding"
        Exit-WithSummary -ExitReason "Onboarding completed successfully" -ExitCode 0
    }
    else {
        Write-Log "MDE onboarding process failed" -Level ERROR
        $script:SessionSummary.OnboardingStatus = "Failed"
        Add-SessionAction -Action "Onboarding Failed" -Details "MDE onboarding script returned failure" -Category "Onboarding"
        Exit-WithSummary -ExitReason "Onboarding process failed" -ExitCode 1
    }
}

# Execute main function
Start-MDEOnboarding

#endregion






