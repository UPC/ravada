Post Install Recomendations
===========================

Firewall
--------

The server must be able to send *DHCP* packets to its own virtual interface.

KVM should be using a virtual interface for the NAT domnains. Look what is the address range and add it to your *iptables* configuration.

First we try to find out what is the new internal network:

::

    $  sudo route -n
    ...
    192.168.122.0   0.0.0.0         255.255.255.0   U     0      0        0 virbr0

So it is 192.168.122.0 , netmask 24. Add it to your iptables configuration:

::

    sudo iptables -A INPUT -s 192.168.122.0/24 -p udp --dport 67:68 --sport 67:68 -j ACCEPT

To confirm that the configuration was updated, check it with:

::

    sudo iptables -S


Configuration
-------------

The frontend has a secret passphrase that should be changed. Cookies and
user session rely on this. You can have many passphrases that get
rotated to improve security even more.

Change the file /etc/rvd\_front.conf line *secrets* like this:

::

    , secrets => ['my secret 1', 'my secret 2' ]


Host Qemu Agent Prerequisits
----------------------------

Execute the following commands on your host:

::
	$ sudo mkdir -p /var/lib/libvirt/qemu/channel/target
	$ sudo chown -R libvirt-qemu:kvm /var/lib/libvirt/qemu/channel

And edit the file /etc/apparmor.d/abstractions/libvirt-qemu adding the following in the end:

::
	/var/lib/libvirt/qemu/channel/target/* rw,


Guest Agent Installation
------------------------

This installation must be done in your guest VM if you want to keep the correct time after hibernate.

Ubuntu and Debian
~~~~~~~~~~~~~~~~~

::
	$ sudo apt install qemu-guest-agent

Fedora
~~~~~~

::
	$ dnf install qemu-guest-agent

RedHat and CentOS
~~~~~~~~~~~~~~~~~

::
	$ yum install qemu-guest-agent

Windows
~~~~~~~

Follow the instructions provided by `Linux KVM <https://www.linux-kvm.org/page/WindowsGuestDrivers/Download_Drivers>`_
