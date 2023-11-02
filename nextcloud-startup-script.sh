#!/bin/bash

#########

IRed='\e[0;91m'         # Red
IGreen='\e[0;92m'       # Green
ICyan='\e[0;96m'        # Cyan
Color_Off='\e[0m'       # Text Reset
print_text_in_color() {
	printf "%b%s%b\n" "$1" "$2" "$Color_Off"
}

print_text_in_color "$ICyan" "Fetching all the variables from lib.sh..."

is_process_running() {
PROCESS="$1"

while :
do
    RESULT=$(pgrep "${PROCESS}")

    if [ "${RESULT:-null}" = null ]; then
            break
    else
            print_text_in_color "$ICyan" "${PROCESS} is running, waiting for it to stop..."
            sleep 10
    fi
done
}

#########

# Check if dpkg or apt is running
is_process_running apt
is_process_running dpkg

true
SCRIPT_NAME="Nextcloud Startup Script"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh

# Check if root
root_check

# Create a snapshot before modifying anything
check_free_space
if does_snapshot_exist "NcVM-installation" || [ "$FREE_SPACE" -ge 50 ]
then
    if does_snapshot_exist "NcVM-installation"
    then
        check_command lvremove /dev/ubuntu-vg/NcVM-installation -y
    fi
    if ! lvcreate --size 5G --snapshot --name "NcVM-startup" /dev/ubuntu-vg/ubuntu-lv
    then
        msg_box "The creation of a snapshot failed.
If you just merged and old one, please reboot your server once more.
It should work afterwards again."
        exit 1
    fi
fi

# Check network
if network_ok
then
    print_text_in_color "$IGreen" "Online!"
else
    print_text_in_color "$ICyan" "Setting correct interface..."
    [ -z "$IFACE" ] && IFACE=$(lshw -c network | grep "logical name" | awk '{print $3; exit}')
    # Set correct interface
    cat <<-SETDHCP > "/etc/netplan/01-netcfg.yaml"
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: true
      dhcp6: true
SETDHCP
    check_command netplan apply
    print_text_in_color "$ICyan" "Checking connection..."
    sleep 1
    set_systemd_resolved_dns "$IFACE"
    if ! nslookup github.com
    then
        msg_box "The script failed to get an address from DHCP.
You must have a working network connection to run this script.

You will now be provided with the option to set a static IP manually instead."

        # Run static_ip script
	bash /var/scripts/static_ip.sh
    fi
fi

# Check network again
if network_ok
then
    print_text_in_color "$IGreen" "Online!"
elif home_sme_server
then
    msg_box "It seems like the last try failed as well using LAN ethernet.

Since the Home/SME server is equipped with a Wi-Fi module, you will now be asked to enable it to get connectivity.

Please note: It's not recommended to run a server on Wi-Fi; using an ethernet cable is always the best."
    if yesno_box_yes "Do you want to enable Wi-Fi on this server?"
    then
        install_if_not network-manager
        nmtui
    fi
        if network_ok
        then
            print_text_in_color "$IGreen" "Online!"
	else
        msg_box "Network is NOT OK. You must have a working network connection to run this script.

Please contact us for support:
https://github.com/Altoyda/Test_Ubuntu_VM/issues/

Please also post this issue on: https://github.com/Altoyda/Test_Ubuntu_VM/issues"
        exit 1
        fi
else
    msg_box "Network is NOT OK. You must have a working network connection to run this script.

Please contact us for support:
https://github.com/Altoyda/Test_Ubuntu_VM/issues/

Please also post this issue on: https://github.com/Altoyda/Test_Ubuntu_VM/issues"
    exit 1
fi

# Run the startup menu
run_script MENU startup_configuration

true
SCRIPT_NAME="Nextcloud Startup Script"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Add temporary fix if needed
if network_ok
then
    run_script STATIC temporary-fix-beginning
fi

# Import if missing and export again to import it with UUID
zpool_import_if_missing

# Is this run as a pure root user?
if is_root
then
    if [[ "$UNIXUSER" == "ncadmin" ]]
    then
        sleep 1
    else
        if [ -z "$UNIXUSER" ]
        then
            msg_box "You seem to be running this as the root user.
You must run this as a regular user with sudo permissions.

Please create a user with sudo permissions and the run this command:
sudo -u [user-with-sudo-permissions] sudo bash /var/scripts/nextcloud-startup-script.sh

We will do this for you when you hit OK."
       download_script STATIC adduser
       bash $SCRIPTS/adduser.sh "$SCRIPTS/nextcloud-startup-script.sh"
       rm $SCRIPTS/adduser.sh
       else
           msg_box "You probably see this message if the user 'ncadmin' does not exist on the system,
which could be the case if you are running directly from the scripts on Github and not the VM.

As long as the user you created have sudo permissions it's safe to continue.
This would be the case if you created a new user with the script in the previous step.

If the user you are running this script with is a user that doesn't have sudo permissions,
please abort this script and report this issue to $ISSUES."
            if yesno_box_yes "Do you want to abort this script?"
            then
                exit
            fi
        fi
    fi
fi

######## The first setup is OK to run to this point several times, but not any further ########
if [ -f "$SCRIPTS/you-can-not-run-the-startup-script-several-times" ]
then
    msg_box "The $SCRIPT_NAME script that handles this first setup \
is designed to be run once, not several times in a row.

