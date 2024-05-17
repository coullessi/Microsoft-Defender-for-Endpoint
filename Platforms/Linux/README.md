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

## Example of environment
- Control node (prod): ubta
- Managed node (prod): rhela
- Managed node (prod): deba
- Managed node (dev):  ubtb
- Managed node (dev):  rhelb
| Ubuntu 22.04-LTS (jammy) | Redhat Linux - RHEL 9 | Debian Linux 11 (bullseye) |
| ---------- | ---------- | ---------- |
| **utba** | **rhela** | **deba**|	
| **ubtb** | **rhelb** | |

## Installation instructions
In this lab exercise, you'll install and configure Microsoft Defender for Endpoint on Linux using the following deployment methods:
- [Deploy MDE on Linux Manually](./ManualOnboarding/README.md)
- [Deploy MDE on Linux with a Script](./ScriptOnboarding/README.md)
- [Deploy MDE on Linux with Ansible](./AnsibleOnboarding/README.md)
