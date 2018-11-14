Post Install Recomendations
===========================

Firewall
--------

The server must be able to send *DHCP* packets to its own virtual interface.

KVM should be using a virtual interface for the NAT domnains. Look what is the address range and add it to your *iptables* configuration.

First we try to find out what is the new internal network:

.. prompt:: bash $,(env)... auto

    sudo route -n
    ...
    192.168.122.0   0.0.0.0         255.255.255.0   U     0      0        0 virbr0

So it is 192.168.122.0 , netmask 24. Add it to your iptables configuration:

.. prompt:: bash $

    sudo iptables -A INPUT -s 192.168.122.0/24 -p udp --dport 67:68 --sport 67:68 -j ACCEPT

To confirm that the configuration was updated, check it with:

.. prompt:: bash $

    sudo iptables -S


Configuration
-------------

The frontend has a secret passphrase that should be changed. Cookies and
user session rely on this. You can have many passphrases that get
rotated to improve security even more.

Change the file /etc/rvd\_front.conf line *secrets* like this:

::

    , secrets => ['my secret 1', 'my secret 2' ]
