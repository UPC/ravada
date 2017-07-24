Configure LDAP Authentication
=============================

Ravada can use LDAP as the authencation engine.

Example: All users
------------------

All the users in the LDAP can have access to ravada:

::

  ldap:
    server: 192.168.1.44
    port: 636
    base: dc=domain,dc=com
    admin_user:
        dn: cn=admin.user,dc=domain,dc=com
        password: secretpassword


Example: Group of users
-----------------------

Allow only a group of users to access ravada:

::

  ldap:
    server: 192.168.1.44
    port: 636
    base: ou=users,ou=groupname,dc=upc,dc=edu
    admin_user:
        dn: cn=admin.user,dc=domain,dc=com
        password: secretpassword

