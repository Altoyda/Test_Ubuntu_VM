#!/bin/bash

# Prefer IPv4 for apt
echo 'Acquire::ForceIPv4 "true";' >> /etc/apt/apt.conf.d/99force-ipv4

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

# Install curl if not existing
if [ "$(dpkg-query -W -f='${Status}' "curl" 2>/dev/null | grep -c "ok installed")" = "1" ]
then
    echo "curl OK"
else
    apt-get update -q4
    apt-get install curl -y
fi

true
SCRIPT_NAME="Ubuntu 22.04 LTS (server)"
SCRIPT_EXPLAINER="This script is installing all requirements that are needed for Ubuntu to run.
It's the first of two parts that are necessary to finish your customized Ubuntu installation."
# shellcheck source=lib.sh
source <(curl -sL https://raw.githubusercontent.com/Altoyda/Test_Ubuntu_VM/main/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
root_check

# Test RAM size (2GB min) + CPUs (min 1)
ram_check 2 Ubuntu
cpu_check 1 Ubuntu

# Check if dpkg or apt is running
is_process_running apt
is_process_running dpkg

# Check distribution and version
if ! version 22.04 "$DISTRO" 22.04.10
then
    msg_box "This script can only be run on Ubuntu 22.04 (server)."
    exit 1
fi

# Automatically restart services
# Restart mode: (l)ist only, (i)nteractive or (a)utomatically.
sed -i "s|#\$nrconf{restart} = .*|\$nrconf{restart} = 'a';|g" /etc/needrestart/needrestart.conf

# Check for flags
if [ "$1" = "" ]
then
    print_text_in_color "$ICyan" "Running in normal mode..."
    sleep 1
elif [ "$1" = "--provisioning" ] || [ "$1" = "-p" ]
then
    print_text_in_color "$ICyan" "Running in provisioning mode..."
    export PROVISIONING=1
    sleep 1
elif [ "$1" = "--not-latest" ]
then
    NOT_LATEST=1
    print_text_in_color "$ICyan" "Running in not-latest mode..."
    sleep 1
else
    msg_box "Failed to get the correct flag. Did you enter it correctly?"
    exit 1
fi

# Show explainer
if [ -z "$PROVISIONING" ]
then
    msg_box "$SCRIPT_EXPLAINER"
fi

# Create a placeholder volume before modifying anything
if [ -z "$PROVISIONING" ]
then
    if ! does_snapshot_exist "NcVM-installation" && yesno_box_no "Do you want to use LVM snapshots to be able to restore your root partition during upgrades and such?
Please note: this feature will not be used by this script but by other scripts later on.
For now we will only create a placeholder volume that will be used to let some space for snapshot volumes.
Be aware that you will not be able to use the built-in backup solution if you choose 'No'!
Enabling this will also force an automatic reboot after running the update script!"
    then
        check_free_space
        if [ "$FREE_SPACE" -ge 50 ]
        then
            print_text_in_color "$ICyan" "Creating volume..."
            sleep 1
            # Create a placeholder snapshot
            check_command lvcreate --size 5G --name "NcVM-installation" ubuntu-vg
        else
            print_text_in_color "$IRed" "Could not create volume because of insufficient space..."
            sleep 2
        fi
    fi
fi

# Fix LVM on BASE image
if grep -q "LVM" /etc/fstab
then
    if [ -n "$PROVISIONING" ] || yesno_box_yes "Do you want to make all free space available to your root partition?"
    then
    # Resize LVM (live installer is &%¤%/!
    # VM
    print_text_in_color "$ICyan" "Extending LVM, this may take a long time..."
    lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv

    # Run it again manually just to be sure it's done
    while :
    do
        lvdisplay | grep "Size" | awk '{print $3}'
        if ! lvextend -L +10G /dev/ubuntu-vg/ubuntu-lv >/dev/null 2>&1
        then
            if ! lvextend -L +1G /dev/ubuntu-vg/ubuntu-lv >/dev/null 2>&1
            then
                if ! lvextend -L +100M /dev/ubuntu-vg/ubuntu-lv >/dev/null 2>&1
                then
                    if ! lvextend -L +1M /dev/ubuntu-vg/ubuntu-lv >/dev/null 2>&1
                    then
                        resize2fs /dev/ubuntu-vg/ubuntu-lv
                        break
                    fi
                fi
            fi
        fi
    done
    fi
fi

# Install needed dependencies
install_if_not lshw
install_if_not net-tools
install_if_not whiptail
install_if_not apt-utils
install_if_not keyboard-configuration

# Nice to have dependencies
install_if_not bash-completion
install_if_not htop
install_if_not iputils-ping

# Download needed libraries before execution of the first script
mkdir -p "$SCRIPTS"
download_script GITHUB_REPO lib
download_script STATIC fetch_lib

# Set locales
run_script ADDONS locales

# Create new current user
download_script STATIC adduser
bash "$SCRIPTS"/adduser.sh "nextcloud_install_production.sh"
rm -f "$SCRIPTS"/adduser.sh

check_universe
check_multiverse

# # Check if key is available
# if ! site_200 "$NCREPO"
# then
#     msg_box "Nextcloud repo is not available, exiting..."
#     exit 1
# fi

# Test Home/SME function
if home_sme_server
then
    msg_box "This is the Home/SME server, function works!"
else
    print_text_in_color "$ICyan" "Home/SME Server not detected. No worries, just testing the function."
    sleep 3
fi

# We don't want automatic updates since they might fail (we use our own script)
if is_this_installed unattended-upgrades
then
    apt-get purge unattended-upgrades -y
    apt-get autoremove -y
    rm -rf /var/log/unattended-upgrades
fi

# Create $SCRIPTS dir
if [ ! -d "$SCRIPTS" ]
then
    mkdir -p "$SCRIPTS"
fi

# Install needed network
install_if_not netplan.io

# APT over HTTPS
install_if_not apt-transport-https

# Install build-essentials to get make
install_if_not build-essential

# Install a decent text editor
install_if_not nano

# Install package for crontab
install_if_not cron

# Make sure sudo exists (needed in adduser.sh)
install_if_not sudo

# Make sure add-apt-repository exists (needed in lib.sh)
install_if_not software-properties-common

# Set dual or single drive setup
if [ -n "$PROVISIONING" ]
then
    choice="2 Disks Auto"
else
    msg_box "This server is designed to run with two disks, one for OS and one for DATA. \
This will get you the best performance since the second disk is using ZFS which is a superior filesystem.

Though not recommended, you can still choose to only run on one disk, \
if for example it's your only option on the hypervisor you're running.

You will now get the option to decide which disk you want to use for DATA, \
or run the automatic script that will choose the available disk automatically."

    choice=$(whiptail --title "$TITLE - Choose disk format" --nocancel --menu \
"How would you like to configure your disks?
$MENU_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"2 Disks Auto" "(Automatically configured)" \
"2 Disks Manual" "(Choose by yourself)" \
"1 Disk" "(Only use one disk /mnt/ncdata - NO ZFS!)" 3>&1 1>&2 2>&3)
fi

case "$choice" in
    "2 Disks Auto")
        run_script DISK format-sdb
        # Change to zfs-mount-generator
        run_script DISK change-to-zfs-mount-generator
        # Create daily zfs prune script
        run_script DISK create-daily-zfs-prune

    ;;
    "2 Disks Manual")
        run_script DISK format-chosen
        # Change to zfs-mount-generator
        run_script DISK change-to-zfs-mount-generator
        # Create daily zfs prune script
        run_script DISK create-daily-zfs-prune
    ;;
    "1 Disk")
        print_text_in_color "$IRed" "1 Disk setup chosen."
        sleep 2
    ;;
    *)
    ;;
