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


Example: Posix Group
-----------------------

If you have all your users under a main OU (e.g. ou=users, dc=domain, dc=com), you can use Posix Groups (https://ldapwiki.com/wiki/PosixGroup) to create a list of users that can access to your Ravada instance, using their memberUid attribute. This allows you grant or remove access to ravada to some users without modify your LDAP structure.

::

  ldap:
    server: 192.168.1.44
    port: 636
    base: ou=users,ou=groupname,dc=upc,dc=edu
    ravada_posix_group: 
    admin_user: cn=ravada,ou=groups,dc=domain,dc=com
        dn: cn=admin.user,dc=domain,dc=com
        password: secretpassword

In the example, cn=ravada,ou=groups,dc=domain,dc=com is a Posix Group in your LDAP server. It should contain the memberUid's of the users allowed to access to Ravada:

::

  dn: cn=ravada,ou=groups,dc=domain,dc=com
    objectclass: posixGroup
    memberUid: user1
    memberUid: user2
    memberUid: user3
