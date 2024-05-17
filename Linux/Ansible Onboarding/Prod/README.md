## Deploy MDE on Linux with Ansible<br>

### Example of environment

| Ubuntu 22.04-LTS (jammy) | Redhat Linux - RHEL 9 | Debian Linux 11 (bullseye) |
| ---------- | ---------- | ---------- |
| utba (prod device, the control node) | rhela (prod device, a managed node) | deba (prod device, a managed node)|	
| ubtb (dev device, a managed node) | rhelb (dev device, a managed node) | |
		
:information_source: **Some notes**:<br>
In this lab exercise, you do not need to login as the root user to run commands. Only make sure that the user running the commands is part of the _**sudo**_ group for Debian-based (for example Ubuntu) systems and the _**wheel**_ group for a RedHat Enterprise system.
You need to determine the code for Debian-based systems, you'll need to specify the codename when you add the repositories for 'mdatp' to your configuration file 'add_mdatp_repo.yml'. Run ```lsb_release -a``` to find the codename: in this lab, the codename is jammy for Ubuntu 22.04 and bullseye for Debian 11.
One of the VM will be the ansible control node and all other VMs will be the managed nodes, refer to the table of devices above.
Make sure unzip is installed on all managed nodes (Linux VMs that you need to onboard to MDE), for example:<br>
<br>
***Ubuntu***: ```sudo apt install unzip```<br>
***RedHat***: ```sudo yum install unzip```

#### Step 1: Assumption
You can provision Linux VMs using Hyper-V, Azure, or any other virtualization platform.
You can configure and exchange communication keys between devices; SSH is correctly configured, and you can transfer files between devices.
You can find help for the usage of commands by typing <command_name> --help, or man <command_name> to view the full documentation for a command. 
In a terminal, type for example ```apt --help``` to get a summary of the available commands and their usage for the Advanced Package Tool (APT), which is a package management system commonly used in Debian-based Linux distributions.
Type for example ```man ssh-keygen``` to get the detailed documentation of the command-line utility used for generating, managing, and converting authentication keys for SSH (Secure Shell).
You can update a system and install applications, for example for a Debian system, run the following:<br>
```sudo apt update && sudo apt upgrade``` to fully update the system.<br>
```sudo apt install unzip``` to install unzip.

##### Step 2: Create and configure SSH keys, and install Ansible
The assumption is that the files and keys do not exist, you'll need to create them then.
Create a private/public key pair on the Ansible control node that you'll use to automate tasks. 
The command ```ssh-keygen -t rsa -C "ControlNode" -f ~/.ssh/ControlNodeKey``` will generate a private/public key pair and store them in the ControlNodeKey and ControlNodeKey.pub files respectively.
You may also need to create the the know_hosts and known_hosts.old files on the devices if they do not exist. The **known_hosts** and **known_hosts.old** files are related to SSH (Secure Shell) and play a crucial role in verifying the identity of remote servers before establishing a connection. 
The known_hosts file stores the public keys of servers that you have connected to using SSH.
The known_hosts.old file is a backup of the known_hosts file.<br>
##### Generate SSH keys
```bash
ssh-keygen -t rsa -C "ControlNode" -f ~/.ssh/ControlNodeKey
sudo vim ~/.ssh/config # add the following line: IdentityFile ~/.ssh/ControlNodeKey - I use 'vim' to edit files, you use any other editor
ls ~/.ssh/ # to view the list of files. You'll have the following: config, ControlNodeKey, ControlNodeKey.pub
cat ~/.ssh/ControlNodeKey.pub # to display the value of the public key, copy it, you will add it to the ~/.ssh/authorized_keys file on the managed nodes.
```
Copy the value of the public key to the ansible managed nodes to the following file: ```~/.ssh/authorized_keys```
If either the directory ```.ssh``` or the file ```authorized_keys``` do not exist, create them.
Paste the value of the public key in the authorized_keys file and save the file.

##### Create the .ssh directory and the authorized_keys file under the .ssh directory
```bash 
mkdir ~/.ssh # to create the .ssh directory
touch ~/.ssh/authorized_keys # or sudo vim ~/.ssh/authorized_keys. (I use vim so the file is created and opened in edit mode).  
```
<br>##### Create the ***known_hosts*** and the ***known_hosts.old*** files 
```bash
sudo touch ~/.ssh/known_hosts ~/.ssh/known_hosts.old # This create the known_hosts and known_hosts.old files.
sudo chown lessi:lessi ~/.ssh/known_hosts ~/.ssh/known_hosts.old # In this case, the user lessi is both the owner and group of the files.
```
<br>##### Install Ansible on the control node (example of Ubuntu device)
```bash
sudo apt update
sudo apt install pipx
pipx install --include-deps ansible
pipx ensurepath
pipx upgrade --include-injected ansible
pipx inject ansible argcomplete
pipx inject --include-apps ansible argcomplete
activate-global-python-argcomplete --user
sudo pipx ensurepath
```
<br>All the above commands are also supplied in the config_controlnode.sh file. You can run that file once to generate the SSH keys and install Ansible.