If you feel uncertain about adding some extra features during this setup, \
then it's best to wait until after the first setup is done. You can always add all the extra features later.

[For the Ubuntu VM:]
Please delete this VM from your host and reimport it once again, then run this setup like you did the first time.

Please report any bugs you find here: $ISSUES"
    exit 1
fi

touch "$SCRIPTS/you-can-not-run-the-startup-script-several-times"

# Allow $UNIXUSER to run figlet script
chown "$UNIXUSER":"$UNIXUSER" "$SCRIPTS/nextcloud.sh"

msg_box "This script will configure your Nextcloud and activate TLS.
It will also do the following:

- Generate new SSH keys for the server
- Install selected apps and automatically configure them
- Detect and set hostname
- Upgrade your system to latest version
- Set new passwords to Linux
- Change timezone
- Add additional options if you choose them
- And more..."

msg_box "PLEASE NOTE:
[#] Please finish the whole setup. The server will reboot once done.

[#] Please read the on-screen instructions carefully, they will guide you through the setup.

[#] When complete it will delete all the *.sh, *.html, *.tar, *.zip inside:
    /root
    /home/$UNIXUSER"

msg_box "PLEASE NOTE:

The first setup is meant to be run once, and not aborted.
If you feel uncertain about the options during the setup, just choose the defaults by hitting [ENTER] at each question.

When the setup is done, the server will automatically reboot.

Please report any issues to: $ISSUES"

# Generate new SSH Keys
printf "\nGenerating new SSH keys for the server...\n"
rm -v /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server

# Server configurations
bash $SCRIPTS/server_configuration.sh

# Nextcloud configuration
bash $SCRIPTS/nextcloud_configuration.sh

# Install apps
bash $SCRIPTS/additional_apps.sh

### Change passwords
# CLI USER
UNIXUSER="$(getent group sudo | cut -d: -f4 | cut -d, -f1)"
if [[ "$UNIXUSER" != "ncadmin" ]]
then
   print_text_in_color "$ICyan" "No need to change password for CLI user '$UNIXUSER' since it's not the default user."
else
    msg_box "For better security, we will now change the password for the CLI user in Ubuntu."
    while :
    do
        UNIX_PASSWORD=$(input_box_flow "Please type in the new password for the current CLI user in Ubuntu: $UNIXUSER.")
        if [[ "$UNIX_PASSWORD" == *" "* ]]
        then
            msg_box "Please don't use spaces."
        else
            break
        fi
    done
    if check_command echo "$UNIXUSER:$UNIX_PASSWORD" | sudo chpasswd
    then
        msg_box "The new password for the current CLI user in Ubuntu ($UNIXUSER) is now set to: $UNIX_PASSWORD

This is used when you login to the Ubuntu CLI."
    fi
fi
unset UNIX_PASSWORD

# Add temporary fix if needed
if network_ok
then
    run_script STATIC temporary-fix-end
fi

# Cleanup 1
rm -f "$SCRIPTS/ip.sh"
rm -f "$SCRIPTS/instruction.sh"
rm -f "$SCRIPTS/static_ip.sh"
rm -f "$SCRIPTS/lib.sh"
rm -f "$SCRIPTS/server_configuration.sh"
rm -f "$SCRIPTS/nextcloud_configuration.sh"
rm -f "$SCRIPTS/additional_apps.sh"
rm -f "$SCRIPTS/adduser.sh"
rm -f "$NCDATA"/*.log

find /root "/home/$UNIXUSER" -type f \( -name '*.sh*' -o -name '*.html*' -o -name '*.tar*' -o -name 'results' -o -name '*.zip*' \) -delete
find "$NCPATH" -type f \( -name 'results' -o -name '*.sh*' \) -delete
sed -i "s|instruction.sh|nextcloud.sh|g" "/home/$UNIXUSER/.bash_profile"

truncate -s 0 \
    /root/.bash_history \
    "/home/$UNIXUSER/.bash_history" \
    /var/spool/mail/root \
    "/var/spool/mail/$UNIXUSER"

sed -i "s|sudo -i||g" "$UNIXUSER_PROFILE"

cat << ROOTNEWPROFILE > "$ROOT_PROFILE"
# ~/.profile: executed by Bourne-compatible login shells.

if [ "/bin/bash" ]
then
    if [ -f ~/.bashrc ]
    then
        . ~/.bashrc
    fi
fi

if [ -x /var/scripts/nextcloud-startup-script.sh ]
then
    /var/scripts/nextcloud-startup-script.sh
fi

if [ -x /var/scripts/history.sh ]
then
    /var/scripts/history.sh
fi

mesg n

ROOTNEWPROFILE

# Cleanup 2
apt-get autoremove -y
apt-get autoclean

# Remove preference for IPv4
rm -f /etc/apt/apt.conf.d/99force-ipv4
apt-get update

# Success!
msg_box "The installation process is *almost* done.

Please hit OK in all the following prompts and let the server reboot to complete the installation process."

msg_box "### PLEASE HIT OK TO REBOOT ###

Congratulations! You have successfully installed Ubuntu!

### PLEASE HIT OK TO REBOOT ###"

# Reboot
print_text_in_color "$IGreen" "Installation done, system will now reboot..."
check_command rm -f "$SCRIPTS/you-can-not-run-the-startup-script-several-times"
check_command rm -f "$SCRIPTS/nextcloud-startup-script.sh"
if ! reboot
then
    shutdown -r now
fi
