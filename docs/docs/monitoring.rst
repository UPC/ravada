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

Edit this file ```/opt/netdata/etc/netdata/health_alarm_notify.conf``` and set SEND_MAIL="NO"
