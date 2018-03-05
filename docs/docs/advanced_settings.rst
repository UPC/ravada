Ravada advanced settings
========================

Display IP
-----------

On a server with 2 IPs, the configuration file allows the administrator define
which one is used for the display. Add the entry *display_ip* to /etc/ravada.conf
with the public address of the server.

::

    display_ip: public.display.ip

NAT
---

The Ravada server can be behind a NAT environment.

      RVD    _______________ NAT ________________ client
      Server 1.1.1.1             2.2.2.2

Configure this option in /etc/ravada.conf

::

    display_ip: 1.1.1.1
    nat_ip: 2.2.2.2

Auto Start
----------

Virtual machines can be configured to auto-start on host boot. This feature
is available from release 0.2.15
You must enable the auto-start column at the frontend configuration file.

::

    {
        admin => {
            autostart => 1
        }
    };

Reboot the frontend and auto-start can be setted at the machine list
page in admin.

