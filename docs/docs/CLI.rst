Ravada CLI
==========

There are some things you can do from the CLI with Ravada.

This document is a work in progress. If you are interested in documenting
more any feature `let us know  <https://ravada.upc.edu/#help>`_.

Help
----

.. prompt:: bash

    sudo rvd_back --help

LDAP
----

You can execute some LDAP actions from the command line.

Test LDAP connection
~~~~~~~~~~~~~~~~~~~~

If you wonder if Ravada is able to access correctly to your LDAP server
use the *--test-ldap* flag. First it will try to connect, then you can
type an username and password to confirm it is a valid user.

::

    $ sudo rvd_back --test-ldap
    Connection to LDAP ok
    login: jimmy.mcnulty
    password: whatever
    LOGIN OK bind

Create LDAP user
~~~~~~~~~~~~~~~~

Add a new entry in your LDAP server. Warning the password will be shown in the
clear.

.. prompt :: bash

    $ sudo rvd_back --add-user-ldap jimmy.mcnulty

Create LDAP group
~~~~~~~~~~~~~~~~~

Add a new group in your LDAP server. These are POSIX groups with member uids
inside.

.. prompt :: bash

    $ sudo rvd_back --add-group-ldap staff

Add users to LDAP groups
~~~~~~~~~~~~~~~~~~~~~~~~

Once you have users and groups in your LDAP server you can easily add member entries
to a group. *Warning* : the user must have logged in at least once.

A list of known LDAP groups will be shown. If the user is already member of a group
it will be flagged with a *YES*. Type the name of the new group you want the
user to belong to:

.. prompt :: bash

    $ rvd_back --add-user-group jimmy.mcnulty
    - staff :
    - cops : YES
    - students :
    - teachers :
    Add user to LDAP group: teachers

Daily Hibernating and Stopping
------------------------------

With the CLI you can set automatic hibernation and shutdown of idle
virtual machines. Check the documentation about
`Automatic Daily Operations <https://ravada.readthedocs.io/en/latest/docs/Automatic_daily_operations.html>`_.
