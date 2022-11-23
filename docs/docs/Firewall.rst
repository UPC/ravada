Firewall
========

Ravada adds and removes rules to the iptables. If you want
to restart the firewall or change some rules you can save
the Ravada entries and restore it later.

Chains
-----

Ravada has its own chain called *RAVADA* where all the permissions
to access the virtual machines displays are stored. You can save
it, then apply your own rules, and then restore it.

Steps to reload the iptables
----------------------------

Step 1: Save the Ravada rules
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A line must be added at the begining and the end of the RAVADA rules
so at the end this file can be used in restore.

.. prompt:: #

  echo "*filter" > ravada.iptables
  iptables-save | grep RAVADA >> ravada.iptables
  echo COMMIT >> ravada.iptables

Step 2: Apply your own rules
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Change your iptables and apply your changes. Now the RAVADA rules
will have been flushed.

Step 3: Restore the Ravada rules
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Now we must restore the rules we saved in step 1.

.. prompt:: #

   iptables-restore -n < ravada.iptables

