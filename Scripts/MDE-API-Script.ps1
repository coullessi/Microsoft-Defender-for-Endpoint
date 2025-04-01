Clear-Host
$note = "`n********************************** Microsoft Defender for Endpoint API Script **********************************

DESCRIPTION:
    This script is designed to tag or offboard a device from Microsoft Defender for Endpoint (MDE) using an API.  
    No support from the author will be provided for the script. Execute the script in a secure and controlled 
    manner. Customize it as needed for your environment.

REQUIREMENTS:
    - Ensure you have the necessary permissions to offboard devices from MDE.
    - Create an application in Entra and assign the required permissions to it.
    - Create a secret in the key vault and assign the required permissions to it.

DISCLAIMER:
    The author disclaims any liability for the execution and outcomes of this script. 
    This script is provided 'as is', without any express or implied warranties. 
    The author assumes no responsibility for any damages or losses that may result from the use of this script. 
    Users are advised to proceed at their own risk.

    Please, refer to the official Microsoft documentation for more information on MDE and its APIs:
    https://learn.microsoft.com/en-us/defender-endpoint/api/offboard-machine-api
    https://learn.microsoft.com/en-us/defender-endpoint/api/management-apis#microsoft-defender-for-endpoint-apis"
Write-Host $note -ForegroundColor Green
Write-Host "`n****************************************************************************************************************`n" -ForegroundColor Green

$proceed = Read-Host "Do you want to proceed with the script? ( Yes/No )"
if ($proceed -notmatch "^(Yes|Y)$") {
    Write-Host -ForegroundColor Yellow "`nExiting the script as per your request."
    Write-Host
    exit
}

Write-Host
Write-Host "`t`t        *****************************************************" -ForegroundColor Green
Write-Host "`t`t         *************** SCRIPT CAPABILITIES ***************" -ForegroundColor Cyan
Write-Host "`t`t          *************************************************" -ForegroundColor Yellow
Write-Host "`t`t               ******    1. List devices        ******" -ForegroundColor Cyan
Write-Host "`t`t                ******   2. Tag devices        ******" -ForegroundColor Cyan
Write-Host "`t`t               ******    3. Offboard devices    ******" -ForegroundColor Cyan
Write-Host "`t`t          *************************************************" -ForegroundColor Yellow
Write-Host "`t`t        *****************************************************" -ForegroundColor Green
Write-Host

Write-Host -ForegroundColor Green "A key vault and a secret are required to get the access token."
$vaultName = Read-Host "Key vault name`t"
$secretName = Read-Host "Secret name`t"
$clientAppName = Read-Host "Client app name`t"
$vaultName = $vaultName.Trim()
$secretName = $secretName.Trim()
$clientAppName = $clientAppName.Trim()

#region Function: Get access token

function Get-AccessToken {
    param (
        [Parameter(Mandatory = $true)]
        [string]$vaultName,
        [Parameter(Mandatory = $true)]
        [string]$secretName
    )

    try {
        Clear-Host
        Disconnect-AzAccount -WarningAction SilentlyContinue | Out-Null
        Connect-AzAccount -WarningAction SilentlyContinue | Out-Null
        $id = (Get-AzTenant).Id
        $clientAppId = (Get-AzADServicePrincipal -SearchString $clientAppName).AppId

        $tenantId = $id
        $clientSecret = Get-AzKeyVaultSecret -VaultName $vaultName -Name $secretName -AsPlainText
        $resource = "https://api.securitycenter.microsoft.com"

        $body = @{
            grant_type    = "client_credentials"
            client_id     = $clientAppId
            client_secret = $clientSecret
            resource      = $resource
        }
        $response = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/token" -Body $body -ErrorAction Stop
        return $response.access_token
    }
    catch {
        Write-Host -ForegroundColor Red "Failed to get access token: $_"
        exit
    }
}
$token = Get-AccessToken -vaultName $vaultName -secretName $secretName

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}
$uri = "https://api.securitycenter.microsoft.com/api/machines"
try {
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
    $allDevices = $response.value
}
catch {
    Write-Host -ForegroundColor Red "Failed to retrieve devices: $_"
    exit
}
#endregion

