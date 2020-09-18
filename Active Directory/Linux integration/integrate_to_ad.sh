#!/usr/bin/env bash
# integrate_to_ad.sh

# this script is intended to partially automate the integration of a Linux host to Active Directory by installing necessary files
# and installing configuration file for Company AD domain

# this was designed for Debian 10
# documentation is available here : https://docs.google.com/document/d/1UhwJA7tihbZdpPUd1gfxI_qC67vTt0SAWuuntQoukc0


DEBIAN_VERSION_FILEPATH="/etc/debian_version"
# name of the config files used in the script, mandatory for script use
NECESSARY_CONFIG_FILES=(
    "common-session"
    "nsswitch.conf"
    "realmd.conf"
    "smb.conf"
    "timesyncd.conf"
)
DEPENDENCIES=(
    "packagekit"
    "realmd"
    "libnss-winbind"
    "libpam-winbind"
    "openssh-server"
    "sudo"
)
DOMAINNAME="domain.com"

# making sure the distro is debian to avoid creating issue
if ! [ -f "$DEBIAN_VERSION_FILEPATH" ] ; then
    echo -e "This is not a Debian distro. The script will not work there. Please proceed manually for AD integration\nExiting\n"
    exit 1
fi

# checking all files are here, exiting if not
for config_file in ${NECESSARY_CONFIG_FILES[@]} ; do
    if ! [ -f "./$config_file" ] ; then
    echo -e "At least one of the neccessary config files is missing. Please copy the whole folder from the source (see procedure) to use the script.\nExiting\n"
    fi
done


echo -e "\n=============================================================================================\n"
echo -e "Dependencies installation with apt, will try all, no confirmation, non interactive"
echo -e "\n=============================================================================================\n"
DEBIAN_FRONTEND=noninteractive apt install -y ${DEPENDENCIES[@]}

# prompt for username for joining domain
echo -e "\nPlease input an AD user with AD join (computer) privilege. The format must be user where user can have spaces. Do not quote. Do not use the domain name."
read ad_join_user

# promt for server tier, will be used to add a line to sshd_config to allow those tier users to connect via SSH
server_tier=9
while [[ ($server_tier !=  "0") && ($server_tier !=  "1") ]] ; do
    echo -e "\nWhat is this server's Tier (for login restriction purposes) (0, 1) :"
    read server_tier
done

# modify SSH config file to allow tier users to connect
if [[ $server_tier == "0" ]]; then
    echo "Modifying provided sshd_config file to allow Tier $server_tier users to connect via SSH"
    sed -i 's/AllowGroups \"domain\\role_tier 1 admin\"/AllowGroups \"domain\\role_tier 0 admin\"/' ./sshd_config # sed to handle string operations on config file
fi


echo "Copying realmd config file to /etc"
cp -f ./realmd.conf /etc/realmd.conf

# error handling loop for realmd
while true ; do
    echo "realm join $DOMAINNAME -U $ad_join_user"
    realm join "$DOMAINNAME" -U "$ad_join_user" --verbose
    if [ $? -ne 0 ] ; then
        echo -e "\nThe user you inputed was either incorrect or does not have permission to perform AD join for a computer. Please input a correct user, with the proper format : "
        read ad_join_user
    else
        break
    fi
done

# changing keytab permission to avoid a bug with winbind
echo "Changing permissions to 640 for the kerberos keytab file"
chmod 640 /etc/krb5.keytab


# config file copy to /etc 
# MODIFYING PAM CONFIG IS A SENSITIVE OPERATION
echo "Copying all config files (nsswitch.conf, common-session, smb.conf, sshd_config) to their respective destination (/etc/...)"
cp -f ./nsswitch.conf /etc/nsswitch.conf
cp -f ./common-session /etc/pam.d/common-session
cp -f ./smb.conf /etc/samba/smb.conf
cp -f ./sshd_config /etc/ssh/sshd_config
cp -f ./timesyncd.conf /etc/systemd/timesyncd.conf


# loop handling sudoers group added to custom sudoers file
while true; do
    # get input for groups
    echo "Please input a group you wish to add as sudoers (to stop group input, input q). The group must be in the form \"DOMAIN\group name\"Do not escape characters :"
    read -r sudoers_group

    if [ "$sudoers_group" == "q" ]; then
        break
    fi

    group_entry=$(getent group "$sudoers_group")

    # handles incorrect group when getent didn't manage to get a corresponding group for user entry (in that case, it will return error code 2)
    if [ $? -ne 0 ]; then
        echo "The group you entered ($sudoers_group) does not exist or your input is incorrect. Please try again"
        continue
    fi

    echo "Creating sudoers entry"
    group_name=$(echo "$group_entry" | cut -d':' -f1 |  sed -e 's/\\/\\\\/g' -e 's/ /\\ /g') # escaping characters in group name to comply to sudoers file specification
    sudoers_entry=$(echo '%'$group_name' ALL=(root)  ALL,    !/bin/su') # creating sudoers entry, specific quoting to prevent the ! to be interpreted by bash

    # appending to sudoers custom file via visudo and tee
    echo -e "Appending the following sudoers entry\n$sudoers_entry\n to /etc/sudoers.d/domain_sudoers"
    echo $sudoers_entry | sudo EDITOR='tee -a' visudo --file=/etc/sudoers.d/domain_sudoers

done



exit

