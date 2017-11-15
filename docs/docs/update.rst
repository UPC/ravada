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
