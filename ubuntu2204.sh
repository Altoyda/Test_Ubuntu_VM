#!/bin/bash

# Define color codes
NC='\033[0m' # No Color
ICyan='\033[0;96m' # Cyan
Green='\033[0;32m' # Green
Red='\033[0;31m' # Red

# Define functions

# Get needed scripts
get_scripts() {
    # shellcheck source=lib.sh
    source <(curl -sL https://raw.githubusercontent.com/Altoyda/Test_Ubuntu_VM/main/lib.sh)
}

download_script() {
    script_name="$1"
    script_url="$2"

    if [ -f "$script_name" ]
    then
        rm "$script_name"
    fi

    wget -q "$script_url" -O "$script_name"
    chmod +x "$script_name"
}

# Download needed libraries before execution of the first script
# Create $SCRIPTS dir
if [ ! -d "$SCRIPTS" ]
then
    mkdir -p "$SCRIPTS"
fi
mkdir -p "$SCRIPTS"
download_script "lib.sh" "https://raw.githubusercontent.com/Altoyda/Test_Ubuntu_VM/main/lib.sh"
download_script STATIC fetch_lib
download_script STATIC nextcloud
download_script APPS vaultwarden
download_script APPS vaultwarden_admin-panel
download_script APPS webmin
download_script APPS fail2ban
download_script NOT-SUPPORTED firewall
download_script NETWORK static_ip

# Set locales
run_script ADDONS locales

# Make $SCRIPTS excutable
chmod +x -R "$SCRIPTS"
chown root:root -R "$SCRIPTS"

# Execute functions
set_max_count
set_nofile_limits
configure_pam_limits

# VARIABLES

# Script information
SCRIPT_NAME="Ubuntu 22.04 LTS (server)"
SCRIPT_EXPLAINER="This script is installing all requirements that are needed for Ubuntu to run.
It's the first of two parts that are necessary to finish your customized Ubuntu installation."

echo -e "${ICyan}Running script for ${SCRIPT_NAME}...${NC}"
echo -e "${ICyan}${SCRIPT_EXPLAINER}${NC}"

# Check distribution and version
if ! version 22.04 "$DISTRO" 22.04.10
then
    msg_box "This script can only be run on Ubuntu 22.04 (server)."
    exit 1
fi

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode() {
    if [ $DEBUG -eq 1 ]
    then
        set -x
    fi
}

# Check if script is running as root
if [ "$EUID" -ne 0 ]
then
    msg_box "Please run this script as root."
    exit 1
fi

# Prefer IPv4 for apt
echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4

# Fix fancy progress bar for apt-get
# https://askubuntu.com/a/754653
if [ -d /etc/apt/apt.conf.d ]
then
    if ! [ -f /etc/apt/apt.conf.d/99progressbar ]
    then
        echo 'Dpkg::Progress-Fancy "1";' > /etc/apt/apt.conf.d/99progressbar
        echo 'APT::Color "1";' >> /etc/apt/apt.conf.d/99progressbar
        chmod 644 /etc/apt/apt.conf.d/99progressbar
    fi
fi

# Automatically restart services
# Restart mode: (l)ist only, (i)nteractive or (a)utomatically.
sed -i "s|#\$nrconf{restart} = .*|\$nrconf{restart} = 'a';|g" /etc/needrestart/needrestart.conf

# Force MOTD to show correct number of updates
if is_this_installed update-notifier-common
then
    sudo /usr/lib/update-notifier/update-motd-updates-available --force
fi

# Check universe repository
check_universe() {
UNIV=$(apt-cache policy | grep http | awk '{print $3}' | grep universe | head -n 1 | cut -d "/" -f 2)
if [ "$UNIV" != "universe" ]
then
    print_text_in_color "$ICyan" "Adding required repo (universe)."
    yes | add-apt-repository universe
fi
}

# Check universe repository
check_multiverse() {
if [ "$(apt-cache policy | grep http | awk '{print $3}' | grep multiverse | head -n 1 | cut -d "/" -f 2)" != "multiverse" ]
then
    print_text_in_color "$ICyan" "Adding required repo (multiverse)."
    yes | add-apt-repository multiverse
fi
}

# We don't want automatic updates since they might fail (we use our own script)
if is_this_installed unattended-upgrades
then
    apt-get purge unattended-upgrades -y
    apt-get autoremove -y
    rm -rf /var/log/unattended-upgrades
fi

# Install packages
# Function to print a colored message box
msg_box() {
    message="$1"
    color_code="$2"

    echo -e "${color_code}==========================================="
    echo -e " $message"
    echo -e "===========================================${NC}"
}

install_if_not() {
    package_name=$1

    if [ "$(dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -c "ok installed")" = "1" ]; then
        msg_box "$package_name OK" "${GREEN}"
    else
        apt-get update -q4
        apt-get install "$package_name" -y
        msg_box "Installed $package_name" "${CYAN}"
    fi
}

# Install required packages
install_if_not "lshw"
install_if_not "net-tools"
install_if_not "apt-utils"
install_if_not "keyboard-configuration"
install_if_not "bash-completion"
install_if_not "iputils-ping"
install_if_not "netplan.io"
install_if_not "apt-transport-https"
install_if_not "build-essential"
install_if_not "nano"
install_if_not "cron"
install_if_not "sudo"
install_if_not "software-properties-common"
install_if_not "open-vm-tools"
install_if_not "figlet"
install_if_not "curl"
install_if_not "update-notifier-common"

# Cleanup
apt-get autoremove -y
apt-get autoclean

# Set DNS resolver
# https://unix.stackexchange.com/questions/442598/how-to-configure-systemd-resolved-and-systemd-networkd-to-use-local-dns-server-f
while :
do
    if [ -n "$PROVISIONING" ]
    then
        choice="Quad9"
    else
        choice=$(whiptail --title "$TITLE - Set DNS Resolver" --menu \
"Which DNS provider should this Nextcloud box use?
$MENU_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"Quad9" "(https://www.quad9.net/)" \
"Cloudflare" "(https://www.cloudflare.com/dns/)" \
"Local" "($GATEWAY) - DNS on gateway" \
"Expert" "If you really know what you're doing!" 3>&1 1>&2 2>&3)
    fi

    case "$choice" in
        "Quad9")
            sed -i "s|^#\?DNS=.*$|DNS=9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9|g" /etc/systemd/resolved.conf
        ;;
        "Cloudflare")
            sed -i "s|^#\?DNS=.*$|DNS=1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001|g" /etc/systemd/resolved.conf
        ;;
        "Local")
            sed -i "s|^#\?DNS=.*$|DNS=$GATEWAY|g" /etc/systemd/resolved.conf
            systemctl restart systemd-resolved.service
            if network_ok
            then
                break
            else
                msg_box "Could not validate the local DNS server. Pick an Internet DNS server and try again."
                continue
            fi
        ;;
        "Expert")
            OWNDNS=$(input_box_flow "Please choose your own DNS server(s) with a space in between, e.g: $GATEWAY 9.9.9.9 (NS1 NS2)")
            sed -i "s|^#\?DNS=.*$|DNS=$OWNDNS|g" /etc/systemd/resolved.conf
            systemctl restart systemd-resolved.service
            if network_ok
            then
                break
                unset OWNDNS 
            else
                msg_box "Could not validate the local DNS server. Pick an Internet DNS server and try again."
                continue
            fi
        ;;
        *)
        ;;
    esac
    if test_connection
    then
        break
    else
        msg_box "Could not validate the DNS server. Please try again."
    fi
