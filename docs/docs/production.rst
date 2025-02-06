Running Ravada in production
============================

Ravada has two daemons that must run on the production server:

-  rvd\_back : must run as root and manages the virtual machines
-  rvd\_front : is the web frontend that sends requests to the backend


System services
---------------

Configuration for boot start
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

There are two services to start and stop the two ravada daemons:

After install or upgrade you may have to refresh the systemd service
units:

.. prompt:: bash $

    sudo systemctl daemon-reload

Check the services are enabled to run at startup

.. prompt:: bash $

    sudo systemctl enable rvd_back
    sudo systemctl enable rvd_front

Start
~~~~~

.. prompt:: bash $

    sudo systemctl start rvd_back
    sudo systemctl start rvd_front

Status
~~~~~~
You should check if the daemons started right the very first time with the status command. See troubleshooting frequently problems if it failed to start.

.. prompt:: bash $
    
    sudo systemctl status rvd_back
    sudo systemctl status rvd_front

Stop
~~~~

.. prompt:: bash $

    sudo systemctl stop rvd_back
    sudo systemctl stop rvd_front


Qemu
----

Ravada uses Qemu to manage the virtual machines. We encourage change
this settings so hibernated machines are stored compressed. This way
you will save a large amount of disk space on your server.

Edit the file /etc/libvirt/qemu.conf and uncomment and
change this line:

::

    save_image_format = "bzip2"

You have to restart libvirt after changing this file:

.. prompt:: bash $

    sudo systemctl restart libvirtd

SPICE-TLS
---------

The default visualization protocol, SPICE, can be hardened
`installing a TLS certificate <spice_tls.html>`__.

Apache
------

You can reach the Ravada frontend heading to
http://your.server.ip:8081/. It is advised to run an Apache server or
similar before the frontend.

In order to make ravada use apache, you must follow the steps explained
on `here <apache.html>`__.


Firewall
--------

Ravada uses ``iptables`` to restrict the access to the virtual machines.
These iptables rules grants acess to the admin workstation to all the
domains and disables the access to everyone else. When the users access
through the web broker they are allowed to the port of their virtual
machines.

In this example we restrict the access to the virtual machines
display. The first line is optional but handy if we want to allow access
to an administrator workstation for debugging purposes.

::

    -A INPUT -p tcp -m tcp -s ip.of.admin.workstation --dport 5900:7000 -j ACCEPT
    -A INPUT -p tcp -m tcp --dport 5900:7000 -j DROP


Virtual machines display ports start on 5900. If you want to override
this configuration, because some other firewall is filtering this port,
you can do it this way:

Edit /etc/libvirt/qemu.conf, uncomment and change remote_display_port_min.

::

    # Override the port for creating both VNC and SPICE sessions (min).
    # This defaults to 5900 and increases for consecutive sessions
    # or when ports are occupied, until it hits the maximum.
    #
    remote_display_port_min = 5910
    #remote_display_port_max = 65535

Then restart libvirtd:

.. prompt:: bash $

    sudo systemctl restart libvirtd

The next virtual machine that starts will be shown from this port (5910).
This won't change machines already started unless you shut them down and
start them again.

Help
----

Struggling with the installation procedure ? We tried to make it easy but
let us know if you need `assistance <http://ravada.upc.edu/#help>`__.

There is also a `troubleshooting <troubleshooting.html>`__ page with common problems that
admins may face.

If you do not know how to create a virtual machine, please read `creating virtual machines <How_Create_Virtual_Machine.html>`__.