#region Function: Get onboarded devices
function Get-MDEDevice {
    param (
        [Parameter(Mandatory = $true)]
        [array]$devices
    )

    $deviceList = @()
    $mdeDevices = $devices
    $mdeDevices | ForEach-Object {
        $machine = New-Object PSObject -Property @{
            "DeviceId"         = $_.id
            "DeviceName"       = if ($_.computerDnsName.Length -gt 40) { $_.computerDnsName.Substring(0, 20) + "..." } else { $_.computerDnsName }
            "OsPlatform"       = $_.osPlatform
            "OnboardingStatus" = $_.onboardingStatus
            "HealthStatus"     = $_.healthStatus
            "GroupName"        = $_.rbacGroupName
            "DeviceTag"        = $_.machineTags
        }
        $deviceList += $machine | Select-Object "DeviceId", "DeviceName", "OsPlatform", "OnboardingStatus", "HealthStatus", "GroupName", "DeviceTag"
    }
    return $deviceList
}
Write-Host -ForegroundColor Yellow "`n`nList of MDE devices:"
$mdeDevices = Get-MDEDevice -devices $allDevices
$mdeDevices | Sort-Object DeviceName | Format-Table -AutoSize
#endregion

#region Function: Get devices to offboard
function Select-Device {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Devices
    )

    $deviceList = @()
    $continue = $true

    while ($continue) {
        $selection = $null
        $id = $null
        $machineTags = $null
        $rbacGroupName = $null

        Write-Host -ForegroundColor Yellow "`nSelect devices:"
        Write-Host "1. Device ID"
        Write-Host "2. Device tag"
        Write-Host "3. Device group"
        Write-Host "4. Onboading status"
        Write-Host "5. Health status"
        Write-Host "6. Exit"
        
        while ($selection -notin 1..6) {
            $selection = Read-Host "`nEnter your choice (1-6)"
            if ($selection -eq 6) {
                Write-Host -ForegroundColor Yellow "`nExiting the script as per your request."
                Write-Host
                exit
            }
        }

        switch ($selection) {
            1 {
                $id = Read-Host "Enter Device ID"
            }
            2 {
                do {
                    $machineTags = Read-Host "Enter Device tag (enter 'notag' for untagged devices)"
                    if ($machineTags -ieq "notag") {
                        $machineTags = "notag"
                    }
                } while ($machineTags -ne "notag" -and $machineTags -match "^\s*$")
            }
            3 {
                $rbacGroupName = Read-Host "Enter Device group name"
            }
            4 {
                $onboardingStatus = Read-Host "Enter Onboarding status [Onboarded | CanBeOnboarded | InsufficientInfo]"
                if ($onboardingStatus -notmatch "^(Onboarded|Offboarded|CanBeOnboarded|InsufficientInfo)$") {
                    Write-Host -ForegroundColor Yellow "`nInvalid Onboarding status. Please enter a valid status."
                    $onboardingStatus = $null
                }
            }
            5 {
                $healthStatus = Read-Host "Enter Health status [Active | Inactive]"
                if ($healthStatus -notmatch "^(Active|Inactive)$") {
                    Write-Host -ForegroundColor Yellow "`nInvalid Health status. Please enter a valid status."
                    $healthStatus = $null
                }
            }
        }

        if ($machineTags -eq "notag") {
            $untaggedDevices = $allDevices | Where-Object { $_.machineTags.Count -eq 0 }
            $selectedDevices = $untaggedDevices
        }
        else {
            $selectedDevices = $Devices | Where-Object {
                ($id -and $_.id -ieq $id) -or
                ($machineTags -and $_.machineTags -ieq $machineTags) -or
                ($rbacGroupName -and $_.rbacGroupName -ieq $rbacGroupName) -or
                ($onboardingStatus -and $_.onboardingStatus -ieq $onboardingStatus) -or
                ($healthStatus -and $_.healthStatus -ieq $healthStatus)
            }
        }

        if ($null -eq $selectedDevices -or $selectedDevices.Count -eq 0) {
            Write-Host -ForegroundColor Green "`nNo device found with the specified criteria."
        }
        else {
            $selectedDevices | ForEach-Object {
                $machine = New-Object PSObject -Property @{
                    "DeviceId"          = $_.id
                    "DeviceTag"         = $_.machineTags
                    "DeviceName"        = if ($_.computerDnsName.Length -gt 40) { $_.computerDnsName.Substring(0, 20) + "..." } else { $_.computerDnsName }
                    "OsPlatform"        = $_.osPlatform
                    "OnboardingStatus"  = $_.onboardingStatus
                    "HealthStatus"      = $_.healthStatus
                    "GroupName"         = $_.rbacGroupName
                }
                if (-not ($deviceList.DeviceId -contains $machine.DeviceId)) {
                    $deviceList += $machine | Select-Object "DeviceId", "DeviceName", "OsPlatform", "OnboardingStatus", "HealthStatus", "GroupName", "DeviceTag"
                }
            }
        }

        $continueResponse = Read-Host "Do you want to select more devices? (Yes/No)"
        if ($continueResponse -match "^(No|N|no|n)$") {
            $continue = $false
        }
    }

    if ($deviceList.Count -eq 0) {
        Write-Host
    }
    else {
        Write-Host -ForegroundColor Yellow "`n`nList of selected devices:"
    }
    return $deviceList
}
#endregion