esac

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

# Install VM-tools
if [ "$SYSVENDOR" == "VMware, Inc." ];
then
    install_if_not open-vm-tools
elif [[ "$SYSVENDOR" == "QEMU" || "$SYSVENDOR" == "Red Hat" ]];
then
    install_if_not qemu-guest-agent
    systemctl enable qemu-guest-agent
    systemctl start qemu-guest-agent
fi

# Install Figlet
install_if_not figlet

# Cleanup
apt-get autoremove -y
apt-get autoclean
find /root "/home/$UNIXUSER" -type f \( -name '*.sh*' -o -name '*.html*' -o -name '*.tar*' -o -name '*.zip*' \) -delete

# Install virtual kernels for Hyper-V, (and extra for UTF8 kernel module + Collabora and OnlyOffice)
# Kernel 5.4
if ! home_sme_server
then
    if [ "$SYSVENDOR" == "Microsoft Corporation" ]
    then
        # Hyper-V
        install_if_not linux-virtual
        install_if_not linux-image-virtual
        install_if_not linux-tools-virtual
        install_if_not linux-cloud-tools-virtual
        install_if_not linux-azure
        # linux-image-extra-virtual only needed for AUFS driver with Docker
    fi
fi

# Add aliases
if [ -f /root/.bash_aliases ]
then
    if ! grep -q "nextcloud" /root/.bash_aliases
    then
{
echo "alias nextcloud_occ='sudo -u www-data php /var/www/nextcloud/occ'"
echo "alias run_update_nextcloud='bash /var/scripts/update.sh'"
} >> /root/.bash_aliases
    fi
