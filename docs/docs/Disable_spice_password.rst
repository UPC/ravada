Disable Spice Password
======================

When the users start a virtual machine, a password is defined for the spice connection.
This can be disabled for a given network.

Unfortunately this settings must be configured directly through SQL commands. There is
still no GUI section for this.

Define the network
------------------

Define a network with no password setting the requires_password field to 0:

::

    # mysql -u root -p ravada
    mysql> insert into networks (name, address, requires_password) values ('classroom','10.0.68.0/24', 0);

Applying settings
-----------------

This settings applies on starting a new virtual machine. So running virtual machines
will keep the former settings. Shutting them down and up will trigger the new
configuration.

Default setting
---------------

Any other network requires password as defined by the '0.0.0.0/0' network setting.

Why is that ?
-------------

Ravada opens SPICE connections and manages iptables to make sure no one can
connect to another user's virtual machine. This is also enforced through the
password setting. Please consider disabling it only in controlled, seat-unique ip
environments.
