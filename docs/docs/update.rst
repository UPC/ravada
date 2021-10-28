Upgrade Ravada
==============

We try to make the upgrading procedure easy. Also if you are running
a very ancient or legacy release, fear not ! We did our best so
everything is set up with minimal user intervention.

In order to upgrade Ravada, you have to do a few steps:

Steps for a clean update
------------------------

Step 1
~~~~~~

Download the *deb* package of the new version found at the `UPC
ETSETB repository <http://infoteleco.upc.edu/img/debian/>`__.

.. prompt:: bash

    wget http://infoteleco.upc.edu/img/debian/ravada_1.1.0_ubuntu-20.04_all.deb


Step 2
~~~~~~

Install the *deb* package.

.. prompt:: bash

    sudo apt install ./ravada_1.1.0_ubuntu-20.04_all.deb


On some upgrades may be required to install some dependencies. You will see
because the packaging system will warn about it:


::

    dpkg: dependency problems prevent configuration of ravada:
      ravada depends on libdatetime-perl; however:
      Package libdatetime-perl is not installed.

If so, install those dependencies automatically running:

.. prompt:: bash

    sudo apt-get -f install


Step 3 
~~~~~~

Reconfigure systemd.

.. prompt:: bash

    sudo systemctl daemon-reload

Step 4
~~~~~~

Restart the services.

.. prompt:: bash

    sudo systemctl restart rvd_back
    sudo systemctl restart rvd_front

Step 5
~~~~~~

Check the apache configuration

If you upgrade from older releases you may have to add some lines to the apache
proxy configuration. Check the `Apache proxy guide <http://ravada.readthedocs.io/en/latest/docs/apache.html>`__.

Problems upgrading
~~~~~~~~~~~~~~~~~~

Problems may arise please take a look at our `troubleshooting
<http://ravada.readthedocs.io/en/latest/docs/troubleshooting.html>`_ guide. If everything
fails you may `contact us <https://ravada.upc.edu/#help>`_
for assistance.