done

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    # Install Docker
    msg_box "Docker is not installed. Installing..."
    
    # Set up Docker's Apt repository
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    msg_box "Docker installed successfully."
else
    msg_box "Docker is already installed."
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
    # Install Docker Compose
    msg_box "Docker Compose is not installed. Installing..."
    sudo apt-get install -y docker-compose
    msg_box "Docker Compose installed successfully."
else
    msg_box "Docker Compose is already installed."
fi

# Prompt user for Docker group name
read -p "Enter the name to add to the Docker group: " DOCKER_USER

# Add user to Docker group
sudo usermod -aG docker $DOCKER_USER
msg_box "User $DOCKER_USER added to Docker group. Please log out and log back in for the changes to take effect."

# Prompt user for Docker data storage directory
read -p "Enter the directory for Docker data storage (default is /home/docker): " DOCKER_DIR

# Set default Docker data storage directory
DOCKER_DIR="${DOCKER_DIR:-/home/docker}"

# Create the directory
sudo mkdir -p $DOCKER_DIR

# Modify access permissions
sudo chmod -R 775 $DOCKER_DIR

# Change ownership of the directory
sudo chown -R $USER:$USER $DOCKER_DIR

# Verify permissions and ownership
msg_box "Directory permissions and ownership:"
ls -ld $DOCKER_DIR

# Function to display colored message box
msg_box() {
    local color="\e[1;36m"  # Cyan color
    local reset="\e[0m"      # Reset color

    echo -e "${color}========================================================${reset}"
    echo -e "${color} $1 ${reset}"
    echo -e "${color}========================================================${reset}"
}

