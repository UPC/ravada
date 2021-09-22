How to Install a LDAP Server
============================

Install 389-ds
----------------------------

.. prompt:: bash

    sudo apt-get install 389-ds-base

Configure directory server
--------------------------

Release 1.3 [old]
~~~~~~~~~~~~~~~~~

This is the configuration tool for older releases of 389 directory server.
If there is no setup-ds tool in your system you probably have the new release,
skip to Release 1.4 instruction bellow.

.. prompt:: bash

    sudo setup-ds

When requested the server name, answer with the full qualified
domain name of the host: hostname.domainname.
In the next step you must supply the domain name as base for the
configuration. So if your domain name is "foobar.com", the base
will be "dc=foobar,dc=com".

Release 1.4 [new]
~~~~~~~~~~~~~~~~~

From release 1.4 we provide an example configuration file for
creating the new directory instance.

.. literalinclude:: ds389.conf

After you set a password and correct suffix create a LDAP instance with *dscreate*:

.. prompt:: bash

    sudo dscreate from-file ds389.conf

Enable and Start the service
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. prompt:: bash

   sudo systemctl start dirsrv@localhost
   sudo systemctl enable dirsrv@localhost

Add a LDAP section in the config file
-------------------------------------

The config file usually is /etc/ravada.conf. Add this configuration:

::

    ldap:
        admin_group: test.admin.group
        admin_user:
            dn: cn=Directory Manager
            password: 12345678
        base: 'dc=example,dc=com'

Then restart the services:

.. prompt:: bash

    sudo systemctl restart rvd_back
    sudo systemctl restart rvd_front

Insert one test user
--------------------

The ravada backend script allows creating users in the LDAP

.. prompt:: bash

    sudo rvd_back --add-user-ldap jimmy.mcnulty

There are more commands to easily manage LDAP entries. Check the
`LDAP section from the CLI  <http://ravada.readthedocs.io/en/latest/docs/CLI.html>`_
documentation.

