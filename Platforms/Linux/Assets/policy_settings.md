In Microsoft Entra ID, create the following device groups named for example ```Linux - MDE-Prod``` for your prod devices and ```Linux - MDE-Dev``` for your dev devices.<br>
The group membership rule rules could be as follow: 
```yml
# for the production devices
(device.managementType -eq "MicrosoftSense") and (device.deviceOSType -eq "Linux") and (device.displayName -in ["ubta","rhela","deba"])
# for the production devices
(device.managementType -eq "MicrosoftSense") and (device.deviceOSType -eq "Linux") and (device.displayName -contains "dev")
```
```

```bash

```