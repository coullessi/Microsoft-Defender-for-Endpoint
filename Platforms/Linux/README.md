# Welcome: Microsoft Defender for Endpoint on Linux

## Introduction
Through guided steps, you will ramp up with onboarding Microsoft Defender for Endpoint (MDE) on Linux. 
This lab exercise will also walk you through configuring MDE features and capabilities. Using a profile, you will configure MDE preferences (which take precedence over the ones set locally a the device). In other words, users in the enterprise will not be able to change preferences that are set through the configuration profile.

## Prerequisites
- Access to the Microsoft Defender portal.
- Ensure that you have a Microsoft Defender for Endpoint subscription.
- Linux distribution using the **_systemd_** system manager.
- Beginner-level experience in Linux and BASH scripting.
- Administrative privileges on the device (in case of manual deployment).

## Installation instructions
In this lab exercise, you'll install and configure Microsoft Defender for Endpoint on Linux using the following deployment methods:
- [Deploy MDE on Linux Manually](./ManualOnboarding/README.md)
- [Deploy MDE on Linux with a Script](./ScriptOnboarding/README.md)
- [Deploy MDE on Linux with Ansible](./AnsibleOnboarding/README.md)

## Reference documents
[Deploy Microsoft Defender for Endpoint on Linux manually](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/linux-install-manually?view=o365-worldwide)<br>
[Deploy Microsoft Defender for Endpoint on Linux with a Script](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/linux-install-manually?view=o365-worldwide#installer-script)<br>
[Deploy Microsoft Defender for Endpoint on Linux with Ansible](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/linux-install-with-ansible?view=o365-worldwide)<br>
[Install Ansible - Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)<br>
[Install pipx](https://pipx.pypa.io/stable/)