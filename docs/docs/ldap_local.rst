How to Install a local LDAP
===========================

Install and configure 389-ds
----------------------------

.. prompt:: bash

    sudo apt-get install 389-ds-base
    sudo setup-ds

When requested the server name, answer with the full qualified
domain name of the host: hostname.domainname.
In the next step you must supply the domain name as base for the
configuration. So if your domain name is "foobar.com", the base
will be "dc=foobar,dc=com".

Add a LDAP section in the config file
-------------------------------------

The config file usually is /etc/ravada.conf. Add this configuration:

::

    ldap:
        admin_group: test.admin.group
        admin_user:
            dn: cn=Directory Manager
            password: thepasswordyouusedwhensetup-ds
        base: 'dc=foobar,dc=com'

Insert one test user
--------------------

The ravada backend script allows creating users in the LDAP

.. prompt:: bash

    sudo ./bin/rvd_back.pl --add-user-ldap jimmy.mcnulty
