Upgrade Ravada 
==============

In order to upgrade Ravada, you have to do a few steps:

Steps for a clean update
------------------------

Step 1 
~~~~~~

Download the *deb* package of the new version found at the `UPC
ETSETB repository <http://infoteleco.upc.edu/img/debian/>`__.

Step 2 
~~~~~~

Install the *deb* package.

::

    $ sudo dpkg -i <deb file>

On some upgrades may be required to install some dependencies. You will see
because the packaging system will warn about it:


::

    dpkg: dependency problems prevent configuration of ravada:
      ravada depends on libdatetime-perl; however:
      Package libdatetime-perl is not installed.

If so, install those dependencies automatically running:

::

    $ sudo apt-get -f install


Step 3 
~~~~~~

Reconfigurate the systemd.

::

    $ sudo systemctl daemon-reload

Step 4
~~~~~~

Restart the services.

::

    $ sudo systemctl restart rvd_back
    $ sudo systemctl restart rvd_front