#region Function: Set device tags
function Set-DeviceTag {
    param (
        [Parameter(Mandatory = $true)]
        [string]$tag,
        [Parameter(Mandatory = $true)]
        [string]$token,
        [Parameter(Mandatory = $true)]
        [string]$action,
        [Parameter(Mandatory = $true)]
        [array]$tagDeviceList
    )

    if ($tagDeviceList.Count -eq 0) {
        Write-Host "No tag will be set." -ForegroundColor Green
        return
    }
    else {
        foreach ($device in $tagDeviceList) {
            $id = $device.DeviceId
            $uri = "https://api.securitycenter.microsoft.com/api/machines/$id/tags"
            $headers = @{
                "Authorization" = "Bearer $token"
                "Content-Type"  = "application/json"
            }
            $body = @{
                "Value"  = $tag
                "Action" = $action
            }

            try {
                Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body ($body | ConvertTo-Json) -ErrorAction Stop | Out-Null
                Write-Host "Setting tag '$tag' for device ID: $id" -ForegroundColor Cyan

                # Update the $allDevices array
                $deviceToUpdate = $allDevices | Where-Object { $_.id -eq $id }
                if ($deviceToUpdate) {
                    if ($action -eq "Add") {
                        $deviceToUpdate.machineTags += $tag
                    } elseif ($action -eq "Remove") {
                        $deviceToUpdate.machineTags = $deviceToUpdate.machineTags -replace $tag, ""
                    }
                }
            }
            catch {
                Write-Host "Failed to set tag '$tag' for device ID: $id" -ForegroundColor Red
            }
        }
        Write-Host "`nTagging process completed.`n" -ForegroundColor Green
    }
}
#endregion