# Check if GRUB_CMDLINE_LINUX_DEFAULT contains "maybe-ubiquity"
msg_box "Checking GRUB_CMDLINE_LINUX_DEFAULT"
if grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="maybe-ubiquity"' /etc/default/grub; then
    # If found, replace the entire line with an empty value
    sed -i 's|GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=|' /etc/default/grub
fi

# Check if "cloud-init" is already set in GRUB_CMDLINE_LINUX
msg_box "Checking GRUB_CMDLINE_LINUX"
if grep -q 'GRUB_CMDLINE_LINUX=".*cloud-init.*"' /etc/default/grub; then
    echo "cloud-init is already set in GRUB_CMDLINE_LINUX"
else
    # If "cloud-init" is not set, add it to GRUB_CMDLINE_LINUX
    sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="cloud-init.disabled"|' /etc/default/grub
fi

# Disable cloud-init by creating a file if it doesn't exist
msg_box "Creating /etc/cloud/cloud-init.disabled"
if [ ! -f /etc/cloud/cloud-init.disabled ]; then
    touch /etc/cloud/cloud-init.disabled
fi

# Regenerate GRUB configuration if changes were made
msg_box "Regenerating GRUB configuration"
if [ -n "$(diff /etc/default/grub /etc/default/grub~)" ]; then
    grub-mkconfig -o /boot/efi/EFI/ubuntu/grub.cfg
fi

msg_box() {
    echo "*************************************"
    echo "* $1"
    echo "*************************************"
}

# Function to print text in color
print_text_in_color() {
    color_code="$1"
    text="$2"
    echo -e "${color_code}${text}${NC}"
}

# Function to set max count in /etc/sysctl.conf
set_max_count() {
    if grep -F 'vm.max_map_count=512000' /etc/sysctl.conf ; then
        print_text_in_color "$ICyan" "Max map count already set, skipping..."
    else
        sysctl -w vm.max_map_count=512000
        {
            echo "###################################################################"
            echo "# Docker ES max virtual memory"
            echo "vm.max_map_count=512000"
            echo "fs.file-max=100000"
            echo "vm.overcommit_memory=1"
        } >> /etc/sysctl.conf
        print_text_in_color "$Green" "Max map count set in /etc/sysctl.conf"
    fi
}

# Function to set nofile limits in /etc/security/limits.conf
set_nofile_limits() {
    if grep -F '* soft nofile 1000000' /etc/security/limits.conf && grep -F '* hard nofile 1000000' /etc/security/limits.conf ; then
        print_text_in_color "$ICyan" "Nofile limits already set, skipping..."
    else
        {
            echo "* soft nofile 1000000"
            echo "* hard nofile 1000000"
        } >> /etc/security/limits.conf
        print_text_in_color "$Green" "Nofile limits set in /etc/security/limits.conf"
    fi
}

# Function to configure pam_limits in /etc/pam.d/common-session
configure_pam_limits() {
    if grep -F 'session required pam_limits.so' /etc/pam.d/common-session ; then
        print_text_in_color "$ICyan" "pam_limits already configured, skipping..."
    else
        echo 'session required        pam_limits.so' >> /etc/pam.d/common-session
        print_text_in_color "$Green" "pam_limits configured in /etc/pam.d/common-session"
    fi
}

# Function to print text in color
print_text_in_color() {
    color_code="$1"
    text="$2"
    echo -e "${color_code}${text}${NC}"
}

# Function to show a msg_box
msg_box() {
    title="$1"
    message="$2"
    whiptail --title "$title" --msgbox "$message" "$WT_HEIGHT" "$WT_WIDTH"
}

# Function to set the system time
set_system_time() {
    new_time="$1"
    timedatectl set-time "$new_time"
    print_text_in_color "$Green" "System time set to $new_time."
}

# Define color codes
NC='\033[0m' # No Color
Green='\033[0;32m' # Green

# Show a msg_box
msg_box "Set System Time" "This script will set the system time. Please provide the new time in the format YYYY-MM-DD HH:MM:SS."

# Input box for user to enter the new time
new_time=$(whiptail --title "Enter New Time" --inputbox "Enter the new time:" "$WT_HEIGHT" "$WT_WIDTH" 3>&1 1>&2 2>&3)

# Check if the user pressed Cancel or entered an empty string
if [ -z "$new_time" ]; then
    print_text_in_color "$ICyan" "Setting time cancelled."
    exit 1
fi

# Set the system time
set_system_time "$new_time"
