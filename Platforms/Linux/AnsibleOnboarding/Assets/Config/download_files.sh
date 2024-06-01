
echo "Downloading the config_control_node.sh file"
curl -o config_control_node.sh "https://raw.githubusercontent.com/coullessi/Microsoft-Defender-for-Endpoint/main/Platforms/Linux/AnsibleOnboarding/Assets/Config/config_controlnode.sh"

echo "Downloading the hoss file, containing the IP addresses of the managed nodes"
curl -o hosts "https://raw.githubusercontent.com/coullessi/Microsoft-Defender-for-Endpoint/main/Platforms/Linux/AnsibleOnboarding/Assets/Config/hosts"

echo "Downloading the onboard_setup.yml file"
curl -o onboard_setup.yml "https://raw.githubusercontent.com/coullessi/Microsoft-Defender-for-Endpoint/main/Platforms/Linux/AnsibleOnboarding/Assets/Config/onboarding_setup.yml"

echo "Downloading the dev_install_mdatp.yml file"
curl -o dev_install_mdatp.yml "https://raw.githubusercontent.com/coullessi/Microsoft-Defender-for-Endpoint/main/Platforms/Linux/AnsibleOnboarding/Assets/Config/dev_install_mdatp.yml"

echo "Downloading the dev_mdatp.repo.yml file"
curl -o dev_mdatp.repo.yml "https://raw.githubusercontent.com/coullessi/Microsoft-Defender-for-Endpoint/main/Platforms/Linux/AnsibleOnboarding/Assets/Config/dev_mdatp.repo.yml"

echo "Downloading the prod_install_mdatp.yml file"
curl -o prod_install_mdatp.yml "https://raw.githubusercontent.com/coullessi/Microsoft-Defender-for-Endpoint/main/Platforms/Linux/AnsibleOnboarding/Assets/Config/prod_install_mdatp.yml"

echo "Downloading the prod_mdatp.repo.yml file"
curl -o prod_mdatp.repo.yml "https://raw.githubusercontent.com/coullessi/Microsoft-Defender-for-Endpoint/main/Platforms/Linux/AnsibleOnboarding/Assets/Config/prod_mdatp.repo.yml"

echo "Downloading the unistall_mdatp.yml file"
curl -o unistall_mdatp.yml "https://raw.githubusercontent.com/coullessi/Microsoft-Defender-for-Endpoint/main/Platforms/Linux/AnsibleOnboarding/Assets/Config/unistall_mdatp.yml"