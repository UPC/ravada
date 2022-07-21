Automatic Daily Operations
==========================

It is possible to configure automatic daily cleaning operations.
You may want to keep the system from having idle virtual
machines. Using the *Ravada CLI* you can stop or hibernate machines
at a given time.

Cron
----

We use the *cron* utility to execute operations at a given time.
If you are not familiar with this consult the system documentation
typing `man cron` or any other online manual.

To configure the cron entries type this from the host console:

.. prompt:: bash $

   sudo crontab -e

Usage
-----

The most usual operation is to hibernate or shutdown all the inactive
virtual machines at night. All the users that have an active connection
will not be affected.

Also, any virtual machine marked as *auto start* will be kept running.

Examples
--------

Hibernate disconnected
~~~~~~~~~~~~~~~~~~~~~~

This cron entry will hibernate all virtual machines that have disconnected
the remote viewer. This will be executed at 4 AM in the morning each day.

::

  00 04 * * * /usr/sbin/rvd_back --hibernate --disconnected

Hibernate active
~~~~~~~~~~~~~~~~

That will hibernate any active virtual machine. This will be executed
at 4 AM in the morning in weekdays.

::

  00 04 * * mon-fri /usr/sbin/rvd_back --hibernate --active

Shutdown or Hibernate
~~~~~~~~~~~~~~~~~~~~~

You can use shutdown in the previous examples instead of hibernate.
The main difference is hibernated machines must dump all the memory
to disk and use large amounts of space in the server.

Other usage
-----------

The commands that can be issued are:

- shutdown
- hibernate

The modifiers to list virtual machines are:

- active
- disconnected
- all
