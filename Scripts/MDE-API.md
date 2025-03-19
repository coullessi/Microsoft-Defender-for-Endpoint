# Microsoft Defender for Endpoint API: tag & offboard devices

## Use Case: Organizational Divestiture

### Scenario

An organization is undergoing a divestiture, where a part of the company is being sold off to another entity. As part of this process, it is crucial to ensure that the devices belonging to the divested business unit are properly tagged and offboarded from Microsoft Defender for Endpoint (MDE) to maintain security and compliance.

### Workflow

1. **Identify Devices**: The IT team identifies all devices that belong to the divested business unit. These devices are typically grouped by specific tags or organizational units within MDE.

2. **Tag Devices**: Using the MDE API, the IT team tags all identified devices with a specific tag, such as "Divestiture2025". This helps in easily identifying and managing these devices throughout the divestiture process.

    ```powershell
    $tag = "Divestiture2025"
    $action = "Add"
    Set-DeviceTag -tag $tag -token $token -action $action -tagDeviceList $divestitureDevices
    ```

3. **Review Tagged Devices**: The IT team reviews the list of tagged devices to ensure accuracy. This step involves verifying that all devices that need to be offboarded are correctly tagged.

4. **Offboard Devices**: Once the devices are tagged and verified, the IT team proceeds to offboard these devices from MDE using the API. This ensures that the divested business unit's devices are no longer managed by the organization's MDE instance.

    ```powershell
    Disconnect-Device -offBoardingDeviceList $divestitureDevices -token $token
    ```

5. **Audit and Compliance**: After offboarding, the IT team conducts an audit to ensure that all devices have been successfully offboarded and that there are no remaining devices from the divested business unit in the MDE management console.

### Benefits

- **Security**: Ensures that the divested business unit's devices are no longer under the organization's security management, reducing the risk of unauthorized access.
- **Compliance**: Helps maintain compliance with data protection regulations by ensuring that only authorized devices are managed and monitored.
- **Efficiency**: Automates the process of tagging and offboarding devices, saving time and reducing the potential for human error.

By leveraging the MDE API, the organization can efficiently manage the divestiture process, ensuring a smooth transition and maintaining security and compliance throughout.

## Script Overview

This PowerShell script is designed to interact with Microsoft Defender for Endpoint (MDE) via its API. The script provides functionalities to list, tag, and offboard devices from MDE. It is intended to be executed in a secure and controlled environment, and users are encouraged to customize it as needed for their specific requirements.

## Features

1. **List Devices**: Retrieve and display a list of devices managed by MDE.
2. **Tag Devices**: Add or remove tags from devices.
3. **Offboard Devices**: Remove devices from MDE.

## Requirements

- Necessary permissions to offboard devices from MDE.
- An application registered in Entra with the required permissions.
- A secret stored in Azure Key Vault with the necessary permissions.

## Disclaimer

⚠️ **Important**: The author disclaims any liability for the execution and outcomes of this script. It is provided "as is" without any express or implied warranties. Users are advised to proceed at their own risk.

## Usage

### Initial Setup

1. **Clear Host and Display Script Information**:

    ```powershell
    Clear-Host
    $note = "`n********************************** Microsoft Defender for Endpoint API Script **********************************
    ...
    Write-Host $note -ForegroundColor Green
    Write-Host "`n****************************************************************************************************************`n" -ForegroundColor Green
    ```

2. **Prompt for User Confirmation**:

    ```powershell
    $proceed = Read-Host "Do you want to proceed with the script? ( Yes/No )"
    if ($proceed -notmatch "^(Yes|Y)$") {
        Write-Host -ForegroundColor Yellow "`nExiting the script as per your request."
        Write-Host
        exit
    }
    ```

3. **Prompt for Key Vault and Secret Information**:

    ```powershell
    $vaultName = Read-Host "Key vault name`t"
    $secretName = Read-Host "Secret name`t"
    $clientAppName = Read-Host "Client app name`t"
    ```

### Functions

#### Get-AccessToken

Retrieves an access token from Azure Key Vault.

```powershell
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
```

#### Get-MDEDevice

Retrieves a list of devices from MDE.

```powershell
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
```

#### Select-Device

Prompts the user to select devices based on various criteria.

```powershell
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
            Write-Host -ForegroundColor Green "`nNo device to process."
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
        Write-Host -ForegroundColor Green "`nNo devices selected."
    }
    else {
        Write-Host -ForegroundColor Yellow "`n`nList of selected devices:"
    }
    return $deviceList
}
```

#### Disconnect-Device

Offboards selected devices from MDE.

```powershell
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
```

#### Set-DeviceTag

Adds or removes tags from selected devices.

```powershell
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
            }
            catch {
                Write-Host "Failed to set tag '$tag' for device ID: $id" -ForegroundColor Red
            }
        }
        Write-Host "`nTagging process completed.`n" -ForegroundColor Green
    }
}
```

### Main Menu

Displays the main menu and calls the appropriate functions based on user input.

```powershell
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

        $tag = Read-Host "Tag to add or remove"
        $tag = $tag.Trim('-')
        while ($tag -notmatch "^[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*$") {
            Write-Host -ForegroundColor Yellow "Invalid tag name. Only alphanumeric characters, including hyphen '-' are allowed."
            Write-Host -ForegroundColor Yellow "Hyphens will be removed at the beginning and end of the tag name. Please enter a valid tag."
            $tag = Read-Host "Tag to add or remove"
            $tag = $tag.Trim('-')
        }
        
        $action = Read-Host "Add or remove tag"
        while ($action -cnotmatch "Add" -and $action -cnotmatch "Remove") {
            Write-Host "Invalid action. Please enter 'Add' or 'Remove'." -ForegroundColor Yellow
            $action = Read-Host "Add or Remove tag"
        }
        Set-DeviceTag -tag $tag -token $token -action $action -tagDeviceList $tagDeviceList
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
        }
        Show-Menu
    }
    if ($option -eq "Exit") {
        Write-Host -ForegroundColor Green "`nExiting the script...Goodbye!`n"
        return
    }
}
Show-Menu
```

## Execution Flow

1. **Display Script Information**: The script starts by clearing the host and displaying information about its capabilities and requirements.
2. **User Confirmation**: The user is prompted to confirm whether they want to proceed with the script.
3. **Key Vault and Secret Information**: The user is prompted to enter the key vault name, secret name, and client app name.
4. **Access Token Retrieval**: The script retrieves an access token from Azure Key Vault.
5. **Main Menu**: The script displays a menu with options to list devices, tag devices, offboard devices, or exit.
6. **Function Execution**: Based on the user's choice, the script calls the appropriate function to perform the desired action.

## References

- [Microsoft Defender for Endpoint API Documentation](https://learn.microsoft.com/en-us/defender-endpoint/api/offboard-machine-api)
- [Microsoft Defender for Endpoint Management APIs](https://learn.microsoft.com/en-us/defender-endpoint/api/management-apis#microsoft-defender-for-endpoint-apis)

This documentation provides a comprehensive overview of the script's functionality, requirements, and usage. Users are encouraged to refer to the official Microsoft documentation for more detailed information on MDE and its APIs.

⚠️ **Disclaimer**: The author disclaims any liability for the execution and outcomes of this script. It is provided "as is" without any express or implied warranties. Users are advised to proceed at their own risk.