elif [ ! -f /root/.bash_aliases ]
then
{
echo "alias nextcloud_occ='sudo -u www-data php /var/www/nextcloud/occ'"
echo "alias run_update_nextcloud='bash /var/scripts/update.sh'"
} > /root/.bash_aliases
fi

# Fix GRUB defaults
if grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="maybe-ubiquity"' /etc/default/grub
then
    sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=|g" /etc/default/grub
fi

# # Set secure permissions final (./data/.htaccess has wrong permissions otherwise)
# bash "$SECURE" & spinner_loading

# Put IP address in /etc/issue (shown before the login)
if [ -f /etc/issue ]
then
   printf '%s\n' "\4" >> /etc/issue
fi

# Fix Realtek on PN51
if asuspn51
then
    if ! version 22.04 "$DISTRO" 22.04.10
    then
        # Upgrade Realtek drivers
        print_text_in_color "$ICyan" "Upgrading Realtek firmware..."
        curl_to_dir https://raw.githubusercontent.com/Altoyda/Test_Ubuntu_VM/main/network/asusnuc pn51.sh "$SCRIPTS"
        bash "$SCRIPTS"/pn51.sh
    fi
fi

# Update if it's the Home/SME Server
if home_sme_server
then
    # Upgrade system
    print_text_in_color "$ICyan" "System will now upgrade..."
    run_script STATIC update
fi

# Force MOTD to show correct number of updates
if is_this_installed update-notifier-common
then
    sudo /usr/lib/update-notifier/update-motd-updates-available --force
fi

# It has to be this order:
# Download scripts
# chmod +x
# Set permissions for ncadmin in the change scripts

print_text_in_color "$ICyan" "Getting scripts from GitHub to be able to run the first setup..."

# Get needed scripts for first bootup
download_script GITHUB_REPO nextcloud-startup-script
download_script STATIC instruction
download_script STATIC history
download_script NETWORK static_ip
# Moved from the startup script 2021-01-04
download_script LETS_ENC activate-tls
download_script STATIC update
download_script STATIC setup_secure_permissions_nextcloud
download_script STATIC change_db_pass
download_script STATIC nextcloud
download_script MENU menu
download_script MENU server_configuration
download_script MENU nextcloud_configuration
download_script MENU additional_apps
download_script MENU desec_menu

# Make $SCRIPTS excutable
chmod +x -R "$SCRIPTS"
chown root:root -R "$SCRIPTS"

# Prepare first bootup
check_command run_script STATIC change-ncadmin-profile
check_command run_script STATIC change-root-profile

# Disable hibernation
print_text_in_color "$ICyan" "Disable hibernation..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Reboot
if [ -z "$PROVISIONING" ]
then
    msg_box "Installation almost done, system will reboot when you hit OK.

After reboot, please login to run the setup script."
fi
reboot