[Bash Script: Configure Control Node](./Linux/AnsibleOboarding/Prod/Assets#config_controlnode.sh)<br>
<br>**config_controlnode.sh**
```bash
#!/bin/bash

echo "####################################################################"
echo "Creating the known_hosts file to store the keys of the managed nodes"
echo "####################################################################"
sudo touch ~/.ssh/known_hosts ~/.ssh/known_hosts.old
sudo chown lessi:lessi ~/.ssh/known_hosts ~/.ssh/known_hosts.old
echo

echo "####################################################################"
echo "Creating a private/public key pair to automate ansible tasks"
echo "Press Enter to continue twice when prompted for passphrase"
echo "####################################################################"
echo
sudo ssh-keygen -t rsa -C 'ControlNode' -f ~/.ssh/ControlNodeKey
sudo chown lessi:lessi ~/.ssh/ControlNodeKey ~/.ssh/ControlNodeKey.pub
echo
echo "####################################################################"
echo    "Create a config file to store ansible control node private key"
echo "####################################################################"
sudo touch ~/.ssh/config # comment this line if the ~/.ssh/config file already exist
sudo chown lessi:lessi ~/.ssh/config
echo "IdentityFile ~/.ssh/ControlNodeKey" >> ~/.ssh/config
echo

echo "####################################################################"
echo                          Installing Ansible
echo "####################################################################"

echo "Installing pipx and ansible"
echo
sudo apt update
sudo apt install pipx
    
pipx install --include-deps ansible
pipx ensurepath
pipx upgrade --include-injected ansible
pipx inject ansible argcomplete
pipx inject --include-apps ansible argcomplete
activate-global-python-argcomplete --user
sudo pipx ensurepath
echo
echo
echo "Ansible installed successfully, type 'exit' to exit the shell"
echo "Start a new shell and run 'ansible --version' to check the version of ansible installed"
```

Once Ansible is installed, log out and log back into the system.

#### Step 3: Download onboarding package
Go to _security.microsoft.com > Settings > Endpoints > Onboarding_ and select the following:
- ```Operation system```: Linux Server
- ```Connectivity type```: Streamlined
- ```Deployment method```: Your preferred Linux configuration management tool
- ```Click Download onboarding package```.

#### Step 4: Create the configuration files
In addition to the downloaded onboarding package, use your favorite editor (Visual Studio code - that's what I use) to create the hosts, add_mdatp_repo.yml, onboarding_setup.yml, and install_mdatp.yml files.

- __GatewayWindowsDefenderATPOnboardingPackage.zip__ file downloaded from the Defender portal<br>
- __hosts__
```yml
[servers]
ubta ansible_ssh_host=10.160.124.4
rhela ansible_ssh_host=10.160.124.9
deba ansible_ssh_host=10.160.124.10
```
- __add_mdatp_repo.yml__
```yml
- name: Ubuntu - Add Microsoft APT key
  apt_key:
    url: https://packages.microsoft.com/keys/microsoft.asc
    state: present
  when: ansible_os_family == "Debian"

- name: Ubuntu - Add Microsoft apt repository for MDATP
  apt_repository:
    repo: deb [arch=amd64] https://packages.microsoft.com/ubuntu/22.04/prod jammy main
    update_cache: yes
    state: present
    filename: microsoft-prod
  when: ansible_os_family == "Debian"

- name: Debian - Add Microsoft APT key
  apt_key:
    url: https://packages.microsoft.com/keys/microsoft.asc
    state: present
  when: ansible_os_family == "Debian"

- name: Debian - Add Microsoft apt repository for MDATP
  apt_repository:
    repo: deb [arch=amd64] https://packages.microsoft.com/debian/11/prod bullseye main
    update_cache: yes
    state: present
    filename: microsoft-prod
  when: ansible_os_family == "Debian"

- name: RedHat - Add Microsoft DNF/YUM key
  rpm_key:
    state: present
    key: https://packages.microsoft.com/keys/microsoft.asc
  when: ansible_os_family == "RedHat"

- name: RedHat - Add  Microsoft yum repository for MDATP
  yum_repository:
    name: packages-microsoft-prod
    description: Microsoft Defender for Endpoint
    file: microsoft-prod
    baseurl: https://packages.microsoft.com/rhel/9/prod
    gpgcheck: yes
    enabled: Yes
  when: ansible_os_family == "RedHat"
```

- __onboarding_setup.yml__
```yml
- name: Create MDATP directories
  file:
    path: /etc/opt/microsoft/mdatp/
    recurse: true
    state: directory
    mode: 0755
    owner: root
    group: root

- name: Register mdatp_onboard.json
  stat:
    path: /etc/opt/microsoft/mdatp/mdatp_onboard.json
  register: mdatp_onboard

- name: Extract GatewayWindowsDefenderATPOnboardingPackage.zip
  unarchive:
    src: GatewayWindowsDefenderATPOnboardingPackage.zip
    dest: /etc/opt/microsoft/mdatp
    mode: 0600
    owner: root
    group: root
  when: not mdatp_onboard.stat.exists
```

- __install_mdatp.yml__
```yml
- hosts: servers
  become: yes
  tasks:
    - ansible.builtin.include_tasks: onboarding_setup.yml
    - ansible.builtin.include_tasks: add_mdatp_repo.yml
    - name: Update Debian (apt)
      apt:
        update_cache: yes
        upgrade: dist
      when: ansible_os_family == 'Debian'

    - name: Update RedHat (yum)
      yum:
        name: '*'
        state: latest
      when: ansible_os_family == 'RedHat'

    - name: Install MDATP - Debian
      apt:
        name: mdatp
        state: latest
        update_cache: yes
      when: ansible_os_family == "Debian"

    - name: Install MDATP - RedHat
      yum:
        name: mdatp
        state: latest
        update_cache: yes
      when: ansible_os_family == "RedHat"

    - name: Debian - Setting Device Tag to MDE-Management
      ansible.builtin.shell:
        cmd: mdatp edr tag set --name GROUP --value 'MDE-Management'
      when: ansible_os_family == "Debian"

    - name: RedHat - Setting Device Tag to MDE-Management
      ansible.builtin.shell:
        cmd: mdatp edr tag set --name GROUP --value 'MDE-Management'
      when: ansible_os_family == "RedHat"
```

- __uninstall_mdatp.yml__
```yml
- hosts: servers
  become: true
  tasks:
    - name: Uninstall MDATP - Debian
      apt:
        name: mdatp
        state: absent
      when: ansible_os_family == "Debian"
    - name: Uninstall MDATP - RedHat
      yum:
        name: mdatp
        state: absent
      when: ansible_os_family == "RedHat"
```

#### Step 5: Copy files to the remote Linux Server (Ansible Control Node) 
In the example below that copies all files from the source folder to the destination directory (the destination directory will be created if it doesn't exist), the following are specified:
- __scp__ (command for a secure copy over SSH)
- __Port number__ (port 45733 where the remote server is listening from incoming SSH requests)
- __Location of the SSH private key__: E:\Repo\Linux\Connect\LocalHostKey, if you do not have a key configure, you can provide a password when prompted. 
- __Source folder__ (folder containing files to be transferred): E:\Repo\Linux\MDELinux\ansible\prod 
- __Destination directory__ (Remote server and destination where files will be transferred): ```lessi@domain.com:~/ansible.```, where ```domain.com``` can also be an ```IP address```.
<br>__Example of command__: ```scp -P 45733 -i E:\Repo\Linux\Connect\LocalHostKey -r E:\Repo\Linux\MDELinux\ansible\prod lessi@domain.com:~/ansible```.

On the Linux Server, run ```ls prod``` to verify all files are copied from your local system to the Ansible control node.

#### Step 6: Install mdatp
___Verify that you can communicate with all ansible nodes that you want to onboard by running ```ansible -i hosts servers -m ping``` where hosts is the list of your managed nodes and servers are specific devices within that list. Make sure you have a "SUCCESS" for all pings and that python3 is discovered.___
___Then run  ```ansible -K install_mdatp.yml -i hosts``` to install MDE on your list of devices.___
```bash
ansible -i hosts servers -m ping
ansible-playbook -K install_mdatp.yml -i hosts
```
___Verify the list of onboarded devices from the Defender portal___
You should end up with a list of devices after the devices are managed by MDE. Allow up to 24 hours for devices to be managed by MDE.

___Create/ configure endpoint security policies for your newly onboarded devices___

Verify the onboarding status on a device and notice that the device is managed by MDE
Run the following command: ```mdatp health | grep -i 'managed\|managed_by\|MDE'```.

Run a threat detection test
Run the following commands, for example from the home directory: 
<br>```curl -o eicar.com.txt "https://secure.eicar.org/eicar.com.txt"``` to donwnload the eicar file.
<br>Run ``ls`` and notice that the downloaded file does not exist; it has been quarantined.
<br>Run ```mdatp threat list``` to view the list of threat found, also notice the quarantined status.You'll also be able to view the correponding alert/incident from the Defender portal.

#### Step 7: Uninstall mdatp - Do not run this unless you want to uninstall MDE on devices
just in case you want to remove mdatp from devices and offboard them from a tenant
```bash
ansible -i hosts all -m ping
ansible-playbook -K uninstall_mdatp.yml -i hosts
```