#region Function: Offboard MDE devices
function Disconnect-Device {
    param (
        [Parameter(Mandatory = $true)]
        [array]$offBoardingDeviceList,
        [Parameter(Mandatory = $true)]
        [string]$token
    )

    $OffboardedDevices = @()

    $offboardBody = @{
        "Comment" = "Offboard device from MDE using the API."
    }

    do {
        $confirmation = Read-Host "Are you sure you want to offboard these device(s)? (Yes/No)"
    } while ($confirmation -notmatch "^(Yes|No|Y|N)$")
    if ($confirmation -match "^(Yes|Y)$") {
        foreach ($device in $offBoardingDeviceList) {
            $id = $device.DeviceId
            Write-Host "Offboarding Device ID: $($device.DeviceId)" -ForegroundColor Cyan
            $uri = "https://api.securitycenter.microsoft.com/api/machines/$id/offboard"
            $headers = @{
                "Authorization" = "Bearer $token"
                "Content-Type"  = "application/json"
            }
            try {
                $offboardedDevice = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body ($offboardBody | ConvertTo-Json) -ErrorAction Stop
                if ($null -eq $offboardedDevice) {
                    Write-Host "Offboarding failed for Device ID: $($device.DeviceId)" -ForegroundColor Red
                }
                else {
                    Write-Host "Offboarding completed for Device ID: $($device.DeviceId)" -ForegroundColor Green
                    $offboardedDevices += $offboardedDevice

                    # Remove the offboarded device from $allDevices
                    $allDevices = $allDevices | Where-Object { $_.id -ne $id }
                }
            }
            catch {
                Write-Host -ForegroundColor Red "Failed to offboard device ID: $($device.DeviceId): $_"
            }
        }
        Write-Host "`nOffboarding completed for all devices." -ForegroundColor Red
        $OffboardedDevices | ForEach-Object {
            New-Object PSObject -Property @{
                "DeviceId"         = $_.machineId
                "DeviceName"       = $_.computerDnsName
                "Type"             = $_.type
                "Status"           = $_.status
                "Requestor"        = $_.Requestor
                "RequestorComment" = $_.requestorComment
            }
        } | Format-Table DeviceId, DeviceName, Type, Status, Requestor, RequestorComment  -AutoSize
    }
    else {
        Write-Host "Offboarding skipped." -ForegroundColor Green
    }
}
#endregion

#region Menu: call functions
function Show-Menu {
    $choices = @("List Devices", "Tag Devices", "Offboard Devices", "Exit")
    Write-Host -ForegroundColor Green "`nYour choice of action:"
    Write-Host "1. List Devices`n2. Tag Devices`n3. Offboard Devices`n4. Exit"
    $choice = Read-Host "`nEnter your choice (1-4)"
    while ($choice -notin 1..4) {
        Write-Host -ForegroundColor Yellow "Invalid choice. Please enter a number between 1 and 4"
        $choice = Read-Host "`nEnter your choice (1-4)"
    }
    $option = $choices[$choice - 1]
    if ($option -eq "List Devices") {
        Select-Device -Devices $allDevices | Sort-Object DeviceName | Format-Table
        Show-Menu
    }
    if ($option -eq "Tag Devices") {
        $tagDeviceList = Select-Device -Devices $allDevices
        $tagDeviceList | Sort-Object DeviceName | Format-Table

        $tag = Read-Host "Tag name"
        $tag = $tag.Trim('-')
        while ($tag -notmatch "^[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*$") {
            Write-Host -ForegroundColor Yellow "Invalid tag name. Only alphanumeric characters, including hyphen '-' are allowed."
            Write-Host -ForegroundColor Yellow "Hyphens will be removed at the beginning and end of the tag name. Please enter a valid tag."
            $tag = Read-Host "Tag name to add or remove"
            $tag = $tag.Trim('-')
        }
        
        $action = Read-Host "Add | Remove"
        while ($action -cnotmatch "Add" -and $action -cnotmatch "Remove") {
            Write-Host "Invalid action. Please enter 'Add' or 'Remove'." -ForegroundColor Yellow
            $action = Read-Host "Add or Remove tag"
        }
        Set-DeviceTag -tag $tag -token $token -action $action -tagDeviceList $tagDeviceList
        # $mdeDevices = Get-MDEDevice -devices $allDevices
        Show-Menu
    }
    if ($option -eq "Offboard Devices") {
        $offBoardingDeviceList = Select-Device -Devices $allDevices
        $offBoardingDeviceList | Sort-Object DeviceName | Format-Table
        if ($null -eq $offboardingDeviceList -or $offboardingDeviceList.Count -eq 0) {
            return
        }
        else {
            Disconnect-Device -offBoardingDeviceList $offboardingDeviceList -token $token
            Set-DeviceTag -tag "Offboarded" -token $token -action "Add" -tagDeviceList $offBoardingDeviceList
        }
        # $mdeDevices = Get-MDEDevice -devices $allDevices
        Show-Menu
    }
    if ($option -eq "Exit") {
        Write-Host -ForegroundColor Green "`nExiting the script...Goodbye!`n"
        return
    }
}
Show-Menu
#endregion
