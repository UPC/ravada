Install TPM ( Trusted Platform Module )
=======================================

This is a guide to install a Trusted Platform Module emulator in Linux.
It is required to install Windows 11 virtual machines.

Ubuntu
------

Ubuntu 22.04 and 24.04
~~~~~~~~~~~~~~~~~~~~~~

Software TPM is an official package since Ubuntu 22.04.

.. prompt:: bash $

    sudo apt update
    sudo apt install swtpm-tools

Ubuntu 20.04 - Focal Fossa
~~~~~~~~~~~~~~~~~~~~~~~~~~

Add the swtpm repository to your package sources

.. prompt:: bash $

    echo "deb [trusted=yes] http://ppa.launchpad.net/stefanberger/swtpm-focal/ubuntu focal main" | sudo tee -a /etc/apt/sources.list

Update and install

If you get the following message "the public key is not available: NO_PUBKEY xxxxxxxxxxx"

.. prompt:: bash $

    sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys xxxxxxxxxxx

.. prompt:: bash $

    sudo apt update
    sudo apt install swtpm-tools


Debian
------

Please `report <https://ravada.upc.edu/#help>`_. Debian information about this topic.

Redhat and derivatives
----------------------

Packages for RPM based distributions are likely to appear and
the installation should be possible with dnf.
`Please report <https://ravada.upc.edu/#help>`_.

Troubleshooting
---------------

Virtual machine may fail to launch. It should generate a log file at
/var/log/swtpm/libvirt/qemu/

Need read/write rights on statedir
==================================

Need read/write rights on statedir /var/lib/swtpm-localca for user tss

Fix it with granting the rights it requests:

.. prompt:: bash $

    sudo chgrp tss /var/lib/swtpm-localca
    sudo chmod g+w /var/lib/swtpm-localca

References
----------

* https://getlabsdone.com/how-to-enable-tpm-and-secure-boot-on-kvm/
