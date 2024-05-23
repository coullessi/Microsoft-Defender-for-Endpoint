# Deploy MDE on Linux Manually


## 1. Connect to the server: example of Red Hat Enterprise
From a terminal session, connect to a Linux VM using the command: ```ssh user@ip_address``` or ```ssh user@ip_address -p port_number``` if you are connecting to a port other then TCP port 22.<br>

:bulb: **Tip:** The ```IP address``` can also be the ```FQDN``` of the server you are connecting to.
```bash
# Connect using an IP address
ssh user@ip_address
# If you need to specify a port number
ssh user@ip_address -p port_number
```
<br>

:information_source: **Note:** This is not needed, but [certificate-based authentication](YouTube) is also an option.<br><br>
  
## 2. Update the server
```bash
sudo yum update && sudo yum upgrade
```
## 3. Create a user 
The user will be added the user to the 'wheel' group, so the user can manage the server. This step is not really needed. But this is to avoid login onto the server as root. You can create a user with multiple lines of commands or a single line of command.

```bash
# Switch to the root user
sudo -i

# Create the user and set the user's home directory with '-m'
adduser -m bob

# Configure the user's password
passwd bob

# Add the user to the 'wheel' (sudo) group
usermod -aG wheel bob

# Verify the user belongs to the 'wheel' group
id bob

# Login as the new user
su - bob
```
or

 ```bash
 # Single line to create a user
 sudo useradd -m bob && sudo passwd bob && usermod -aG wheel bob
 ```
Now, you can connect to your Linux device using the new user's (bob) credentials:
```bash
ssh bob@ip_address
```

## 4. Install MDE
[RHEL and variants (CentOS, Fedora, Oracle Linux, Amazon Linux 2, Rocky and Alma)](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/linux-install-manually?view=o365-worldwide#rhel-and-variants-centos-fedora-oracle-linux-amazon-linux-2-rocky-and-alma)

Use ```hostnamectl``` command to identify system related information including distribution and release version.

![Distro detail](/assets/pictures/rhel_hostnamectl.png)<br>

| Distro & Version  | Package Location |
|----------|----------|
| RHEL/Centos/Oracle 9.0-9.8   | [RHEL/Centos/Oracle 9.0-9.8](https://packages.microsoft.com/config/rhel/9/prod.repo)   |
| RHEL/Centos/Oracle 8.0-8.8    | [RHEL/Centos/Oracle 8.0-8.8](https://packages.microsoft.com/config/rhel/8/prod.repo)  |
| RHEL/Centos/Oracle 7.2-7.9 & Amazon    | [RHEL/Centos/Oracle 7.2-7.9 & Amazon](https://packages.microsoft.com/config/rhel/7.2/prod.repo)   |

Install yum-utils if it isn't already installed: 
```bash
sudo yum install yum-utils
```
Add the repository to your list of packages (Rhel 9.3 from the prod and insiders-fast channels)
```bash
sudo yum-config-manager --add-repo=https://packages.microsoft.com/config/rhel/9.0/prod.repo
sudo yum-config-manager --add-repo=https://packages.microsoft.com/config/rhel/9.0/insiders-fast.repo
```
Install the Microsoft GPG public key
```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
```
Application installation
```bash
# List all repositories
yum repolist 
```
 If you have multiple Microsoft repositories, for example, use the following command to install the package from the production channel.
 ```bash 
 # to install the package from the production repository.
 sudo yum --enablerepo=packages-microsoft-com-prod install mdatp
 ```
 Set the device tag
 ```bash
 sudo mdatp edr tag set --name GROUP --value 'MDE-Management'
 ```        
Download the onboarding package from Microsoft Defender XDR portal<br>
![Linux Server Onboarding Package](/assets/pictures/download_onboarding_package.png)<br>

**Transfer the onboarding package to your Linux machine** 
In Linux, we can share files between computers using scp. scp utilizes ssh to securely transfer files. We use the following syntax to copy files from the source machine to the destination machine: ```scp <path_to_local_file> username@ip_address:<path_to_destination>```, for example the below command will copy the onboarding package from your local computer into the MDE directory of the Linux device.
```bash
 scp "E:\MDE\Linux\WindowsDefenderATPOnboardingPackage.zip" lessi@10.0.0.97:~/MDE
```  

On the Linux machine:
Unzip the onboarding package. You'll get the MicrosoftDefenderATPOnboardingLinuxServer.py file
```bash
unzip WindowsDefenderATPOnboardingPackage.zip
```
This will give you the _**MicrosoftDefenderATPOnboardingLinuxServer**.py_ file.
Client configuration
Initially the client device is not associated with an organization and the orgId attribute is blank.
```bash
mdatp health --field org_id
``` 

:exclamation: Verify python3 is installed
```bash
# Install python3 if it's not installed
python3 --version
```
Run MicrosoftDefenderATPOnboardingLinuxServer.py to onboard the Linux Server.
```bash
sudo python3 MicrosoftDefenderATPOnboardingLinuxServer.py
```
 Verify that the device is now associated with your organization and reports a valid organization identifier.
```bash
mdatp health --field org_id
```
Check the health status of the product. A return value of 'true' denotes that the product is functioning as expected.
```bash
mdatp health --field healthy
```    
Check the status of the definition update, return value should be up_to_date.
```bash
mdatp health --field definitions_status
```
Ensure real-time protection is enabled, the return value should be true.
```bash
mdatp health --field real_time_protection_enabled
```
If not, run the following: 
```bash
sudo mdatp config real-time-protection --value enabled
```
Test MDE on Linux by simulating the download of a "malicious" eicar file. The file should be quarantined.
```bash
curl -o ~/eicar.com.txt https://secure.eicar.org/eicar.com.txt
```
List the detected threats
```bash
mdatp threat list
```