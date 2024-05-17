<details>
<summary><b>Deploy MDE on Linux Manually</b></summary><br>

**Example of Red Hat Enterprise Linux 9.3**

### 1. Connect to the server - example Redhat Server
From a Terminal session, connect to a Linux VM using the command: **_ssh <user>@<ip_address>_** or **_ssh <user>@<ip_address> -p <port_number>_** if you are connecting to a port other then TCP port 22. The 'IP address' can also be the FQDN of the server you are connecting to.
>```bash
>ssh <user>@<ip_address>
>```
or
>```bash
>ssh <user>@<ip_address> -p <port_number>
>```
Press enter. Then answer "yes" and provide your password when prompted.
  
### 2. Update the server
sudo yum update && sudo yum upgrade
### 3. Create a user 
The user will be added the user to the 'wheel' group, so the user can manage the server.<br>
This step is not really needed. But this is to avoid login onto the server as root. You can do this will multiple lines of commands or a single line of command.
#### Create a user with a series of commands
>Switch to the root user.
>```bash
>sudo -i
>```
>Create the user and set the user's home directory with '-m'
>```bash
>adduser -m bob
>```
>Configure the user's password
>```bash
>passwd bob
>```
> Add the user to the 'wheel' (sudo) group
> ```bash
> usermod -aG wheel bob
> ```
> Verify the user belongs to the 'wheel' group
> ```bash
> id bob
> ```
> Login as the new user
> ```bash
> su - bob
> ```
> View the user's working directory
> ```bash
> pwd
> ```
>```
or

#### Create a user with a single line 
> ```bash
> sudo useradd -m bob && sudo passwd bob && usermod -aG wheel bob
> ```
Now, you can connect to your Linux device using the new user's (bob) credentials:
```bash
ssh bob@<ip_address>
```
> :information_source: **Note**<br>
**This is not needed**, but certificate-based authentication is also an option.<br>Example of a Windows device with PowerShell<br>
On your local device (Windows), do the following from a PowerShell session:
Generate a private/public key pair and provide the name LocalHostKey for example when prompted and do not provide any password (two files will be created, one for the private key 'LocalHostKey' and one for the public key 'LocalHostKey.pub').
```PowerShell
ssh-keygen -t rsa -C "LocalHost" -f LocalHostKey
```
Create a variable to hold the location of the private key, for example:
```PowerShell
$keyFile = "E:\Repo\MDE\LocalHostKey"
```
Run the following command and note FullControl access for System and Administrators, and Modify and Synchronize for the current user, which are overly permissive, and a Linux system will not allow authentication with such permissions.
```PowerShell
Get-Acl $keyFile | Format-List
```    
Get the permissions that users and user groups have to access the file
```PowerShell
$acl = Get-Acl $keyFile 
```      
Get the current username on the device
```PowerShell
$username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
```
        
Create a new access rule object with the permissions for the ACL and apply the ACL to the file
```PowerShell
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($username,"Read","Allow")
$acl.SetAccessRule($accessRule)
$acl | Set-Acl $keyFile
```  
Disable the inheritance and remove the existing access rules
```PowerShell
$acl.SetAccessRuleProtection($true,$false)
$acl | Set-Acl $keyFile
```  
After applying the ACL and disabling the inheritance, make sure FullControl is no longer granted to the current user
```PowerShell
Get-Acl $keyFile | Format-List
```     
Finally copy the public key, you'll upload that to your Linux device
```PowerShell
Get-Content .\LocalHostKey.pub
```
        
On your Linux machine
```bash
mkdir ~/.ssh
sudo vim ~/.ssh/authorized_keys
```
Type 'i' and paste the public key<br>
Type 'ESC' then ':wq' to exit

Verify the presence of the public key on the Linux machine with the following command:
```bash
cat ~/.ssh/authorized_keys
``` 
Now you can connect to your Linux device without a password:
```PowerShell
ssh -i "LocalHostKey" bob@<ip_address>
```

    From the current system, you can also copy the public key to other systems with the following command for example:
    sudo scp ~/.ssh/authorized_keys lessi@10.0.0.78:~/.ssh
    
### 4. Install MDE
[RHEL and variants (CentOS, Fedora, Oracle Linux, Amazon Linux 2, Rocky and Alma)](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/linux-install-manually?view=o365-worldwide#rhel-and-variants-centos-fedora-oracle-linux-amazon-linux-2-rocky-and-alma)
##### Locate the installer script
- Use hostnamectl command to identify system related information including distribution and release version.<br>

![Uninstall Ansible](/assets/pictures/rhel_hostnamectl.png)<br>

| Distro & Version  | Package Location |
|----------|----------|
| RHEL/Centos/Oracle 9.0-9.8   | [RHEL/Centos/Oracle 9.0-9.8](https://packages.microsoft.com/config/rhel/9/prod.repo)   |
| RHEL/Centos/Oracle 8.0-8.8    | [RHEL/Centos/Oracle 8.0-8.8](https://packages.microsoft.com/config/rhel/8/prod.repo)  |
| RHEL/Centos/Oracle 7.2-7.9 & Amazon    | [RHEL/Centos/Oracle 7.2-7.9 & Amazon](https://packages.microsoft.com/config/rhel/7.2/prod.repo)   |

- Install yum-utils if it isn't already installed: 
```bash
sudo yum install yum-utils
```
- Add the repository to your list of packages (Rhel 9.3 from the prod and insiders-fast channels)
```bash
sudo yum-config-manager --add-repo=https://packages.microsoft.com/config/rhel/9.0/prod.repo
sudo yum-config-manager --add-repo=https://packages.microsoft.com/config/rhel/9.0/insiders-fast.repo
```
- Install the Microsoft GPG public key
```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
```
- Application installation
> ```bash
> yum repolist # to list all repositories
> ```
> If you have multiple Microsoft repositories, for example, use the following command to install the package from the production channel.
> ```bash 
> # to install the package from the production repository.
> sudo yum --enablerepo=packages-microsoft-com-prod install mdatp
> ```
> - Set the device tag
> ```bash
> sudo mdatp edr tag set --name GROUP --value 'MDE-Management' # to set the device tag.
> ```        
- Download the onboarding package from Microsoft Defender XDR portal
Create a folder to store MDE onboarding files: 
> ```bash
> mkdir MDE
> cd MDE # to navigate in that directory
> ```
- Transfer the onboarding package to your Linux machine: 
In Linux, we can share files between computers using scp. scp utilizes ssh to securely transfer files. We use the following syntax to copy files from the source machine to the destination machine: scp /path/to/local/file username@destination:/path/to/destination, for example the below command will copy the onboarding package from your local computer into the MDE directory of the Linux device.
```bash
 scp "E:\MDE\Linux\WindowsDefenderATPOnboardingPackage.zip" lessi@10.0.0.97:~/MDE
