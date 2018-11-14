Authentication with Active Directory
====================================

This feature is experimental and only can be used if you
have a development release of Ravada.

Install Modules
---------------

.. prompt:: bash

    sudo apt-get install libtest-spelling-perl
    sudo apt-get install cpanminus
    sudo cpanm Auth::ActiveDirectory

Configure Ravada
----------------

Add this entries to the file /etc/ravada.conf. The tag *ActiveDirectoy* must be
at first level without indentations, the other tags must be space-indented. The
port is optional.

::

    ActiveDirectory:
        host: thehost
        port: 389
        domain: thedomain
        principal: whatever it is, it must be set

Run
---

Restart the rvd_front service and try to login

Admin Users
-----------

Admin users must be set from the management tool once they have logged in.

Todo
----

- Admin users: how to find if an user is admin ? Maybe some kind of LDAP group ?
- Create users
- Create groups
- Remove users
- Remove groups
