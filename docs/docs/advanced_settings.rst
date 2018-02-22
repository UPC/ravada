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
