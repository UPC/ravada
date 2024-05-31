Upgrade Ravada with Rollback
============================

This is the ugprade procedure when you want to keep everything
just in case you wanted to roll back to the previous version.

Step 1: Shutdown the services
---------------------

.. prompt:: bash

   sudo systemctl stop rvd_back
   sudo systemctl stop rvd_front


Step 2: Keep the package and data
--------------------------------------

Step 2.1: Keep the package file
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you installed the package it must be in the server somewhere.
It is a *deb* file called ravada_x.y.z_system-version_all.deb.

When in doubt, we keep most of the released packages in the
`UPC ETSETB repository <http://infoteleco.upc.edu/img/debian/>`__.

Step 2.2: Save Current Data
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Check the database user and password from the config file /etc/ravada.conf.
Then dump the database:

.. prompt:: bash

    mysqldump -u rvd_user -p ravada > ravada.sql


Step 4: Upgrade
---------------

Step 4.1: Fetch the new package
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Download the *deb* package of the new version found at the `UPC
ETSETB repository <http://infoteleco.upc.edu/img/debian/>`__.

.. prompt:: bash

    wget http://infoteleco.upc.edu/img/debian/ravada_2.2.2_ubuntu-20.04_all.deb


Step 4.2: Install
~~~~~~~~~~~~~~~~~

Install the *deb* package.

.. prompt:: bash

    sudo apt install ./ravada_2.2.2_ubuntu-20.04_all.deb


On some upgrades may be required to install some dependencies. You will see
because the packaging system will warn about it:


::

    dpkg: dependency problems prevent configuration of ravada:
      ravada depends on libdatetime-perl; however:
      Package libdatetime-perl is not installed.

If so, install those dependencies automatically running:

.. prompt:: bash

    sudo apt-get -f install


Step 4.3: systemd
~~~~~~~~~~~~~~~~~

Reconfigure systemd.

.. prompt:: bash

    sudo systemctl daemon-reload

Step 4.4: apache config
~~~~~~~~~~~~~~~~~~~~~~~

Check the apache configuration

If you upgrade from older releases you may have to add some lines to the apache
proxy configuration. Check the `Apache proxy guide <http://ravada.readthedocs.io/en/latest/docs/apache.html>`__.

Step 4.5: start
~~~~~~~~~~~~~~~

Restart the services.

.. prompt:: bash

    sudo systemctl restart rvd_back
    sudo systemctl restart rvd_front

If you are upgrading from a very old release, it may take a while to proceed.
You may check the log file for information opening another terminal:

.. prompt:: bash

   sudo tail -f /var/log/syslog


Check the daemons are running:

.. prompt:: bash

    sudo systemctl status rvd_back
    sudo systemctl status rvd_front

Finally connect to your server and try to run and clone a virtual machine.

Rollback
--------

If something failed and you wanted to rollback follow the
 `Rollback Ravada version guide <http://ravada.readthedocs.io/en/latest/docs/update_rollback.html>`_
