Post Install Recomendations
===========================

Firewall
--------

The server must be able to send *DHCP* packets to its own virtual interface.

KVM should be using a virtual interface for the NAT domnains.

First we try to find out what is the new internal network:

.. prompt:: bash $,(env)... auto

    sudo ip route
    ...
    192.168.122.0/24 dev virbr0 proto kernel scope link src 192.168.122.1

So it is the interface virbr0.

Add it to your iptables configuration. This will allow some traffic between the
host and the virtual machines: DHCP, DNS and ping.

.. prompt:: bash $

   sudo iptables -A INPUT -i virbr0 -p udp -m udp --dport 67:68 -j ACCEPT
   sudo iptables -A INPUT -i virbr0 -p udp -m udp --dport 53 -j ACCEPT
   sudo iptables -A INPUT -i virbr0 -p udp -m udp --dport 5353 -j ACCEPT
   sudo iptables -A INPUT -i virbr0 -p tcp -m tcp --dport 53 -j ACCEPT
   sudo iptables -A INPUT -i virbr0 -p tcp -m tcp --dport 5353 -j ACCEPT
   sudo iptables -A INPUT -i virbr0 -p icmp -m icmp --icmp-type 8 -j ACCEPT
   sudo iptables -A OUTPUT -o virbr0 -p udp -m udp --sport 67:68 -j ACCEPT
   sudo iptables -A OUTPUT -i virbr0 -p udp -m udp --sport 53 -j ACCEPT
   sudo iptables -A OUTPUT -i virbr0 -p udp -m udp --sport 5353 -j ACCEPT
   sudo iptables -A OUTPUT -o virbr0 -p icmp -m icmp --icmp-type 8 -j ACCEPT
   sudo iptables -A OUTPUT -o virbr0 -p tcp -m tcp -s 192.168.122.1/32 -j ACCEPT

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
