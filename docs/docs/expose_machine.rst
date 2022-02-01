Exposing a Virtual Machine
==========================

By default the virtual machines are created inside a private internal
network. This allows the user to reach internet but no connections
from outside are allowed.

Some times we may want to install a server in the Virtual Machine and
grant access to it. There are many ways to expose a Virtual Machine and
allow access to it from outside. Here we describe a few: set a public IP
address, redirect with IPTables and HTTP forwarding.

Setting a public IP
-------------------

One way to expose the virtual machine is use a public IP instead the
private used by default. To do so you have to manually edit the machine
definition before creating the base. Change the network settings to
`bridge <http://ravada.readthedocs.io/en/latest/docs/network_bridge.html>`__.

This setting gives the more exposure to the virtual machine, so firewalls
and other security measures must be configured.

IPTables redirection
--------------------

You can redirect a port from the host or a virtual machine acting as
gateway to the internal address of the machine you want to expose.

This technique restricts which ports from the internal machine are
exposed from outside.


HTTP Forwarding
---------------

HTTP forwarding can be configured in a web server in the host to access internal web
services from outside.

Expose Ports
------------

Ports from the virtual machine can be exposed to outside with this new feature
introduced in release 0.5.
