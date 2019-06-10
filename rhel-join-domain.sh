#!/usr/bin/env bash

oudcsuffix="DC=AWSCLOUD,DC=CMS,DC=LOCAL"
sshusername='ec2-user'
domainname='awscloud.cms.local'
domaincontrollerhost=$domainname


domainjoinerusername=$1


if [[ -z $domainjoinerusername ]]
then
    echo "Prerequisites:"
    echo "The script requires RHEL7 or RHEL6."
    echo "Usage:"
    echo "sudo ./rhel-join-domain.sh <domain joiner account> [hostname] [ou] [ssh users groups] [sudo users group]"
    echo "* domain joiner account - username of a poweruser capable of joining instances to domains"
    echo "* hostname - desired hostname for the target instance"
    echo "* ou - AD OU to which the instance should be added"
    echo "* ssh users group - name of a group containing ssh-only users"
    echo "* sudo users group - name of a group containing sudo users"
    echo "Example: sudo ./rhel-join-domain.sh R1ZL"
    echo "Example: sudo ./rhel-join-domain.sh R1ZL mktapp-dev-01 'OU=Test,OU=Servers,OU=TEST,OU=FFM,\
OU=External,OU=CMS,DC=AWSCLOUD,DC=CMS,DC=LOCAL' 'TEST Dev Users' 'TEST Dev Admins'"
    exit 1
fi

#check stdin for the password
read -t 1 domainjoinerpassword
if [[ -z $domainjoinerpassword ]]
then
    read -s -p "Enter domain account password:" domainjoinerpassword
fi

yum install -y openldap-clients

echo -e "\n"
echo "Validating credentials and querying AD. May take several minutes."

availableapplications=$(ldapsearch -h $domaincontrollerhost -x -D "$domainjoinerusername@$domainname" -w $domainjoinerpassword\
 -b "ou=FFM,ou=External,ou=CMS,$oudcsuffix" -s one -LLL "(objectClass=organizationalUnit)" -o nettimeout=5 dn|awk -F'OU=' '{print $2}'|tr -d '\n')
if [[ -z $availableapplications ]]
then
    exit 1
fi

hostname=$2
ou=$3
usersgroup=$4
adminsgroup=$5

if [[ -z $ou ]]
then
    read -p "Was the instance deployed as part of a Marketplace application? (Y/n)" ismarketplace
    if [[ -z $ismarketplace ]] || [[ $ismarketplace == "Y" ]] || [[ $ismarketplace == "y" ]]
    then
        echo "Enter application name."
        echo -e "Available applications:\n$availableapplications"|tr ',' '\n'
        echo "Contact NOC if desired application is missing."
        read -p "Enter application name:" applicationname
        if [[ $availableapplications != *$applicationname* ]]
        then
            echo "ERROR: Unknown application. Make sure that application AD OU structure has been created."
            exit 1
        fi
        availableenvironments="dev, test, impl, prod"
        read -p "Enter application environment ($availableenvironments):" applicationenvironment
                if [[ $availableenvironments != *$applicationenvironment* ]]
        then
            echo "ERROR: Unknown environment"
            exit 1
        fi
        ou="OU=$applicationenvironment,OU=Servers,OU=$applicationname,OU=FFM,OU=External,OU=CMS,$oudcsuffix"
        usersgroup="$applicationname $applicationenvironment Users"
        adminsgroup="$applicationname $applicationenvironment Admins"
    else
        read -p "Enter target ou for the instance. If unsure, contact NOC.:" ou
    fi
fi

if [[ -z $usersgroup ]]
then
    read -p "Enter name of a group containing ssh-only users:" usersgroup
fi

if [[ -z $adminsgroup ]]
then
    read -p "Enter name of a group containing sudo users:" adminsgroup
fi

if [[ -z $hostname ]]
then
    read -p "Enter desired host name for the instance:" hostname
fi

rhelrelease=$(cat /etc/redhat-release)
echo $rhelrelease
rhelversion=$(echo $rhelrelease|sed 's/[^0-9.]//g')
rhelmajor=${rhelversion:0:1}
if [ $rhelmajor -eq "6" ]
then
	echo "Detected RHEL6"
	#install required packages
    yum install -y adcli krb5-workstation oddjob oddjob-mkhomedir

    #Configure hostname
    shorthostname=${hostname:0:15}
    echo "preserve_hostname: true" >> /etc/cloud/cloud.cfg
    sed -i "s|HOSTNAME=.*|HOSTNAME=${shorthostname}.${domainname}|" /etc/sysconfig/network
    hostname ${shorthostname}.${domainname}
    sleep 10
	./rhel6-scripts/rhel6-joindomain.sh "$hostname" "$ou" "$usersgroup" "$adminsgroup" "$domainname" "$domainjoinerusername" "$domainjoinerpassword"
elif [ $rhelmajor -eq "7" ]
then
	echo "Detected RHEL7"
	#install required packages
    yum install -y realmd
    yum install -y oddjob oddjob-mkhomedir sssd samba-common-tools
    hostnamectl set-hostname --static "$hostname.$domainname"
    echo "preserve_hostname: true" >> /etc/cloud/cloud.cfg
    if realm --install=/ discover $domainname;
    then
        echo "realmd successfully discovered the domain."
    else
        echo "realmd failed to discover the domain. Reboot the instance and restart the script. If the error persists check instance security groups and shared services connectivity."
        exit 1
    fi
    sleep 10
    ./rhel7-scripts/rhel7-joindomain.sh "$hostname" "$ou" "$usersgroup" "$adminsgroup" "$domainname" "$domainjoinerusername" "$domainjoinerpassword"
else
	echo "Unsupported RHEL major version"
	exit 255
fi