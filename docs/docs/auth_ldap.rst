Configure LDAP Authentication
=============================

Ravada can use LDAP as the authencation engine.

Configuration
-------------

The configuration file is /etc/ravada.conf. The format is YML, make sure you
edit this file with spaces, no tabs.

Add a section ldap like this:

::

  ldap:
    server: 192.168.1.44
    port: 389 # or 636 for secure connections
    secure: 0 # defaults to 1 if port is 636
    base: dc=domain,dc=com
    admin_user:
        dn: cn=admin.user,dc=domain,dc=com
        password: secretpassword


The _secure_ setting is optional. It defaults to 0 for port 389 (ldap) and to 1 for
port 636 ( ldaps ). It can be enabled so secure connections can be forced for other
ports.

The LDAP admin user can be a low level account with minimal privileges.

Another optional setting can be used to force the authentication method.
By default Ravada tries first to bind to the LDAP as the user. If that fails
then it
tries to match the encrypted password. You can force the method
with:

::

  auth: all # defaults to all, can be all, bind, match

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


Example: Posix Group
-----------------------

If you have all your users under a main OU (e.g. ou=users, dc=domain, dc=com), you can use Posix Groups (https://ldapwiki.com/wiki/PosixGroup) to create a list of users that can access to your Ravada instance, using their memberUid attribute. This allows you grant or remove access to ravada to some users without modify your LDAP structure.

::

  ldap:
    server: 192.168.1.44
    port: 636
    base: ou=users,ou=groupname,dc=upc,dc=edu
    ravada_posix_group: cn=ravada,ou=groups,dc=domain,dc=com
    admin_user: 
        dn: cn=admin.user,dc=domain,dc=com
        password: secretpassword

In the example, cn=ravada,ou=groups,dc=domain,dc=com is a Posix Group in your LDAP server. It should contain the memberUid's of the users allowed to access to Ravada:

::

  dn: cn=ravada,ou=groups,dc=domain,dc=com
    objectclass: posixGroup
    memberUid: user1
    memberUid: user2
    memberUid: user3


Example: Attribute Filter
-------------------------

In this example, only the users that have pass a filter can login:

::

  ldap:
    server: 192.168.1.44
    port: 636
    base: dc=domain,dc=com
    filter: campus=North
    admin_user:
        dn: cn=admin.user,dc=domain,dc=com
        password: secretpassword
