========
log file
========

Frontend log file
=================

You can set a custom log file for the frontend process in the configuration.

Edit the configuration file: */etc/rvd_front.conf* and add or change next section:

.. code-block:: perl

  ,log => {
       log => 1
       ,file => '/var/log/ravada/rvd_front.log'
       ,level => 'debug'
  }


Create the log directory and grant the Ravada user permissions to write to it:

.. code-block:: bash

    root@server:~# mkdir /var/log/ravada
    root@server:~# chown ravada /var/log/ravada

Now restart the Ravada front process and check the log file is created.

.. code-block:: bash

    root@server:~# systemctl restart rvd_front

Security Logs
=============

Security access will appear in the log file similar as an Apache log entry::

    127.0.0.1 - [2020/09/01:12:20:32 +0200] GET /


Login failures show with an *access denied* message-
Set the log level to *error* if you only want these::

     Access denied to fff from 127.0.0.1


A fail2ban catch can be created from these. Contributions welcome.

