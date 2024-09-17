Hardening Spice security with TLS
=================================

TLS support allows to encrypt all/some of the channels Spice uses for its communication. A separate port is used for the encrypted channels.

Change libvirtd configuration
-----------------------------

The certificate must be specified in libvirtd configuration file in /etc/libvirt/qemu.conf 

Uncomment the lines: *spice_listen="0.0.0.0"*, *spice_tls=1*  and *spice_tls_x509_cert_dir="/etc/pki/libvirt-spice"*

::

    # SPICE is configured to listen on 127.0.0.1 by default.
    # To make it listen on all public interfaces, uncomment
    # this next option.
    #
    # NB, strong recommendation to enable TLS + x509 certificate
    # verification when allowing public access
    #
    spice_listen = "0.0.0.0"
    # Enable use of TLS encryption on the SPICE server.
    #
    # It is necessary to setup CA and issue a server certificate
    # before enabling this.
    #
    spice_tls = 1
    # Use of TLS requires that x509 certificates be issued. The
    # default it to keep them in /etc/pki/libvirt-spice. This directory
    # must contain
    #
    #  ca-cert.pem - the CA master certificate
    #  server-cert.pem - the server certificate signed with ca-cert.pem
    #  server-key.pem  - the server private key
    #
    # This option allows the certificate directory to be changed.
    #
    spice_tls_x509_cert_dir = "/etc/pki/libvirt-spice"

Add path in Apparmor 
--------------------

You may want to add this path to Apparmor, in some Linux distributions it is not
necessary, ie Ubuntu from 18.04.

Add ``/etc/pki/libvirt-spice/** r,`` in ``/etc/apparmor.d/abstractions/libvirt-qemu`` 

::

    # access PKI infrastructure
    /etc/pki/libvirt-vnc/** r,
    /etc/pki/libvirt-spice/** r,

.. note:: Remmember restart the services: ``systemctl restart apparmor.service`` & ``systemctl restart libvirtd.service``

Create self signed certificate
------------------------------

Download and modify your servername in `v3.ext <https://raw.githubusercontent.com/UPC/ravada/gh-pages/docs/docs/v3.ext>`__ file, then run the
`create_cert.sh <https://raw.githubusercontent.com/UPC/ravada/gh-pages/docs/docs/create_cert.sh>`__ script.

.. include:: create_cert.sh
   :code: bash

.. warning::
    Whatever method you use to generate the certificate and key files, the Common Name value used for the server and client certificates/keys must each differ from the Common Name value used for the CA certificate. Otherwise, the certificate and key files will not work for servers compiled using OpenSSL.

Disable Spice Password
----------------------

More information about `removing SPICE password <https://ravada.readthedocs.io/en/latest/docs/Disable_spice_password.html>`_ for all the networks. 

Debug and check TLS connection
------------------------------

For debug errors you can check connection to YOUR_SERVERNAME and your SPICE port from console.

::

    openssl s_client -connect YOUR_SERVERNAME:SPICE_PORT -tls1_3
