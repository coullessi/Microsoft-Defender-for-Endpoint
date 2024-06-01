#!/bin/bash

curl -o mde_installer.sh https://raw.githubusercontent.com/microsoft/mdatp-xplat/master/linux/installation/mde_installer.sh
sudo unzip GatewayWindowsDefenderATPOnboardingPackage.zip
sudo chmod +x ./mde_installer.sh
sudo ./mde_installer.sh --install --channel prod --onboard MicrosoftDefenderATPOnboardingLinuxServer.py --tag GROUP "RedHat-Linux" --min_req -y