```  
![Linux Server Onboarding Package](/assets/pictures/download_onboarding_package.png)  
On the Linux machine:
```bash 
ls -l MDE # to verify the presence of the onboarded ZIP file
```
- Unzip the onboarding package. You'll get the MicrosoftDefenderATPOnboardingLinuxServer.py file
```bash
unzip WindowsDefenderATPOnboardingPackage.zip
```
This will give you the _**MicrosoftDefenderATPOnboardingLinuxServer**.py_ file.
- Client configuration
>Initially the client device is not associated with an organization and the orgId attribute is blank.
>```bash
>mdatp health --field org_id
>``` 
> :information_source: **Note**<br>To onboard a device that was previously offboarded you must remove the _**mdatp_offboard.json**_ file located at /etc/opt/microsoft/mdatp.
>>View the presence of the mdatp_offboard.json file
>>```bash
>>ls /etc/opt/microsoft/mdatp/ 
>>```
>>Remove mdatp from the device
>>```bash
>>sudo yum remove mdatp
>>```
>>Remove the mdatp_onboard.json file
>>```bash
>>sudo rm -f /etc/opt/microsoft/mdatp/mdatp_onboard.json
>>```

>:exclamation: Verify python3 is installed
>```bash
>python3 --version # install python3 if it's not installed
>```
>Run MicrosoftDefenderATPOnboardingLinuxServer.py to onboard the Linux Server.
>```bash
>sudo python3 MicrosoftDefenderATPOnboardingLinuxServer.py
>```
> Verify that the device is now associated with your organization and reports a valid organization identifier.
>```bash
>mdatp health --field org_id
>```
>>Check the health status of the product. A return value of 'true' denotes that the product is functioning as expected.
>>```bash
>>mdatp health --field healthy
>>```
>>```bash
>>mdatp health | grep -i 'network\|enabled\|managed_by\|MDE-management\|managed\|real_time_protection\|behavior_monitoring\|edr\|MDE\|org_id\|tag'
>>```    
>>Check the status of the definition update, return value should be up_to_date.
>>```bash
>>mdatp health --field definitions_status
>>```
>>Ensure real-time protection is enabled, the return value should be true.
>>```bash
>>mdatp health --field real_time_protection_enabled
>>```
>>If not, run the following: 
>>```bash
>>sudo mdatp config real-time-protection --value enabled # to enable real-time protection
>>```
>Test MDE on Linux by simulating the download of a "malicious" eicar file. The file should be quarantined.
>```bash
>curl -o ~/eicar.com.txt https://secure.eicar.org/eicar.com.txt
>```
>List the detected threats
>```bash
>mdatp threat list
>```
</details>