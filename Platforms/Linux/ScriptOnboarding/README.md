# Deploy MDE on Linux with a Script

## Introduction
Make sure ```unzip``` is installed on the Linux you are going to onboard From the Defender portal, download the onboarding package. Then, copy the ```onboarding package``` and the ```installer script``` to the Linux server you want to onboard

## Table of Contents
- [Download the onboarding package]()
- [Copy onboarding files to server to onboard]()

## Install MDE
Before you run the bash script below, replace ```onboarding_package``` with the package you download from your Defender portal.
```bash
#!/bin/bash

mkdir MDE
cd MDE
curl -o mde_installer.sh https://raw.githubusercontent.com/microsoft/mdatp-xplat/master/linux/installation/mde_installer.sh
sudo unzip GatewayWindowsDefenderATPOnboardingPackage.zip
sudo ./mde_installer.sh --install --channel prod --onboard [onboarding_package] --tag GROUP "MDE-Management" --min_req -y
```

## Uninstall MDE
Before you run the bash script below, replace ```onboarding_package``` with the package you download from your Defender portal.
```bash
#!/bin/bash

sudo unzip WindowsDefenderATPOffboardingPackage_valid_until_2024-04-30.zip
sudo ./mde_installer.sh --remove --onboard [offboarding_package]
```

## Reference Documents
[Deploy MDE on Linux with a Script](https://learn.microsoft.com/en-us/defender-endpoint/linux-install-manually#installer-script)<br>


<hr>

[![LinkeIn](../../Assets/Pictures/LinkeIn.png)](https://www.linkedin.com/in/c-lessi/)
[![YouTube](../../Assets/Pictures/YouTube.png)](https://www.youtube.com/channel/UCk8wUhDaJ6pnP_1G5ugrQ1A)