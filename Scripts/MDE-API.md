# Microsoft Defender for Endpoint API Script

## Overview

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
    ...
    return $response.access_token
}

#### Get-MDEDevice

Retrieves a list of devices from MDE.

```powershell
function Get-MDEDevice {
    param (
        [Parameter(Mandatory = $true)]
        [array]$devices
    )
    ...
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
    ...
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
    ...
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
    ...
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
    ...
    Show-Menu
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
