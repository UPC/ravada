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

Add ``/etc/pki/libvirt-spice/** r,`` in ``/etc/apparmor.d/abstractions/libvirt-qemu`` 

::

    # access PKI infrastructure
    /etc/pki/libvirt-vnc/** r,
    /etc/pki/libvirt-spice/** r,

.. note:: Remmember restart the services: ``systemctl restart apparmor.service`` & ``systemctl restart libvirtd.service``

Create self signed certificate
------------------------------

Perform the following script, to generate the cert files for ssl , and then copy ``*.pem`` file into ``/etc/pkil/libvirt-spice`` directory: (`source <http://fedoraproject.org/w/index.php?title=QA:Testcase_Virtualization_Manually_set_spice_listening_port_with_TLS_port_set>`_)

::
    
    #!/bin/bash

    SERVER_KEY=server-key.pem
    
    # creating a key for our ca
    if [ ! -e ca-key.pem ]; then
        openssl genrsa -des3 -out ca-key.pem 1024
    fi
    # creating a ca
    if [ ! -e ca-cert.pem ]; then
        openssl req -new -x509 -days 1095 -key ca-key.pem -out ca-cert.pem  -subj "/C=IL/L=Raanana/O=Red Hat/CN=my CA"
    fi
    # create server key
    if [ ! -e $SERVER_KEY ]; then
        openssl genrsa -out $SERVER_KEY 1024
    fi
    # create a certificate signing request (csr)
    if [ ! -e server-key.csr ]; then
        openssl req -new -key $SERVER_KEY -out server-key.csr -subj "/C=IL/L=Raanana/O=Red Hat/CN=my server"
    fi
    # signing our server certificate with this ca
    if [ ! -e server-cert.pem ]; then
        openssl x509 -req -days 1095 -in server-key.csr -CA ca-cert.pem -CAkey ca-key.pem -set_serial 01 -out server-cert.pem
    fi
    
    # now create a key that doesn't require a passphrase
    openssl rsa -in $SERVER_KEY -out $SERVER_KEY.insecure
    mv $SERVER_KEY $SERVER_KEY.secure
    mv $SERVER_KEY.insecure $SERVER_KEY
    
    # show the results (no other effect)
    openssl rsa -noout -text -in $SERVER_KEY
    openssl rsa -noout -text -in ca-key.pem
    openssl req -noout -text -in server-key.csr
    openssl x509 -noout -text -in server-cert.pem
    openssl x509 -noout -text -in ca-cert.pem

    # copy *.pem file to /etc/pki/libvirt-spice
    if [[ -d "/etc/pki/libvirt-spice" ]] 
    then    
        cp ./*.pem /etc/pki/libvirt-spice
    else
        mkdir /etc/pki/libvirt-spice
        cp ./*.pem /etc/pki/libvirt-spice
    fi

    # echo --host-subject
    echo "your --host-subject is" \" `openssl x509 -noout -text -in server-cert.pem | grep Subject: | cut -f 10- -d " "` \"
 
.. warning::
    Whatever method you use to generate the certificate and key files, the Common Name value used for the server and client certificates/keys must each differ from the Common Name value used for the CA certificate. Otherwise, the certificate and key files will not work for servers compiled using OpenSSL.

Disable Spice Password
----------------------
	 Removing SPICE password for all the networks, link to https://ravada.readthedocs.io/en/latest/docs/Disable_spice_password.html
