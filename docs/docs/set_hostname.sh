#!/bin/sh
date >> /var/log/set_hostname.log
hostname=`/usr/sbin/dmidecode | grep hostname | awk '{ print $4}'`
if [ ! -z "$hostname" ]; then
	/bin/hostname $hostname
	/bin/hostname > /etc/hostname
	echo "Found hostname $hostname in dmidecode " >> /var/log/set_hostname.log
else
	echo "Not found hostname in dmidecode " >> /var/log/set_hostname.log
	/usr/sbin/dmidecode >> /var/log/set_hostname.log
fi
