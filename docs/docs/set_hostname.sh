#!/bin/sh
hostname=$(/usr/sbin/dmidecode | grep hostname | awk '{ print $4}' | sed -e 's/_/-/g')
if [ ! -z "$hostname" ]; then
    old_hostname=$(hostname)
    if [ $hostname != "$old_hostname" ]; then
        /bin/hostname $hostname
        /bin/hostname >/etc/hostname
        umount -t nfs,nfs4 -a
        rm -f /etc/machine-id /var/lib/dbus/machine-id
        systemd-machine-id-setup
        mount -t nfs,nfs4 -a
        echo "Found hostname $hostname in dmidecode " >>/var/log/set_hostname.log
    fi
else
    echo "Not found hostname in dmidecode " >>/var/log/set_hostname.log
    /usr/sbin/dmidecode >>/var/log/set_hostname.log
fi
