Install TPM ( Trusted Platform Module )
=======================================

This is a guide to install a Trusted Platform Module emulator in Linux.
It is required to install Windows 11 virtual machines.

Ubuntu
------

Ubuntu 20.04 - Focal Fossa
~~~~~~~~~~~~~~~~~~~~~~~~~~

Add the swtpm repository to your package sources

.. prompt:: bash $

    echo "deb [trusted=yes] http://ppa.launchpad.net/stefanberger/swtpm-focal/ubuntu focal main" | sudo tee -a /etc/apt/sources.list

Update and install

.. prompt:: bash $
    sudo apt update
    sudo apt install swtpm-tools

Ubuntu 22.04
~~~~~~~~~~~~

Software TPM is expected to ship with Ubuntu 22.04.

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

References
----------

* https://getlabsdone.com/how-to-enable-tpm-and-secure-boot-on-kvm/
