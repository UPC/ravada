Server Monitoring 
=================

In order to support Ravada server monitoring, you have to do a few steps:


Install my-netdata.io
---------------------

Follow this steps from `my-netdata.io <https://github.com/firehol/netdata/wiki/Installation>`_ 

or 

Linux 64bit, pre-built static binary installation
for any Linux distro, any kernel version - for Intel/AMD 64bit hosts.
 
::

    # bash <(curl -Ss https://my-netdata.io/kickstart-static64.sh)


Disable mail alarms
-------------------

Edit the file ``/opt/netdata/etc/netdata/health_alarm_notify.conf`` and set SEND_MAIL="NO"

Graphite backend
----------------

Edit the file ``/opt/netdata/etc/netdata/netdata.conf``:

::

 [backend]
     host tags =
     enabled = yes
     data source = average
     type = graphite
     destination = <GraphiteServer>
     prefix = netdata
     hostname = <hostname>
     update every = 10
     buffer on failures = 10
     timeout ms = 20000
     send names instead of ids = yes
     send charts matching = *
     send hosts matching = localhost *
