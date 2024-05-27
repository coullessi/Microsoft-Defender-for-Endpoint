# Deploy MDE on Linux with a Script

## What is the lab exercise about?
In this exercise, you'll use an [automated script](https://learn.microsoft.com/en-us/defender-endpoint/linux-install-manually#installer-script) to onboard a device to Microsoft Defender for Endpoint. The script identifies the distribution and version, simplifies the selection of the right repository, sets up the device to pull the latest package, and combines the product installation and onboarding steps.The following steps will be covered:<br>
- [Step 1: Download the onboarding package](https://github.com/coullessi/Microsoft-Defender-for-Endpoint/blob/main/Platforms/Linux/ScriptOnboarding/README.md#step-1-download-the-onboarding-package)
- [Step 2: Copy files to the server to onboard](https://github.com/coullessi/Microsoft-Defender-for-Endpoint/blob/main/Platforms/Linux/ScriptOnboarding/README.md#step-2-copy-files-to-the-server-to-onboard)
- [Step 3: Install MDE](https://github.com/coullessi/Microsoft-Defender-for-Endpoint/blob/main/Platforms/Linux/ScriptOnboarding/README.md#step-3-install-mde)
- [Step 4: Uninstall MDE](https://github.com/coullessi/Microsoft-Defender-for-Endpoint/blob/main/Platforms/Linux/ScriptOnboarding/README.md#step-4-uninstall-mde)

## Step 1: Download the onboarding package
Go to ```security.microsoft.com > Settings > Endpoints > Onboarding``` and select the following:
- Operation system: ```Linux Server```
- Connectivity type: ```Streamlined```
- Deployment method: ```Local Script (Python)```
- Click: ```Download onboarding package```.<br>
![download_package](./Assets/Pictures//download_package.png)

## Step 2: Copy files to the server to onboard
In the example below, the ```scp``` command copies all files from the source folder to the destination directory on the ```control node``` (the destination directory will be created if it doesn't exist):
- ```scp```: the command for a secure copy over SSH.
- ```port_number```: the port where the remote server is listening for incoming SSH requests.
- ```ssh_private_key```: location of the ssh private key; if you do not have a key configure, you can provide a password when prompted. 
- ```source_folder```: folder containing files to be transferred. 
- ```destination_directory```: Remote server directory where files will be transferred, in the form of ```user@domain.com:~/directory``` or ```user@ip_address:~/directory```

**Example of command**: ```scp -P [port_number] -i [ssh_private_key] -r [source_folder] [destination_directory]```. Replace all items in square brackets ```[]``` with their corresponding values.<br>
On the Linux Server, run the ```ls [destination_directory]``` to verify that all files are copied from your local system to the Ansible control node.

## Step 3: Install MDE
Run the following commands to onboard the server to MDE. Make sure ```unzip``` is installed on the Linux you are going to onboard.
```bash
mkdir MDE
cd MDE
curl -o mde_installer.sh https://raw.githubusercontent.com/microsoft/mdatp-xplat/master/linux/installation/mde_installer.sh
sudo unzip GatewayWindowsDefenderATPOnboardingPackage.zip
sudo ./mde_installer.sh --install --channel prod --onboard MicrosoftDefenderATPOnboardingLinuxServer.py --tag GROUP "MDE-Management" --min_req -y
```
Intead of running the above commands individually, you may also run the [bash script](install_mde.sh) to onboard the server.

## Step 4: Uninstall MDE
Download the ```offboarding package``` from the Defender portal.<br>
:exclamation: Before you run the command below, replace ```offboarding_package``` with the package you downloaded from your Defender portal.
```bash
sudo ./mde_installer.sh --remove --onboard [offboarding_package]
```
<br>
<hr>

[![LinkeIn](../../Assets/Pictures/LinkeIn.png)](https://www.linkedin.com/in/c-lessi/)
[![YouTube](../../Assets/Pictures/YouTube.png)](https://www.youtube.com/channel/UCk8wUhDaJ6pnP_1G5ugrQ1A)